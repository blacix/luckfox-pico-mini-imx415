#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <dirent.h>
#include <cmath>
#include <iostream>
#include <sstream>
#include "rkipc_isp.h"
#include <string>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {

constexpr char kMeasurementApp[] = "/usr/bin/night-vision-measurement";
constexpr char kV4l2Ctl[] = "/usr/bin/v4l2-ctl";
constexpr char kVideo4Linux[] = "/sys/class/video4linux";
constexpr char kImx415Service[] = "/etc/init.d/S99a-eye-cam";
constexpr char kLedDirectory[] = "/sys/class/leds/pwm0_led";
constexpr char kGpioExport[] = "/sys/class/gpio/export";
constexpr char kGpioDirectory[] = "/sys/class/gpio/gpio116";
constexpr unsigned int kShutterGpio = 116;
constexpr char kLogFile[] = "/tmp/night-vision.log";
#if !RKIPC_NIGHT_MODE
constexpr char kSaturationStateFile[] = "/run/a-eye-day-saturation";
#endif
constexpr double kDefaultNightOnThreshold = 75.0;
constexpr double kDefaultDayOnThreshold = 75.0;
constexpr double kDefaultDayP90Minimum = 110.0;
constexpr double kDefaultDayP90Maximum = 210.0;
constexpr double kDefaultNightLedMeanCompensation = 20.0;
constexpr unsigned int kDefaultIntervalSeconds = 2;
constexpr unsigned int kDefaultModeSettleSeconds = 10;
constexpr unsigned int kDefaultSwitchSamplesRequired = 2;
constexpr unsigned int kDefaultLedIntensityPercent = 10;
constexpr double kV4l2ScoreScale = 2.55; // 255 * 10 ms reference exposure

volatile sig_atomic_t g_running = 1;

struct Options {
 std::string measurement_method = "v4l2";
 std::string v4l2_device;
 // Initial score thresholds based on SC3336 readings. IMX415 with IR-cut
 // and IR LED enabled still needs measurement and calibration.
 double v4l2_night_on = 100.0;
 double v4l2_day_on = 500.0;
 double v4l2_led_compensation = 0.0;
 double night_exposure_threshold_seconds = 0.0;
 double day_gain_max = 0.0;
	double night_on_threshold = kDefaultNightOnThreshold;
	double day_on_threshold = kDefaultDayOnThreshold;
	double day_p90_minimum = kDefaultDayP90Minimum;
	double day_p90_maximum = kDefaultDayP90Maximum;
	double night_led_mean_compensation = kDefaultNightLedMeanCompensation;
	unsigned int interval_seconds = kDefaultIntervalSeconds;
	unsigned int mode_settle_seconds = kDefaultModeSettleSeconds;
	unsigned int switch_samples_required = kDefaultSwitchSamplesRequired;
	unsigned int led_intensity_percent = kDefaultLedIntensityPercent;
};

struct BrightnessSample {
	double mean_y = 0.0;
	double p90_y = 0.0;
	double score = 0.0;
	double exposure_seconds = 0.0;
	double linear_gain = 0.0;
	bool v4l2 = false;
};

enum class Mode { Day, Night };

#if RKIPC_NIGHT_MODE
struct GrayscaleState {
	bool mode_known = false;
	bool night_mode = false;
	std::string last_error;
};
#else
struct GrayscaleState {
	bool original_known = false;
	int original_value = 0;
	bool grayscale_applied = false;
	std::string last_error;
};
#endif

void handle_signal(int) { g_running = 0; }

void log_message(const std::string &message) {
	std::time_t now = std::time(nullptr);
	std::tm local_time{};
	localtime_r(&now, &local_time);
	char timestamp[32]{};
	std::strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", &local_time);
	std::ofstream log(kLogFile, std::ios::out | std::ios::app);
	if (log)
		log << timestamp << ' ' << message << '\n';
}

bool write_value(const std::string &path, const std::string &value) {
	std::ofstream output(path.c_str());
	if (!output)
		return false;
	output << value << '\n';
	return output.good();
}

bool read_integer(const std::string &path, int &value) {
	std::ifstream input(path.c_str());
	return static_cast<bool>(input >> value);
}

void sleep_seconds(unsigned int seconds) {
	while (g_running && seconds > 0) {
		const unsigned int portion = seconds > 1 ? 1 : seconds;
		::sleep(portion);
		seconds -= portion;
	}
}

