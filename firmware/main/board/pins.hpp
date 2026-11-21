// SPDX-License-Identifier: MIT
#pragma once
#include <array>
#include <cstdint>
namespace aim {
// 公开硬件连接事实；键序按面板从上到下、从左到右。
inline constexpr int buzzer_pin=1, power_pin=2, pixel_pin=3, battery_pin=4;
inline constexpr int touch_pin=7, joy_y_pin=9, joy_x_pin=10;
inline constexpr int encoder_key_pin=11, encoder_b_pin=12, encoder_a_pin=13;
inline constexpr int clock_pin=14, usb_dm_pin=19, usb_dp_pin=20, load_pin=21;
inline constexpr int charge_pin=41, standby_pin=42, enable_pin=47, data_pin=48;
inline constexpr std::array<int,3> indicator_pins={40,39,38}; // 上、中、下，低有效
inline constexpr std::array<uint8_t,13> key_bits={9,15,7,8,11,14,3,4,10,13,6,5,12};
inline constexpr std::array<uint8_t,6> agent_pixels={20,19,15,16,17,18};
inline constexpr std::array<uint8_t,7> command_pixels={14,13,12,11,8,9,10};
inline constexpr std::array<const char*,13> key_ids={
    "AG00","AG01","AG02","AG03","AG04","AG05",
    "ACT06","ACT07","ACT08","ACT09","ACT10","ACT11","ACT12"};
inline constexpr unsigned pixel_count=21;
}
