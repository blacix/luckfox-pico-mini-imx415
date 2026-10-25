#include "rkipc_saturation.h"

#include <cerrno>
#include <cstring>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

namespace rkipc_saturation {
namespace {

constexpr char kSocketPath[] = "/var/tmp/rkipc";

bool send_all(int fd, const void *data, size_t size) {
	const char *bytes = static_cast<const char *>(data);
	size_t sent = 0;
	while (sent < size) {
		const ssize_t count = send(fd, bytes + sent, size - sent, MSG_NOSIGNAL);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			return false;
		sent += static_cast<size_t>(count);
	}
	return true;
}

bool receive_all(int fd, void *data, size_t size) {
	char *bytes = static_cast<char *>(data);
	size_t received = 0;
	while (received < size) {
		const ssize_t count = recv(fd, bytes + received, size - received, 0);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			return false;
		received += static_cast<size_t>(count);
	}
	return true;
}

int connect_to_rkipc(std::string &error) {
	const int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		error = std::string("create RKIPC socket: ") + std::strerror(errno);
		return -1;
	}

	timeval timeout{};
	timeout.tv_sec = 2;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
	setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

	struct sockaddr_un address{};
	address.sun_family = AF_UNIX;
	std::strncpy(address.sun_path, kSocketPath, sizeof(address.sun_path) - 1);
	if (connect(fd, reinterpret_cast<struct sockaddr *>(&address), sizeof(address)) != 0) {
		error = std::string("connect to RKIPC at ") + kSocketPath + ": " +
			std::strerror(errno);
		close(fd);
		return -1;
	}

	int server_status = -1;
	if (!receive_all(fd, &server_status, sizeof(server_status)) || server_status != 0) {
		error = "RKIPC socket handshake failed";
		close(fd);
		return -1;
	}
	return fd;
}

bool begin_call(int fd, const char *function, std::string &error) {
	const int name_size = static_cast<int>(std::strlen(function) + 1);
	if (!send_all(fd, &name_size, sizeof(name_size)) ||
	    !send_all(fd, function, static_cast<size_t>(name_size))) {
		error = std::string("send RKIPC function name: ") + std::strerror(errno);
		return false;
	}
	return true;
}

bool finish_call(int fd, int function_status, std::string &error) {
	int server_status = -1;
	const bool received = receive_all(fd, &server_status, sizeof(server_status));
	close(fd);
	if (!received) {
		error = std::string("read RKIPC response: ") + std::strerror(errno);
		return false;
	}
	if (function_status != 0 || server_status != 0) {
		error = "RKIPC rejected saturation request";
		return false;
	}
	return true;
}

} // namespace

bool get(int camera_id, int &value, std::string &error) {
	const int fd = connect_to_rkipc(error);
	if (fd < 0)
		return false;
	if (!begin_call(fd, "rk_isp_get_saturation", error)) {
		close(fd);
		return false;
	}
	if (!send_all(fd, &camera_id, sizeof(camera_id))) {
		error = std::string("send RKIPC camera id: ") + std::strerror(errno);
		close(fd);
		return false;
	}
	int function_status = -1;
	if (!receive_all(fd, &value, sizeof(value)) ||
	    !receive_all(fd, &function_status, sizeof(function_status))) {
		error = std::string("read RKIPC saturation: ") + std::strerror(errno);
		close(fd);
		return false;
	}
	if (!finish_call(fd, function_status, error))
		return false;
	if (value < 0 || value > 100) {
		error = "RKIPC returned saturation outside the 0-100 range";
		return false;
	}
	return true;
}

bool set(int camera_id, int value, std::string &error) {
	if (value < 0 || value > 100) {
		error = "saturation must be between 0 and 100";
		return false;
	}
	const int fd = connect_to_rkipc(error);
	if (fd < 0)
		return false;
	if (!begin_call(fd, "rk_isp_set_saturation", error)) {
		close(fd);
		return false;
	}
	if (!send_all(fd, &camera_id, sizeof(camera_id)) ||
	    !send_all(fd, &value, sizeof(value))) {
		error = std::string("send RKIPC saturation: ") + std::strerror(errno);
		close(fd);
		return false;
	}
	int function_status = -1;
	if (!receive_all(fd, &function_status, sizeof(function_status))) {
		error = std::string("read RKIPC saturation result: ") + std::strerror(errno);
		close(fd);
		return false;
	}
	return finish_call(fd, function_status, error);
}

} // namespace rkipc_saturation