bool prepare_gpio() {
	if (access(kGpioDirectory, F_OK) != 0) {
		write_value(kGpioExport, std::to_string(kShutterGpio));
		for (int attempt = 0; attempt < 10 && access(kGpioDirectory, F_OK) != 0; ++attempt)
			usleep(100000);
	}
	if (access(kGpioDirectory, F_OK) != 0 ||
	    !write_value(std::string(kGpioDirectory) + "/direction", "out")) {
		log_message("GPIO116 is unavailable or could not be configured as output");
		return false;
	}
	return true;
}

bool parse_json_number(const std::string &text, const std::string &key,
	               double &value) {
	const std::string::size_type key_pos = text.find(key);
	if (key_pos == std::string::npos)
		return false;

	const char *start = text.c_str() + key_pos + key.size();
	char *end = nullptr;
	errno = 0;
	const double parsed = std::strtod(start, &end);
	if (errno || end == start || parsed < 0.0 || parsed > 255.0)
		return false;
	value = parsed;
	return true;
}

bool parse_brightness_sample(const std::string &text,
	                     BrightnessSample &sample) {
	return parse_json_number(text, "\"mean_y\":", sample.mean_y) &&
	       parse_json_number(text, "\"p90_y\":", sample.p90_y);
}

bool capture_brightness_sample(BrightnessSample &sample, std::string &error) {
	int descriptors[2];
	if (pipe(descriptors) != 0) {
		error = std::string("create JPEG app pipe: ") + std::strerror(errno);
		return false;
	}

	const pid_t child = fork();
	if (child < 0) {
		error = std::string("fork JPEG app: ") + std::strerror(errno);
		close(descriptors[0]);
		close(descriptors[1]);
		return false;
	}
	if (child == 0) {
		close(descriptors[0]);
		dup2(descriptors[1], STDOUT_FILENO);
		dup2(descriptors[1], STDERR_FILENO);
		close(descriptors[1]);
		execl(kMeasurementApp, kMeasurementApp, static_cast<char *>(nullptr));
		_exit(127);
	}

	close(descriptors[1]);
	std::string output;
	char buffer[512];
	for (;;) {
		const ssize_t count = read(descriptors[0], buffer, sizeof(buffer));
		if (count > 0) {
			if (output.size() < 8192)
				output.append(buffer, static_cast<size_t>(count));
			continue;
		}
		if (count < 0 && errno == EINTR) {
			if (g_running)
				continue;
			kill(child, SIGTERM);
		}
		break;
	}
	close(descriptors[0]);

	int status = 0;
	while (waitpid(child, &status, 0) < 0) {
		if (errno == EINTR)
			continue;
		error = std::string("wait for JPEG app: ") + std::strerror(errno);
		return false;
	}
	if (!g_running)
		return false;
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
		const std::string::size_type newline = output.find('\n');
		error = output.substr(0, newline);
		if (error.empty())
			error = "JPEG app exited unsuccessfully";
		return false;
	}
	if (!parse_brightness_sample(output, sample)) {
		error = "could not parse mean_y and p90_y from JPEG app output";
		return false;
	}
	return true;
}

