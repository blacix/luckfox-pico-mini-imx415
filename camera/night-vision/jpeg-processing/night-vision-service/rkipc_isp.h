#ifndef A_EYE_RKIPC_ISP_H
#define A_EYE_RKIPC_ISP_H

#include <string>

namespace rkipc_isp {

bool get_saturation(int camera_id, int &value, std::string &error);
bool set_saturation(int camera_id, int value, std::string &error);
bool set_night_to_day(int camera_id, bool night, std::string &error);

} // namespace rkipc_isp

#endif
