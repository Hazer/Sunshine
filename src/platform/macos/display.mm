/**
 * @file src/platform/macos/display.mm
 * @brief todo
 */
#include "src/platform/common.h"
#include "src/platform/macos/av_img_t.h"
#include "src/platform/macos/av_video.h"
#include "src/platform/macos/nv12_zero_device.h"

#include "src/config.h"
#include "src/logging.h"

// Avoid conflict between AVFoundation and libavutil both defining AVMediaType
#define AVMediaType AVMediaType_FFmpeg
#include "src/video.h"
#undef AVMediaType

namespace fs = std::filesystem;

namespace platf {
  using namespace std::literals;

  av_img_t::~av_img_t() {
    if (pixel_buffer != NULL) {
      CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    }

    if (sample_buffer != nullptr) {
      CFRelease(sample_buffer);
    }

    data = nullptr;
  }

  struct av_display_t: public display_t {
    AVVideo *av_capture {};
    CGDirectDisplayID display_id {};

    ~av_display_t() override {
      [av_capture release];
    }

    capture_e
    capture(const push_captured_image_cb_t &push_captured_image_cb, const pull_free_image_cb_t &pull_free_image_cb, bool *cursor) override {
      auto signal = [av_capture capture:^(CMSampleBufferRef sampleBuffer) {
        CFRetain(sampleBuffer);

        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

        std::shared_ptr<img_t> img_out;
        if (!pull_free_image_cb(img_out)) {
          // got interrupt signal
          // returning false here stops capture backend
          return false;
        }
        auto av_img = std::static_pointer_cast<av_img_t>(img_out);

        if (av_img->pixel_buffer != nullptr)
          CVPixelBufferUnlockBaseAddress(av_img->pixel_buffer, 0);

        if (av_img->sample_buffer != nullptr)
          CFRelease(av_img->sample_buffer);

        av_img->sample_buffer = sampleBuffer;
        av_img->pixel_buffer = pixelBuffer;
        img_out->data = (uint8_t *) CVPixelBufferGetBaseAddress(pixelBuffer);

        img_out->width = (int) CVPixelBufferGetWidth(pixelBuffer);
        img_out->height = (int) CVPixelBufferGetHeight(pixelBuffer);
        img_out->row_pitch = (int) CVPixelBufferGetBytesPerRow(pixelBuffer);
        img_out->pixel_pitch = img_out->row_pitch / img_out->width;

        if (!push_captured_image_cb(std::move(img_out), true)) {
          // got interrupt signal
          // returning false here stops capture backend
          return false;
        }

        return true;
      }];

      // FIXME: We should time out if an image isn't returned for a while
      dispatch_semaphore_wait(signal, DISPATCH_TIME_FOREVER);

      return capture_e::ok;
    }

    std::shared_ptr<img_t>
    alloc_img() override {
      return std::make_shared<av_img_t>();
    }

    std::unique_ptr<avcodec_encode_device_t>
    make_avcodec_encode_device(pix_fmt_e pix_fmt) override {
      if (pix_fmt == pix_fmt_e::yuv420p) {
        av_capture.pixelFormat = kCVPixelFormatType_32BGRA;

        return std::make_unique<avcodec_encode_device_t>();
      }
      else if (pix_fmt == pix_fmt_e::nv12 || pix_fmt == pix_fmt_e::p010) {
        auto device = std::make_unique<nv12_zero_device>();

        device->init(static_cast<void *>(av_capture), pix_fmt, setResolution, setPixelFormat);

        return device;
      }
      else {
        BOOST_LOG(error) << "Unsupported Pixel Format."sv;
        return nullptr;
      }
    }