bool read_v4l2_controls(const Options &options, BrightnessSample &sample,
			std::string &error) {
	std::string device = options.v4l2_device;
	std::string sensor;
	if (device.empty()) {
		DIR *dir = opendir(kVideo4Linux);
		if (!dir) { error = "cannot scan video4linux devices"; return false; }
		struct dirent *entry;
		while ((entry = readdir(dir)) != nullptr) {
			if (std::strncmp(entry->d_name, "v4l-subdev", 10) != 0) continue;
			std::ifstream name(std::string(kVideo4Linux) + "/" + entry->d_name + "/name");
			std::string value;
			if (!(name >> value)) continue;
			if (value.find("sc3336") != std::string::npos ||
			    value.find("imx415") != std::string::npos) {
				device = std::string("/dev/") + entry->d_name;
				sensor = value;
				break;
			}
		}
		closedir(dir);
	} else {
		std::string base = device.substr(device.find_last_of('/') + 1);
		std::ifstream name(std::string(kVideo4Linux) + "/" + base + "/name");
		name >> sensor;
	}
	if (device.empty()) { error = "no SC3336 or IMX415 V4L2 subdevice found"; return false; }
	int pipefd[2];
	if (pipe(pipefd) != 0) { error = "cannot create v4l2-ctl pipe"; return false; }
	pid_t child = fork();
	if (child < 0) { close(pipefd[0]); close(pipefd[1]); error = "cannot fork v4l2-ctl"; return false; }
	if (child == 0) {
		dup2(pipefd[1], STDOUT_FILENO); dup2(pipefd[1], STDERR_FILENO);
		close(pipefd[0]); close(pipefd[1]);
		execl(kV4l2Ctl, kV4l2Ctl, "-d", device.c_str(), "--get-ctrl=exposure,analogue_gain,pixel_rate,horizontal_blanking", static_cast<char *>(nullptr));
		_exit(127);
	}
	close(pipefd[1]);
	std::string output; char buf[256]; ssize_t n;
	while ((n = read(pipefd[0], buf, sizeof(buf))) > 0) if (output.size() < 4096) output.append(buf, static_cast<size_t>(n));
	close(pipefd[0]); int status = 0;
	while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
	if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) { error = "v4l2-ctl could not read sensor controls: " + output; return false; }
	auto get = [&output](const char *key, double &v) {
		std::istringstream lines(output); std::string line;
		while (std::getline(lines, line)) { auto p = line.find(':'); if (p == std::string::npos) continue;
			if (line.substr(0, p).find(key) != std::string::npos) { char *end = nullptr; v = std::strtod(line.c_str()+p+1, &end); return end != line.c_str()+p+1; } }
		return false;
	};
	double exp_raw=0, gain_raw=0, pixel_rate=0, hblank=0;
	if (!get("exposure", exp_raw) || !get("analogue_gain", gain_raw) || !get("pixel_rate", pixel_rate) || !get("horizontal_blanking", hblank) || pixel_rate <= 0) { error = "missing or invalid exposure, gain, pixel_rate, or horizontal_blanking from v4l2-ctl"; return false; }
	const bool sc = sensor.find("sc3336") != std::string::npos;
	const bool imx = sensor.find("imx415") != std::string::npos;
	if (!sc && !imx) { error = "unsupported sensor for V4L2 exposure conversion: " + sensor; return false; }
	const double width = sc ? 2304.0 : 1944.0;
	sample.exposure_seconds = (sc ? exp_raw / 16.0 : exp_raw) * (width + hblank) / pixel_rate;
	// SC3336 exposes total gain in 1/128 units. IMX415's 0..0xf0 register
	// maps gain as 256/(256-register), per the sensor's conversion curve.
	sample.linear_gain = sc ? gain_raw / 128.0 : 256.0 / (256.0 - gain_raw);
	if (sample.exposure_seconds <= 0 || sample.linear_gain <= 0) { error = "sensor returned nonpositive exposure or gain"; return false; }
	sample.score = kV4l2ScoreScale / (sample.exposure_seconds * sample.linear_gain);
	sample.v4l2 = true;
	sample.mean_y = sample.score;
	return true;
}

bool set_day_mode(Mode &mode, bool log_transition, bool shutter_control) {
	if (!write_value(std::string(kLedDirectory) + "/brightness", "0")) {
		log_message("could not turn off the IR LED");
		return false;
	}
	if (shutter_control)
		sleep_seconds(1);
	if (shutter_control &&
	    !write_value(std::string(kGpioDirectory) + "/value", "1")) {
		log_message("could not set GPIO116 high for day mode");
		return false;
	}
	const bool changed = mode != Mode::Day;
	mode = Mode::Day;
	if (log_transition && changed) {
		log_message(shutter_control ? "day mode: shutter high, IR LED off"
					    : "day mode: IR LED off (shutter unchanged)");
	}
	return true;
}

bool set_night_mode(Mode &mode, int led_brightness, int led_max,
		    bool shutter_control) {
	if (shutter_control &&
	    !write_value(std::string(kGpioDirectory) + "/value", "0")) {
		log_message("could not set GPIO116 low for night mode");
		return false;
	}
	if (shutter_control)
		sleep_seconds(1);
	if (!g_running ||
	    !write_value(std::string(kLedDirectory) + "/brightness",
	                 std::to_string(led_brightness))) {
		if (shutter_control)
			write_value(std::string(kGpioDirectory) + "/value", "1");
		log_message("could not turn on the IR LED");
		return false;
	}
	mode = Mode::Night;
	log_message(std::string("night mode: ") +
		     (shutter_control ? "shutter low, " : "shutter unchanged, ") +
		     "IR LED brightness " + std::to_string(led_brightness) + "/" +
		     std::to_string(led_max));
	return true;
}

