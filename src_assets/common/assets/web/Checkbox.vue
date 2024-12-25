<script setup>
import {computed} from 'vue'

const model = defineModel({required: true});
const slots = defineSlots();
const props = defineProps({
  class: {
    type: String,
    default: ""
  },
  desc: {
    type: String,
    default: null
  },
  id: {
    type: String,
    required: true
  },
  label: {
    type: String,
    default: null
  },
  localePrefix: {
    type: String,
    default: "missing-prefix"
  },
  checkedByDef: {
    type: Boolean,
    default: false
  },
  uncheckedByDef: {
    type: Boolean,
    default: false
  },
  thrutyValues: {
    type: Array,
    default: () => [
      true,
      1,
      "true",
      "1",
      "enabled",
      "enable",
      "yes",
      "on"
    ]
  },
  falsyValues: {
    type: Array,
    default: () => [
      false,
      0,
      "false",
      "0",
      "disabled",
      "disable",
      "no",
      "off"
    ]
  }
});

// Add the mandatory class values
const extendedClassStr = (() => {
  let values = props.class.split(" ");
  if (!values.includes("form-check")) {
    values.push("form-check");
  }
  return values.join(" ");
})();

const labelField = props.label ?? `${props.localePrefix}.${props.id}`;
const descField = props.desc ?? `${props.localePrefix}.${props.id}_desc`;
const showDesc = props.desc !== "" || Object.entries(slots).length > 0;
const showDefValue = props.checkedByDef || props.uncheckedByDef;
const defValue = props.checkedByDef === props.uncheckedByDef ? "INVALID" :
    props.checkedByDef ? "_common.enabled_def_cbox" : "_common.disabled_def_cbox";

const realValue = computed({
  // getter
  get() {
    // Check if model value has a value, and if there's a value, we check if it's a truthy value or a falsy value,
    // and return either true or false. If there's no value, or the value is not in each list of values,
    // if checkedByDef (checked by default) is true, return true, otherwise return false. And we should the following error message:
    // console.error(`Checkbox ${props.id}:${labelField} with value ${model.value} did not match any acceptable pattern!`);

    let currentState = model.value;
    if (currentState === undefined || currentState === null || currentState === '') {
      return props.checkedByDef;
    }

    if (typeof currentState === "string") {
      currentState = currentState.toLowerCase().trim();
    }

    if (props.thrutyValues.includes(currentState)) {
      return true;
    }

    if (props.falsyValues.includes(currentState)) {
      return false;
    }

    console.error(`Checkbox ${props.id}:${labelField} with value ${model.value} did not match any acceptable pattern!`);
    return props.checkedByDef;
  },
  // setter
  set(newValue) {
    model.value = newValue;
  }
});

</script>

<template>
  <div :class="extendedClassStr">
    <label :for="props.id" :class="`form-check-label${showDesc ? ' mb-2' : ''}`">
      {{ $t(labelField) }}
      <div class="mt-0 form-text" v-if="showDefValue">
        {{ $t(defValue) }}
      </div>
    </label>
    <input type="checkbox"
           class="form-check-input"
           :id="props.id"
           v-model="realValue"/>
    <div class="form-text" v-if="showDesc">
      {{ $t(descField) }}
      <slot></slot>
    </div>
  </div>
</template>