    int
    dummy_img(img_t *img) override {
      auto signal = [av_capture capture:^(CMSampleBufferRef sampleBuffer) {
        auto av_img = (av_img_t *) img;

        CFRetain(sampleBuffer);

        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

        // XXX: next_img->img should be moved to a smart pointer with
        // the CFRelease as custom deallocator
        if (av_img->pixel_buffer != nullptr)
          CVPixelBufferUnlockBaseAddress(((av_img_t *) img)->pixel_buffer, 0);

        if (av_img->sample_buffer != nullptr)
          CFRelease(av_img->sample_buffer);

        av_img->sample_buffer = sampleBuffer;
        av_img->pixel_buffer = pixelBuffer;
        img->data = (uint8_t *) CVPixelBufferGetBaseAddress(pixelBuffer);

        img->width = (int) CVPixelBufferGetWidth(pixelBuffer);
        img->height = (int) CVPixelBufferGetHeight(pixelBuffer);
        img->row_pitch = (int) CVPixelBufferGetBytesPerRow(pixelBuffer);
        img->pixel_pitch = img->row_pitch / img->width;

        // returning false here stops capture backend
        return false;
      }];

      dispatch_semaphore_wait(signal, DISPATCH_TIME_FOREVER);

      return 0;
    }

    /**
     * A bridge from the pure C++ code of the hwdevice_t class to the pure Objective C code.
     *
     * display --> an opaque pointer to an object of this class
     * width --> the intended capture width
     * height --> the intended capture height
     */
    static void
    setResolution(void *display, int width, int height) {
      [static_cast<AVVideo *>(display) setFrameWidth:width frameHeight:height];
    }

    static void
    setPixelFormat(void *display, OSType pixelFormat) {
      static_cast<AVVideo *>(display).pixelFormat = pixelFormat;
    }
  };

  std::shared_ptr<display_t>
  display(platf::mem_type_e hwdevice_type, const std::string &display_name, const video::config_t &config) {
    if (hwdevice_type != platf::mem_type_e::system && hwdevice_type != platf::mem_type_e::videotoolbox) {
      BOOST_LOG(error) << "Could not initialize display with the given hw device type."sv;
      return nullptr;
    }

    auto display = std::make_shared<av_display_t>();

    // Default to main display
    display->display_id = CGMainDisplayID();

    // Print all displays available with it's name and id
    auto display_array = [AVVideo displayNames];
    BOOST_LOG(info) << "Detecting displays"sv;
    for (NSDictionary *item in display_array) {
      NSNumber *display_id = item[@"id"];
      // We need show display's product name and corresponding display number given by user
      NSString *name = item[@"displayName"];
      // We are using CGGetActiveDisplayList that only returns active displays so hardcoded connected value in log to true
      BOOST_LOG(info) << "Detected display: "sv << name.UTF8String << " (id: "sv << [NSString stringWithFormat:@"%@", display_id].UTF8String << ") connected: true"sv;
      if (!display_name.empty() && std::atoi(display_name.c_str()) == [display_id unsignedIntValue]) {
        display->display_id = [display_id unsignedIntValue];
      }
    }
    BOOST_LOG(info) << "Configuring selected display ("sv << display->display_id << ") to stream"sv;

    display->av_capture = [[AVVideo alloc] initWithDisplay:display->display_id frameRate:config.framerate];

    if (!display->av_capture) {
      BOOST_LOG(error) << "Video setup failed."sv;
      return nullptr;
    }

    display->width = display->av_capture.frameWidth;
    display->height = display->av_capture.frameHeight;
    // We also need set env_width and env_height for absolute mouse coordinates
    display->env_width = display->width;
    display->env_height = display->height;

    return display;
  }

  std::vector<std::string>
  display_names(mem_type_e hwdevice_type) {
    __block std::vector<std::string> display_names;

    auto display_array = [AVVideo displayNames];

    display_names.reserve([display_array count]);
    [display_array enumerateObjectsUsingBlock:^(NSDictionary *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
      NSString *name = obj[@"name"];
      display_names.emplace_back(name.UTF8String);
    }];

    return display_names;
  }

  /**
   * @brief Returns if GPUs/drivers have changed since the last call to this function.
   * @return `true` if a change has occurred or if it is unknown whether a change occurred.
   */
  bool
  needs_encoder_reenumeration() {
    // We don't track GPU state, so we will always reenumerate. Fortunately, it is fast on macOS.
    return true;
  }
}  // namespace platf