#if RKIPC_NIGHT_MODE
void apply_grayscale_mode(bool night, GrayscaleState &state) {
	if (state.mode_known && state.night_mode == night)
		return;
	std::string error;
	if (!rkipc_isp::set_night_to_day(0, night, error)) {
		state.mode_known = false;
		if (error != state.last_error) {
			log_message("could not request RKIPC night-to-day mode: " + error);
			state.last_error = error;
		}
		return;
	}
	state.mode_known = true;
	state.night_mode = night;
	state.last_error.clear();
	log_message(night ? "requested RKIPC night mode (AIE black-and-white)"
			  : "requested RKIPC day mode (AIE effect off)");
}
#else
bool load_saturation_state(GrayscaleState &state) {
	int value = 0;
	if (!read_integer(kSaturationStateFile, value))
		return false;
	if (value < 0 || value > 100) {
		log_message("saved daytime saturation is invalid; ignoring it");
		unlink(kSaturationStateFile);
		return false;
	}
	state.original_known = true;
	state.original_value = value;
	return true;
}

void log_saturation_error(GrayscaleState &state, const std::string &error) {
	if (error != state.last_error) {
		log_message("could not update RKIPC saturation: " + error);
		state.last_error = error;
	}
}

void apply_grayscale_mode(bool night, GrayscaleState &state) {
	std::string error;
	if (night) {
		if (!state.original_known) {
			int current = 0;
			if (!rkipc_isp::get_saturation(0, current, error)) {
				log_saturation_error(state, error);
				return;
			}
			if (!write_value(kSaturationStateFile, std::to_string(current))) {
				log_saturation_error(state,
						     "cannot save the daytime saturation in /run");
				return;
			}
			state.original_value = current;
			state.original_known = true;
		}
		if (state.grayscale_applied)
			return;
		if (!rkipc_isp::set_saturation(0, 0, error)) {
			log_saturation_error(state, error);
			return;
		}
		state.grayscale_applied = true;
		state.last_error.clear();
		log_message("night image set to grayscale; saved daytime saturation " +
			    std::to_string(state.original_value));
		return;
	}

	if (!state.original_known)
		return;
	if (!rkipc_isp::set_saturation(0, state.original_value, error)) {
		log_saturation_error(state, error);
		return;
	}
	state.grayscale_applied = false;
	state.original_known = false;
	state.last_error.clear();
	unlink(kSaturationStateFile);
	log_message("day image restored to saturation " +
		    std::to_string(state.original_value));
}
#endif

void cleanup(bool shutter_control, GrayscaleState &grayscale_state) {
	apply_grayscale_mode(false, grayscale_state);
	write_value(std::string(kLedDirectory) + "/brightness", "0");
	if (shutter_control)
		write_value(std::string(kGpioDirectory) + "/value", "1");
	log_message(shutter_control ? "stopped: shutter high and IR LED off"
				    : "stopped: IR LED off (shutter unchanged)");
}

bool parse_number(const char *text, double &value) {
	char *end = nullptr;
	errno = 0;
	value = std::strtod(text, &end);
	return !errno && end != text && *end == '\0' && value >= 0.0 && value <= 255.0;
}

