#ifndef A_EYE_RKIPC_SATURATION_H
#define A_EYE_RKIPC_SATURATION_H

#include <string>

namespace rkipc_saturation {

bool get(int camera_id, int &value, std::string &error);
bool set(int camera_id, int value, std::string &error);

} // namespace rkipc_saturation

#endif
