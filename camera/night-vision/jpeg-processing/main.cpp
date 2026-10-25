/*
 * Capture one JPEG through the running RKIPC service and report reduced
 * image-brightness statistics as one JSON object on stdout.
 *
 * TJpgDec retains its upstream copyright and license notice in tjpgd.c.
 */

#include "tjpgd.h"
#include "../common/brightness_metrics.h"

#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <limits>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <utility>

namespace {

constexpr const char *kDefaultSocket = "/var/tmp/rkipc";
constexpr const char *kDefaultSnapshotDir = "/userdata/video0";
constexpr int kSnapshotRequestTimeoutSeconds = 8;
constexpr int kSnapshotPollIntervalMs = 100;
constexpr int kStableSnapshotObservations = 3;
constexpr size_t kJpegWorkBytes = 3500;
constexpr uint8_t kDecodeScale = 3; // 1/8-size output.

struct SnapshotInput {
	FILE *file;
};

struct FileStamp {
	std::string path;
	ino_t inode = 0;
	off_t size = 0;
	timespec modified{};
};

struct Brightness {
	uint64_t sum = 0;
	uint64_t samples = 0;
	std::array<uint64_t, 256> histogram{};
	uint8_t minimum = 255;
	uint8_t maximum = 0;
	unsigned int width = 0;
	unsigned int height = 0;
};

struct DecodeSession {
	SnapshotInput input;
	Brightness *brightness;
};

bool read_exact(int fd, void *buffer, size_t size) {
	auto *bytes = static_cast<uint8_t *>(buffer);
	size_t received = 0;
	while (received < size) {
		ssize_t count = read(fd, bytes + received, size - received);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			return false;
		received += static_cast<size_t>(count);
	}
	return true;
}

bool write_exact(int fd, const void *buffer, size_t size) {
	const auto *bytes = static_cast<const uint8_t *>(buffer);
	size_t written = 0;
	while (written < size) {
		ssize_t count = write(fd, bytes + written, size - written);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			return false;
		written += static_cast<size_t>(count);
	}
	return true;
}

bool request_snapshot(const std::string &socket_path, std::string &error) {
	sockaddr_un address{};
	if (socket_path.size() >= sizeof(address.sun_path)) {
		error = "RKIPC socket path is too long";
		return false;
	}

	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		error = std::string("create RKIPC socket: ") + strerror(errno);
		return false;
	}

	timeval timeout{};
	timeout.tv_sec = 3;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
	setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

	address.sun_family = AF_UNIX;
	memcpy(address.sun_path, socket_path.c_str(), socket_path.size() + 1);
	const socklen_t address_size =
	    static_cast<socklen_t>(offsetof(sockaddr_un, sun_path) + socket_path.size() + 1);
	if (connect(fd, reinterpret_cast<sockaddr *>(&address), address_size) < 0) {
		error = std::string("connect to RKIPC: ") + strerror(errno);
		close(fd);
		return false;
	}

	int status = -1;
	if (!read_exact(fd, &status, sizeof(status)) || status != 0) {
		error = "RKIPC did not accept the socket connection";
		close(fd);
		return false;
	}

	constexpr char function_name[] = "rk_take_photo";
	const int name_length = sizeof(function_name); // Include terminating NUL.
	if (!write_exact(fd, &name_length, sizeof(name_length)) ||
	    !write_exact(fd, function_name, sizeof(function_name))) {
		error = std::string("send snapshot request: ") + strerror(errno);
		close(fd);
		return false;
	}

	// The handler returns the capture status; the dispatcher then sends its
	// protocol acknowledgement as a second integer.
	int capture_status = -1;
	int dispatcher_status = -1;
	const bool got_reply = read_exact(fd, &capture_status, sizeof(capture_status)) &&
	                       read_exact(fd, &dispatcher_status, sizeof(dispatcher_status));
	close(fd);
	if (!got_reply) {
		error = std::string("read RKIPC snapshot response: ") + strerror(errno);
		return false;
	}
	if (dispatcher_status != 0) {
		error = "RKIPC rejected the snapshot command";
		return false;
	}
	if (capture_status != 0) {
		error = "RKIPC could not start snapshot capture (storage may not be mounted)";
		return false;
	}
	return true;
}

bool is_jpeg_name(const char *name) {
	const size_t length = strlen(name);
	return (length >= 5 && strcmp(name + length - 5, ".jpeg") == 0) ||
	       (length >= 4 && strcmp(name + length - 4, ".jpg") == 0);
}

bool get_newest_snapshot(const std::string &directory, FileStamp &newest) {
	DIR *dir = opendir(directory.c_str());
	if (!dir)
		return false;

	bool found = false;
	while (dirent *entry = readdir(dir)) {
		if (!is_jpeg_name(entry->d_name))
			continue;

		FileStamp candidate;
		candidate.path = directory + "/" + entry->d_name;
		struct stat info{};
		if (stat(candidate.path.c_str(), &info) < 0 || !S_ISREG(info.st_mode) ||
		    info.st_size <= 0)
			continue;
		candidate.inode = info.st_ino;
		candidate.size = info.st_size;
		candidate.modified = info.st_mtim;

		if (!found || candidate.modified.tv_sec > newest.modified.tv_sec ||
		    (candidate.modified.tv_sec == newest.modified.tv_sec &&
		     candidate.modified.tv_nsec > newest.modified.tv_nsec) ||
		    (candidate.modified.tv_sec == newest.modified.tv_sec &&
		     candidate.modified.tv_nsec == newest.modified.tv_nsec &&
		     candidate.path > newest.path)) {
			newest = std::move(candidate);
			found = true;
		}
	}
	closedir(dir);
	return found;
}

