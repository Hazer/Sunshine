<script setup>
import { inject, onBeforeUpdate, onMounted, ref, Ref } from 'vue'

const props = defineProps({
  selectedDisplay: Object,
  displays: Array
})

/**
 *
 * @type {Ref<HTMLCanvasElement | undefined>}
 */
const canvasElement = ref();

const state = ref()

function makeState(windowWidth, displays) {
  const mergedFrames = mergeFrames(displays);
  const totalSize = calcTotalSize(mergedFrames);

  const totalAreaWidth = totalSize.width;
  const totalAreaHeight = totalSize.height;

  const windowHeight = (totalAreaHeight / totalAreaWidth) * windowWidth // Calculate proportional window height

  // Scale coordinates and sizes
  return {
    size: totalSize,
    windowHeight: windowHeight,
    resizedFrames: scaleCoordinatesAndSize(mergedFrames, totalAreaWidth, totalAreaHeight, windowWidth, windowHeight)
  };
}

function mergeFrames(displays) {
  const mergedFrames = [];
  displays.forEach(display => {
    const cs = display.current_settings
    const origin = cs.origin
    const res = cs.mode.resolution
    const frame = {
      id: display.id,
      x: origin.x,
      y: origin.y,
      width: res.width,
      height: res.height
    };
    let merged = false;
    mergedFrames.forEach((mergedFrame, index) => {
      // Check for overlap
      if (
          frame.x < mergedFrame.x + mergedFrame.width &&
          frame.x + frame.width > mergedFrame.x &&
          frame.y < mergedFrame.y + mergedFrame.height &&
          frame.y + frame.height > mergedFrame.y
      ) {
        // Merge overlapping frames
        mergedFrame.x = Math.min(frame.x, mergedFrame.x);
        mergedFrame.y = Math.min(frame.y, mergedFrame.y);
        mergedFrame.width = Math.max(frame.x + frame.width, mergedFrame.x + mergedFrame.width) - mergedFrame.x;
        mergedFrame.height = Math.max(frame.y + frame.height, mergedFrame.y + mergedFrame.height) - mergedFrame.y;
        merged = true;
      }
    });
    if (!merged) {
      mergedFrames.push({...frame});
    }
  });
  return mergedFrames;
}

function calcTotalSize(mergedFrames) {
  let minX = Number.MAX_SAFE_INTEGER;
  let maxX = Number.MIN_SAFE_INTEGER;
  let maxY = Number.MIN_SAFE_INTEGER;
  mergedFrames.forEach(frame => {
    minX = Math.min(minX, frame.x);
    maxX = Math.max(maxX, frame.x + frame.width);
    maxY = Math.max(maxY, frame.y + frame.height);
  });
  const width = maxX - minX;
  return {width, height: maxY};
}

function toCanvasCoordinate(resizedFrame, windowWidth, windowHeight) {
  let canvasX, canvasY, canvasWidth, canvasHeight;

  // Calculate positive x-coordinate relative to the canvas
  if (resizedFrame.x >= 0) {
    canvasX = Math.min(resizedFrame.x, windowWidth);
  } else {
    canvasX = Math.max(0, windowWidth + resizedFrame.x);
  }

  // Calculate positive y-coordinate relative to the canvas
  canvasY = Math.min(resizedFrame.y, windowHeight);

  // Calculate positive width relative to the canvas
  canvasWidth = Math.min(resizedFrame.width, windowWidth - canvasX);

  // Calculate positive height relative to the canvas
  canvasHeight = Math.min(resizedFrame.height, windowHeight - canvasY);

  return mirrorHorizontally(
      {
        id: resizedFrame.id,
        x: canvasX,
        y: canvasY,
        width: canvasWidth,
        height: canvasHeight
      },
      windowWidth
  );
}

function mirrorHorizontally(frame, canvasWidth) {
  return {
    id: frame.id,
    x: canvasWidth - frame.x - frame.width,
    y: frame.y,
    width: frame.width,
    height: frame.height
  };
}

function scaleCoordinatesAndSize(frames, totalAreaWidth, totalAreaHeight, windowWidth, windowHeight) {
  return frames.map(frame => {
    // Scale x coordinate
    const newFrame = frame;

    newFrame.id = frame.id;
    // Scale x coordinate
    newFrame.x = (newFrame.x / totalAreaWidth) * windowWidth;
    // Scale y coordinate
    newFrame.y = (newFrame.y / totalAreaHeight) * windowHeight;
    // Scale width
    newFrame.width = (newFrame.width / totalAreaWidth) * windowWidth;
    // Scale height
    newFrame.height = (newFrame.height / totalAreaHeight) * windowHeight;
    return newFrame
  });
}

/**
 *
 * @type {Ref<CanvasRenderingContext2D | undefined>}
 */
const context = ref();

function renderCanvas() {
  if (canvasElement.value) {
    const windowWidth = canvasElement.value.width // Desired window width
    const stateReady = makeState(windowWidth, props.displays)
    state.value = stateReady
    canvasElement.value.height = stateReady.windowHeight;

    render(stateReady, windowWidth, inject('selectedDisplay').value);
  }
}

onBeforeUpdate(() => {
  renderCanvas()
})

onMounted(() => {
  // Get canvas context. If 'getContext' returns 'null', set to 'undefined', so that it conforms to the Ref typing
  context.value = canvasElement.value?.getContext('2d') || undefined;

  renderCanvas()
});

function render(state, windowWidth, selectedDisplay) {
  if (!context.value || !state) {
    console.log("aborted rendering")
    return;
  }

  const frames = state.resizedFrames;
  const ctx = context.value

  function drawMonitor(monitor) {
    const coord = toCanvasCoordinate(monitor, windowWidth, state.windowHeight);
    const selected = monitor.id === selectedDisplay.id

    if (selected) {
      ctx.lineWidth = 2
      ctx.strokeStyle = 'cyan'
      ctx.fillStyle = '#198754'
    } else {
      ctx.lineWidth = 1
      ctx.strokeStyle = 'rgba(33, 37, 41, .75)'
      ctx.fillStyle = 'cyan'
    }

    ctx.fillRect(
        coord.x,
        coord.y,
        coord.width,
        coord.height
    );

    ctx.strokeRect(
        coord.x,
        coord.y,
        coord.width,
        coord.height
    )

    if (selected) {
      let offset = {
        x: (coord.x + coord.width / 2),
        y: (coord.y + coord.height / 2)
      }
      const text = 'Selected'
      const textMeasure = ctx.measureText(text)
      ctx.fillStyle = 'white'
      ctx.fillText(text, offset.x - textMeasure.width / 2, offset.y - textMeasure.actualBoundingBoxAscent / 2)
    }
  }

  for (let i = 0; i < frames.length; i++) {
    drawMonitor(frames[i])
  }
}
</script>

<template>
  <canvas ref="canvasElement" width="480" height="320">
    Sorry, your browser does not support canvas.
  </canvas>
</template>

<style scoped>

</style>