bool parse_options(int argc, char **argv, Options &options) {
	for (int i = 1; i < argc; ++i) {
		const std::string argument(argv[i]);
		if (argument == "--measurement-method" || argument == "--v4l2-device") {
			if (++i >= argc) return false;
			if (argument == "--measurement-method") options.measurement_method = argv[i];
			else options.v4l2_device = argv[i];
			continue;
		}
		if (argument == "--v4l2-night-on" || argument == "--v4l2-day-on" ||
		    argument == "--v4l2-led-compensation" ||
		    argument == "--night-exposure-threshold-sec" || argument == "--day-gain-max") {
			if (++i >= argc) return false;
			char *end = nullptr; errno = 0;
			double value = std::strtod(argv[i], &end);
			if (errno || end == argv[i] || *end || !std::isfinite(value) || value < 0) return false;
			if (argument == "--v4l2-night-on") options.v4l2_night_on = value;
			else if (argument == "--v4l2-day-on") options.v4l2_day_on = value;
			else if (argument == "--v4l2-led-compensation") options.v4l2_led_compensation = value;
			else if (argument == "--night-exposure-threshold-sec") options.night_exposure_threshold_seconds = value;
			else options.day_gain_max = value;
			continue;
		}
		if (argument == "--night-on" || argument == "--day-on" ||
		    argument == "--day-p90-min" || argument == "--day-p90-max" ||
		    argument == "--night-led-mean-compensation") {
			if (i + 1 >= argc)
				return false;
			double value = 0.0;
			if (!parse_number(argv[++i], value))
				return false;
			if (argument == "--night-on")
				options.night_on_threshold = value;
			else if (argument == "--day-on")
				options.day_on_threshold = value;
			else if (argument == "--day-p90-min")
				options.day_p90_minimum = value;
			else if (argument == "--day-p90-max")
				options.day_p90_maximum = value;
			else
				options.night_led_mean_compensation = value;
		} else if (argument == "--interval-sec" ||
		           argument == "--mode-settle-sec" ||
		           argument == "--samples-required" ||
		           argument == "--led-intensity-percent") {
			if (i + 1 >= argc)
				return false;
			char *end = nullptr;
			errno = 0;
			const unsigned long value = std::strtoul(argv[++i], &end, 10);
			const unsigned long maximum =
			    (argument == "--interval-sec" || argument == "--mode-settle-sec")
			        ? 3600
			        : 100;
			const bool zero_not_allowed =
			    value == 0 && argument != "--led-intensity-percent" &&
			    argument != "--mode-settle-sec";
			if (errno || end == argv[i] || *end || zero_not_allowed || value > maximum)
				return false;
			if (argument == "--interval-sec")
				options.interval_seconds = static_cast<unsigned int>(value);
			else if (argument == "--mode-settle-sec")
				options.mode_settle_seconds = static_cast<unsigned int>(value);
			else if (argument == "--samples-required")
				options.switch_samples_required = static_cast<unsigned int>(value);
			else
				options.led_intensity_percent = static_cast<unsigned int>(value);
		} else {
			return false;
		}
	}
	// LED compensation is subtracted from night-mode measurements, so the
	// effective raw boundary for returning to day is day_on + compensation.
	return (options.measurement_method == "v4l2" || options.measurement_method == "jpeg") &&
	       options.v4l2_night_on < options.v4l2_day_on + options.v4l2_led_compensation &&
	       options.night_on_threshold <
	           options.day_on_threshold + options.night_led_mean_compensation &&
	       options.day_p90_minimum < options.day_p90_maximum &&
	       options.night_led_mean_compensation <= 255.0;
}

void print_usage(const char *program) {
	std::cerr << "Usage: " << program
	          << " [--measurement-method v4l2|jpeg] [--v4l2-device /dev/v4l-subdevN]"
	             " [--v4l2-night-on SCORE] [--v4l2-day-on SCORE]"
	             " [--v4l2-led-compensation SCORE]"
	             " [--night-exposure-threshold-sec SECONDS] [--day-gain-max GAIN]"
	             " [--night-on LUMA] [--day-on LUMA]"
	             " [--day-p90-min LUMA] [--day-p90-max LUMA]"
	             " [--night-led-mean-compensation LUMA]"
	             " [--interval-sec N] [--mode-settle-sec N]"
	             " [--samples-required N]"
	             " [--led-intensity-percent PERCENT]\n";
}

} // namespace