bool same_stamp(const FileStamp &left, const FileStamp &right) {
	return left.path == right.path && left.inode == right.inode &&
	       left.size == right.size && left.modified.tv_sec == right.modified.tv_sec &&
	       left.modified.tv_nsec == right.modified.tv_nsec;
}

bool wait_for_snapshot(const std::string &directory, const FileStamp *previous,
                       FileStamp &snapshot, std::string &error) {
	const auto deadline = std::chrono::steady_clock::now() +
	                      std::chrono::seconds(kSnapshotRequestTimeoutSeconds);
	FileStamp stable_stamp;
	int stable_observations = 0;

	while (std::chrono::steady_clock::now() < deadline) {
		FileStamp candidate;
		const bool exists = get_newest_snapshot(directory, candidate);
		const bool is_new = exists &&
		                    (!previous || !same_stamp(candidate, *previous));
		if (is_new) {
			if (stable_observations > 0 && same_stamp(candidate, stable_stamp)) {
				++stable_observations;
			} else {
				stable_stamp = candidate;
				stable_observations = 1;
			}
			if (stable_observations >= kStableSnapshotObservations) {
				snapshot = std::move(candidate);
				return true;
			}
		} else {
			stable_observations = 0;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(kSnapshotPollIntervalMs));
	}

	error = "timed out waiting for a completed JPEG in " + directory;
	return false;
}

size_t jpeg_input(JDEC *decoder, uint8_t *buffer, size_t count) {
	auto *session = static_cast<DecodeSession *>(decoder->device);
	if (!session || !session->input.file)
		return 0;
	if (buffer)
		return fread(buffer, 1, count, session->input.file);
	return fseek(session->input.file, static_cast<long>(count), SEEK_CUR) == 0 ? count : 0;
}

int collect_brightness(JDEC *decoder, void *bitmap, JRECT *rect) {
	auto *session = static_cast<DecodeSession *>(decoder->device);
	Brightness *brightness = session ? session->brightness : nullptr;
	if (!brightness || !bitmap || !rect)
		return 0;

	const unsigned int width = rect->right - rect->left + 1;
	const unsigned int height = rect->bottom - rect->top + 1;
	const auto *pixels = static_cast<const uint8_t *>(bitmap);
	const size_t pixel_count = static_cast<size_t>(width) * height;

	for (size_t index = 0; index < pixel_count; ++index) {
		// TJpgDec is configured for RGB888. Use integer BT.601 luma weights.
		const unsigned int red = pixels[index * 3];
		const unsigned int green = pixels[index * 3 + 1];
		const unsigned int blue = pixels[index * 3 + 2];
		const uint8_t luma = static_cast<uint8_t>(
		    (77 * red + 150 * green + 29 * blue + 128) >> 8);
		brightness->sum += luma;
		++brightness->samples;
		++brightness->histogram[luma];
		brightness->minimum = std::min(brightness->minimum, luma);
		brightness->maximum = std::max(brightness->maximum, luma);
	}

	brightness->width = std::max(brightness->width,
	                             static_cast<unsigned int>(rect->right) + 1);
	brightness->height = std::max(brightness->height,
	                              static_cast<unsigned int>(rect->bottom) + 1);
	return 1;
}

uint8_t percentile(const Brightness &brightness, unsigned int percentile_value) {
	const uint64_t target =
	    (brightness.samples * percentile_value + 99) / 100;
	uint64_t accumulated = 0;
	for (size_t value = 0; value < brightness.histogram.size(); ++value) {
		accumulated += brightness.histogram[value];
		if (accumulated >= target)
			return static_cast<uint8_t>(value);
	}
	return 255;
}

bool decode_snapshot(const FileStamp &snapshot, Brightness &brightness,
	                 uint16_t &source_width, uint16_t &source_height,
	                 std::string &error) {
	DecodeSession session{{fopen(snapshot.path.c_str(), "rb")}, &brightness};
	if (!session.input.file) {
		error = std::string("open snapshot: ") + strerror(errno);
		return false;
	}

	JDEC decoder{};
	alignas(std::max_align_t) std::array<uint8_t, kJpegWorkBytes> work{};
	JRESULT result = jd_prepare(&decoder, jpeg_input, work.data(), work.size(), &session);
	if (result != JDR_OK) {
		error = "TJpgDec could not prepare JPEG (error " + std::to_string(result) + ")";
		fclose(session.input.file);
		return false;
	}
	source_width = decoder.width;
	source_height = decoder.height;
	result = jd_decomp(&decoder, collect_brightness, kDecodeScale);
	fclose(session.input.file);
	if (result != JDR_OK || brightness.samples == 0) {
		error = "TJpgDec could not decode JPEG (error " + std::to_string(result) + ")";
		return false;
	}
	return true;
}

