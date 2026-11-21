// SPDX-License-Identifier: MIT
#pragma once
#include "input_logic.hpp"
#include "pins.hpp"
#include "protocol/protocol.hpp"
#include "driver/rmt_tx.h"
#include "driver/rmt_encoder.h"
#include "driver/touch_sens.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include <functional>
namespace aim {
enum class InputKind { Key, Encoder, EncoderPress, Joystick, Touch, Power };
struct InputEvent { InputKind kind; int index; bool pressed; };
struct Snapshot {
    uint16_t key_register=0xffff, pressed_mask=0;
    int joy_x=0,joy_y=0,battery_mv=0,battery_percent=0;
    bool battery_valid=false,charging=false,standby=false,touched=false;
    uint32_t touch_raw=0,touch_baseline=0;
};
class Board {
public:
    esp_err_t begin();
    void poll(int64_t now_ms,const std::function<void(InputEvent)>&);
    void pixel(unsigned index,uint32_t rgb,float brightness=0.15f);
    void region(unsigned group,uint32_t rgb,float brightness=0.15f);
    void indicators(uint8_t mask);
    esp_err_t show();
    void render(const Lights&,int64_t now_ms);
    bool tone(unsigned hz,unsigned duration_ms,unsigned volume);
    const Snapshot& snapshot() const { return state; }
private:
    Snapshot state{};
    adc_oneshot_unit_handle_t adc=nullptr;
    adc_cali_handle_t battery_calibration=nullptr;
    touch_sensor_handle_t touch=nullptr;
    touch_channel_handle_t touch_channel=nullptr;
    rmt_channel_handle_t rmt=nullptr;
    rmt_encoder_handle_t encoder=nullptr;
    std::array<rmt_symbol_word_t,pixel_count*24+1> symbols{};
    std::array<uint32_t,pixel_count> colors{};
    std::array<Debounce,16> buttons{};
    Encoder quadrature{};
    Direction last_direction=Direction::Center;
    int center_x=2048,center_y=2048;
    int64_t last_adc=-1000,last_battery=-1000,tone_until=0;
    bool dirty=true;
    uint16_t scan_keys();
};
}
