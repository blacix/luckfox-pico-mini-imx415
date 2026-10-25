#ifndef A_EYE_BRIGHTNESS_METRICS_H
#define A_EYE_BRIGHTNESS_METRICS_H

#include <cstdint>

namespace night_vision {

// Common result returned by either the JPEG-processing or rkipc-patch path.
// Luma and percentile values use an 8-bit range: 0 is black, 255 is white.
struct BrightnessMetrics {
	uint16_t source_width = 0;
	uint16_t source_height = 0;
	uint16_t sample_width = 0;
	uint16_t sample_height = 0;
	uint64_t samples = 0;
	double mean_luma = 0.0;
	uint8_t p10_luma = 0;
	uint8_t p50_luma = 0;
	uint8_t p90_luma = 0;
	uint8_t min_luma = 0;
	uint8_t max_luma = 0;
};

} // namespace night_vision

#endif // A_EYE_BRIGHTNESS_METRICS_H