int main(int argc, char **argv) {
	Options options;
	if (!parse_options(argc, argv, options)) {
		print_usage(argv[0]);
		return 2;
	}
	const bool shutter_control = access(kImx415Service, X_OK) == 0;

	std::ofstream(kLogFile, std::ios::out | std::ios::trunc).close();
	struct sigaction action{};
	action.sa_handler = handle_signal;
	sigemptyset(&action.sa_mask);
	sigaction(SIGINT, &action, nullptr);
	sigaction(SIGTERM, &action, nullptr);

	if (options.measurement_method == "jpeg" && access(kMeasurementApp, X_OK) != 0) {
		log_message(std::string("missing image measurement executable: ") + kMeasurementApp);
		return 1;
	}
	if (shutter_control && !prepare_gpio())
		return 1;

	int led_max = 0;
	if (!read_integer(std::string(kLedDirectory) + "/max_brightness", led_max) ||
	    led_max <= 0 || access((std::string(kLedDirectory) + "/brightness").c_str(), W_OK) != 0) {
		log_message("PWM LED interface is unavailable or has an invalid maximum");
		return 1;
	}
	const int led_night_brightness =
	    (led_max * static_cast<int>(options.led_intensity_percent) + 50) / 100;
	GrayscaleState grayscale_state;
#if !RKIPC_NIGHT_MODE
	load_saturation_state(grayscale_state);
#endif

	Mode mode = Mode::Night;
	if (!set_day_mode(mode, false, shutter_control))
		return 1;
	const bool v4l2_method = options.measurement_method == "v4l2";
	const std::string measurement_description = v4l2_method
		? "monitoring V4L2 score every " + std::to_string(options.interval_seconds) +
		  "s; night below " + std::to_string(options.v4l2_night_on) +
		  ", day above " + std::to_string(options.v4l2_day_on) +
		  "; night-mode day-return subtracts V4L2 score compensation " +
		  std::to_string(options.v4l2_led_compensation)
		: "monitoring mean_y every " + std::to_string(options.interval_seconds) +
		  "s; night below " + std::to_string(options.night_on_threshold) +
		  ", day above " + std::to_string(options.day_on_threshold) +
		  " with p90_y in [" + std::to_string(options.day_p90_minimum) +
		  ", " + std::to_string(options.day_p90_maximum) +
		  "]; night-mode day-return subtracts mean_y LED compensation " +
		  std::to_string(options.night_led_mean_compensation);
	log_message(std::string("measurement method ") + options.measurement_method + "; " +
		     (shutter_control ? "shutter control enabled; "
					     : "shutter control disabled; LED-only mode; ") +
		     measurement_description +
	             "; switching requires " +
	             std::to_string(options.switch_samples_required) +
	             " consecutive samples; mode settle " +
	             std::to_string(options.mode_settle_seconds) + "s; LED intensity " +
	             std::to_string(options.led_intensity_percent) + "% (" +
	             std::to_string(led_night_brightness) + "/" + std::to_string(led_max) + ")");

	std::string last_error;
	unsigned int night_candidate_count = 0;
	unsigned int day_candidate_count = 0;
	while (g_running) {
		bool mode_changed = false;
		BrightnessSample sample;
		std::string error;
		const bool sampled = options.measurement_method == "v4l2"
			? read_v4l2_controls(options, sample, error)
			: capture_brightness_sample(sample, error);
		if (!sampled) {
			night_candidate_count = 0;
			day_candidate_count = 0;
#if RKIPC_NIGHT_MODE
			grayscale_state.mode_known = false;
#else
			grayscale_state.grayscale_applied = false;
#endif
			if (g_running && error != last_error) {
				log_message("no valid " + options.measurement_method + " sample: " + error);
				last_error = error;
			}
		} else {
			if (!last_error.empty()) {
				log_message(options.measurement_method + " sampling recovered");
				last_error.clear();
			}
			const double night_threshold = sample.v4l2 ? options.v4l2_night_on : options.night_on_threshold;
			const double day_threshold = sample.v4l2 ? options.v4l2_day_on : options.day_on_threshold;
			const double led_compensation = sample.v4l2 ? options.v4l2_led_compensation : options.night_led_mean_compensation;
			if (sample.v4l2)
				log_message("V4L2 exposure=" + std::to_string(sample.exposure_seconds) +
					    "s gain=" + std::to_string(sample.linear_gain) +
					    " score=" + std::to_string(sample.score));
			const bool night_candidate = sample.score < night_threshold ||
			    (sample.v4l2 && options.night_exposure_threshold_seconds > 0 && sample.exposure_seconds >= options.night_exposure_threshold_seconds);
			// Night-mode samples include IR LED light. Subtract its configured
			// estimate only for the return-to-day mean check; p90 remains raw.
			const bool day_candidate =
			    (sample.score - led_compensation > day_threshold &&
			     (sample.v4l2 || (sample.p90_y >= options.day_p90_minimum && sample.p90_y <= options.day_p90_maximum))) ||
			    (sample.v4l2 && options.day_gain_max > 0 && sample.linear_gain < options.day_gain_max);

			if (mode == Mode::Day) {
				day_candidate_count = 0;
				night_candidate_count = night_candidate
				                            ? night_candidate_count + 1
				                            : 0;
				if (night_candidate_count >= options.switch_samples_required) {
					mode_changed = set_night_mode(mode, led_night_brightness,
							      led_max, shutter_control);
					night_candidate_count = 0;
				}
			} else {
				night_candidate_count = 0;
				day_candidate_count = day_candidate
				                          ? day_candidate_count + 1
				                          : 0;
				if (day_candidate_count >= options.switch_samples_required) {
					mode_changed = set_day_mode(mode, true, shutter_control);
					day_candidate_count = 0;
				}
			}
		}
		apply_grayscale_mode(mode == Mode::Night, grayscale_state);
		sleep_seconds(mode_changed ? options.mode_settle_seconds
					   : options.interval_seconds);
	}

	cleanup(shutter_control, grayscale_state);
	return 0;
}