bool capture_and_report(const std::string &socket_path,
	                    const std::string &snapshot_directory,
	                    bool keep_snapshot) {
	FileStamp previous;
	const bool had_previous = get_newest_snapshot(snapshot_directory, previous);
	std::string error;
	if (!request_snapshot(socket_path, error)) {
		fprintf(stderr, "camera: %s\n", error.c_str());
		return false;
	}

	FileStamp snapshot;
	if (!wait_for_snapshot(snapshot_directory, had_previous ? &previous : nullptr,
	                       snapshot, error)) {
		fprintf(stderr, "camera: %s\n", error.c_str());
		return false;
	}

	Brightness brightness;
	uint16_t source_width = 0;
	uint16_t source_height = 0;
	if (!decode_snapshot(snapshot, brightness, source_width, source_height, error)) {
		fprintf(stderr, "camera: %s\n", error.c_str());
		return false;
	}

	night_vision::BrightnessMetrics metrics;
	metrics.source_width = source_width;
	metrics.source_height = source_height;
	metrics.sample_width = static_cast<uint16_t>(brightness.width);
	metrics.sample_height = static_cast<uint16_t>(brightness.height);
	metrics.samples = brightness.samples;
	metrics.mean_luma = static_cast<double>(brightness.sum) / brightness.samples;
	metrics.p10_luma = percentile(brightness, 10);
	metrics.p50_luma = percentile(brightness, 50);
	metrics.p90_luma = percentile(brightness, 90);
	metrics.min_luma = brightness.minimum;
	metrics.max_luma = brightness.maximum;
	printf("{\"source_width\":%u,\"source_height\":%u,"
	       "\"sample_width\":%u,\"sample_height\":%u,"
	       "\"samples\":%llu,\"mean_y\":%.3f,"
	       "\"p10_y\":%u,\"p50_y\":%u,\"p90_y\":%u,"
	       "\"min_y\":%u,\"max_y\":%u}\n",
	       metrics.source_width, metrics.source_height, metrics.sample_width,
	       metrics.sample_height, static_cast<unsigned long long>(metrics.samples),
	       metrics.mean_luma, metrics.p10_luma, metrics.p50_luma,
	       metrics.p90_luma, metrics.min_luma, metrics.max_luma);
	fflush(stdout);

	if (!keep_snapshot && unlink(snapshot.path.c_str()) < 0 && errno != ENOENT)
		fprintf(stderr, "camera: could not remove processed snapshot %s: %s\n",
		        snapshot.path.c_str(), strerror(errno));
	return true;
}

void usage(const char *program) {
	fprintf(stderr,
	        "Usage: %s [--socket PATH] [--snapshot-dir DIR] "
	        "[--interval-sec N] [--keep-snapshots]\n"
	        "Default: one capture from %s, snapshots in %s, then remove the "
	        "processed JPEG.\n",
	        program, kDefaultSocket, kDefaultSnapshotDir);
}

} // namespace

int main(int argc, char **argv) {
	std::string socket_path = kDefaultSocket;
	std::string snapshot_directory = kDefaultSnapshotDir;
	unsigned int interval_seconds = 0;
	bool keep_snapshots = false;

	for (int i = 1; i < argc; ++i) {
		const std::string argument(argv[i]);
		if (argument == "--keep-snapshots") {
			keep_snapshots = true;
		} else if ((argument == "--socket" || argument == "--snapshot-dir" ||
		            argument == "--interval-sec") && i + 1 < argc) {
			const std::string value(argv[++i]);
			if (argument == "--socket") {
				socket_path = value;
			} else if (argument == "--snapshot-dir") {
				snapshot_directory = value;
			} else {
				char *end = nullptr;
				errno = 0;
				const unsigned long parsed = strtoul(value.c_str(), &end, 10);
				if (errno || end == value.c_str() || *end ||
				    parsed > std::numeric_limits<unsigned int>::max()) {
					usage(argv[0]);
					return 2;
				}
				interval_seconds = static_cast<unsigned int>(parsed);
			}
		} else {
			usage(argv[0]);
			return 2;
		}
	}

	struct stat directory_info{};
	if (stat(snapshot_directory.c_str(), &directory_info) < 0 ||
	    !S_ISDIR(directory_info.st_mode)) {
		fprintf(stderr, "camera: snapshot directory is unavailable: %s\n",
		        snapshot_directory.c_str());
		return 1;
	}

	if (interval_seconds > 0 && interval_seconds < 2) {
		fprintf(stderr, "camera: --interval-sec must be at least 2 because RKIPC "
		                "names snapshots to one-second resolution\n");
		return 2;
	}

	do {
		if (!capture_and_report(socket_path, snapshot_directory, keep_snapshots))
			return 1;
		if (interval_seconds > 0)
			std::this_thread::sleep_for(std::chrono::seconds(interval_seconds));
	} while (interval_seconds > 0);

	return 0;
}
