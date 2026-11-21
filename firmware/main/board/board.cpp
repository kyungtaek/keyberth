// SPDX-License-Identifier: MIT
#include "board.hpp"
#include "render.hpp"
#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_check.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "soc/touch_sensor_channel.h"
#include <algorithm>
#include <cmath>
namespace aim {
namespace {
gpio_num_t pin(int p) { return static_cast<gpio_num_t>(p); }
esp_err_t output(int p,int value) {
    ESP_RETURN_ON_ERROR(gpio_set_level(pin(p),value),"basic","GPIO value");
    return gpio_set_direction(pin(p),GPIO_MODE_OUTPUT);
}
esp_err_t input(int p) {
    ESP_RETURN_ON_ERROR(gpio_set_direction(pin(p),GPIO_MODE_INPUT),"basic","GPIO input");
    return gpio_set_pull_mode(pin(p),GPIO_PULLUP_ONLY);
}
}
esp_err_t Board::begin() {
    for(int p:{clock_pin,load_pin,enable_pin,pixel_pin,buzzer_pin}) {
        ESP_RETURN_ON_ERROR(output(p,p==load_pin||p==enable_pin),"basic","output");
    }
    for(int p:indicator_pins) ESP_RETURN_ON_ERROR(output(p,1),"basic","indicator");
    for(int p:{data_pin,encoder_a_pin,encoder_b_pin,encoder_key_pin,power_pin,charge_pin,standby_pin}) {
        ESP_RETURN_ON_ERROR(input(p),"basic","input");
    }
    adc_oneshot_unit_init_cfg_t unit{};unit.unit_id=ADC_UNIT_1;
    ESP_RETURN_ON_ERROR(adc_oneshot_new_unit(&unit,&adc),"basic","ADC unit");
    adc_oneshot_chan_cfg_t channel{};channel.atten=ADC_ATTEN_DB_12;channel.bitwidth=ADC_BITWIDTH_12;
    for(adc_channel_t ch:{ADC_CHANNEL_3,ADC_CHANNEL_8,ADC_CHANNEL_9})
        ESP_RETURN_ON_ERROR(adc_oneshot_config_channel(adc,ch,&channel),"basic","ADC channel");
    adc_cali_curve_fitting_config_t cal{};cal.unit_id=ADC_UNIT_1;cal.chan=ADC_CHANNEL_3;
    cal.atten=ADC_ATTEN_DB_12;cal.bitwidth=ADC_BITWIDTH_12;
    // 无 eFuse 校准时不把粗略原始值伪装为电压。
    if(adc_cali_create_scheme_curve_fitting(&cal,&battery_calibration)!=ESP_OK) battery_calibration=nullptr;
    ESP_RETURN_ON_ERROR(adc_oneshot_read(adc,ADC_CHANNEL_9,&center_x),"basic","joystick X");
    ESP_RETURN_ON_ERROR(adc_oneshot_read(adc,ADC_CHANNEL_8,&center_y),"basic","joystick Y");

    touch_sensor_sample_config_t sampling[TOUCH_SAMPLE_CFG_NUM]={
        TOUCH_SENSOR_V2_DEFAULT_SAMPLE_CONFIG(1,TOUCH_VOLT_LIM_L_0V5,TOUCH_VOLT_LIM_H_2V2)};
    touch_sensor_config_t tc=TOUCH_SENSOR_DEFAULT_BASIC_CONFIG(1,sampling);
    ESP_RETURN_ON_ERROR(touch_sensor_new_controller(&tc,&touch),"basic","touch controller");
    touch_channel_config_t cc{};cc.charge_speed=TOUCH_CHARGE_SPEED_7;
    cc.init_charge_volt=TOUCH_INIT_CHARGE_VOLT_DEFAULT;
    ESP_RETURN_ON_ERROR(touch_sensor_new_channel(touch,TOUCH_PAD_GPIO7_CHANNEL,&cc,&touch_channel),"basic","touch channel");
    touch_sensor_filter_config_t filter=TOUCH_SENSOR_DEFAULT_FILTER_CONFIG();
    ESP_RETURN_ON_ERROR(touch_sensor_config_filter(touch,&filter),"basic","touch filter");
    ESP_RETURN_ON_ERROR(touch_sensor_enable(touch),"basic","touch enable");
    for(int i=0;i<5;++i) ESP_RETURN_ON_ERROR(touch_sensor_trigger_oneshot_scanning(touch,1000),"basic","touch sample");
    uint32_t baseline[TOUCH_SAMPLE_CFG_NUM]{};
    ESP_RETURN_ON_ERROR(touch_channel_read_data(touch_channel,TOUCH_CHAN_DATA_TYPE_BENCHMARK,baseline),"basic","touch baseline");
    state.touch_baseline=baseline[0];
    ESP_RETURN_ON_ERROR(touch_sensor_start_continuous_scanning(touch),"basic","touch scan");

    ledc_timer_config_t timer{};timer.speed_mode=LEDC_LOW_SPEED_MODE;timer.duty_resolution=LEDC_TIMER_10_BIT;
    timer.timer_num=LEDC_TIMER_0;timer.freq_hz=2700;timer.clk_cfg=LEDC_AUTO_CLK;
    ESP_RETURN_ON_ERROR(ledc_timer_config(&timer),"basic","buzzer timer");
    ledc_channel_config_t pwm{};pwm.gpio_num=buzzer_pin;pwm.speed_mode=LEDC_LOW_SPEED_MODE;
    pwm.channel=LEDC_CHANNEL_0;pwm.timer_sel=LEDC_TIMER_0;
    ESP_RETURN_ON_ERROR(ledc_channel_config(&pwm),"basic","buzzer output");
    rmt_tx_channel_config_t tx{};tx.gpio_num=pin(pixel_pin);tx.clk_src=RMT_CLK_SRC_DEFAULT;
    tx.resolution_hz=10000000;tx.mem_block_symbols=64;tx.trans_queue_depth=1;
    ESP_RETURN_ON_ERROR(rmt_new_tx_channel(&tx,&rmt),"basic","RMT channel");
    rmt_copy_encoder_config_t copy{};
    ESP_RETURN_ON_ERROR(rmt_new_copy_encoder(&copy,&encoder),"basic","RMT encoder");
    ESP_RETURN_ON_ERROR(rmt_enable(rmt),"basic","RMT enable");
    return show();
}
uint16_t Board::scan_keys() {
    gpio_set_level(pin(enable_pin),1);gpio_set_level(pin(load_pin),0);esp_rom_delay_us(2);
    gpio_set_level(pin(load_pin),1);esp_rom_delay_us(2);gpio_set_level(pin(enable_pin),0);
    uint16_t word=0;
    for(unsigned bit=0;bit<16;++bit) {
        word|=uint16_t(gpio_get_level(pin(data_pin))<<bit);
        if(bit!=15) { gpio_set_level(pin(clock_pin),1);esp_rom_delay_us(2);gpio_set_level(pin(clock_pin),0);esp_rom_delay_us(2); }
    }
    gpio_set_level(pin(enable_pin),1);return word;
}
void Board::poll(int64_t now,const std::function<void(InputEvent)>& emit) {
    state.key_register=scan_keys();
    for(unsigned k=0;k<key_bits.size();++k) {
        if(buttons[k].update(!(state.key_register&(1U<<key_bits[k])),now))
            emit({InputKind::Key,int(k),buttons[k].stable});
        if(buttons[k].stable) state.pressed_mask|=1U<<k;
        else state.pressed_mask&=~(1U<<k);
    }
    const int rotation=quadrature.update(uint8_t((gpio_get_level(pin(encoder_a_pin))<<1)|gpio_get_level(pin(encoder_b_pin))));
    if(rotation)emit({InputKind::Encoder,rotation,true});
    if(buttons[13].update(!gpio_get_level(pin(encoder_key_pin)),now))emit({InputKind::EncoderPress,0,buttons[13].stable});
    if(buttons[14].update(!gpio_get_level(pin(power_pin)),now))emit({InputKind::Power,0,buttons[14].stable});
    if(now-last_adc>=10) {
        last_adc=now;
        int x=0,y=0;
        if(adc_oneshot_read(adc,ADC_CHANNEL_9,&x)==ESP_OK&&adc_oneshot_read(adc,ADC_CHANNEL_8,&y)==ESP_OK) {
            state.joy_x=x;state.joy_y=y;
            auto d=direction(x-center_x,y-center_y);
            if(d!=last_direction) {last_direction=d;emit({InputKind::Joystick,int(d),d!=Direction::Center});}
        }
        uint32_t raw[TOUCH_SAMPLE_CFG_NUM]{};
        if(touch_channel_read_data(touch_channel,TOUCH_CHAN_DATA_TYPE_SMOOTH,raw)==ESP_OK) {
            state.touch_raw=raw[0];
            bool active=raw[0]>state.touch_baseline+std::max(uint32_t(1),state.touch_baseline/20);
            if(buttons[15].update(active,now)) {state.touched=buttons[15].stable;emit({InputKind::Touch,0,state.touched});}
        }
    }
    if(now-last_battery>=1000) {
        last_battery=now;int raw=0,mv=0;
        state.battery_valid=battery_calibration&&adc_oneshot_read(adc,ADC_CHANNEL_3,&raw)==ESP_OK&&
            adc_cali_raw_to_voltage(battery_calibration,raw,&mv)==ESP_OK;
        if(state.battery_valid) {state.battery_mv=mv*2;state.battery_percent=std::clamp((state.battery_mv-3300)*100/900,0,100);}
        state.charging=!gpio_get_level(pin(charge_pin));state.standby=!gpio_get_level(pin(standby_pin));
    }
    if(tone_until&&now>=tone_until) {ledc_stop(LEDC_LOW_SPEED_MODE,LEDC_CHANNEL_0,0);tone_until=0;}
}
void Board::pixel(unsigned i,uint32_t rgb,float b) {
    if(i>=pixel_count||!std::isfinite(b))return;
    b=std::clamp(b,0.0f,1.0f);
    uint32_t scaled=(uint32_t(((rgb>>16)&255)*b)<<16)|(uint32_t(((rgb>>8)&255)*b)<<8)|uint32_t((rgb&255)*b);
    if(colors[i]!=scaled) {colors[i]=scaled;dirty=true;}
}
void Board::region(unsigned g,uint32_t rgb,float b) {
    if(g==0)for(unsigned i=0;i<8;++i)pixel(i,rgb,b);
    else if(g==1)for(auto i:command_pixels)pixel(i,rgb,b);
    else if(g<8)pixel(agent_pixels[g-2],rgb,b);
}
void Board::indicators(uint8_t mask) {for(unsigned i=0;i<3;++i)gpio_set_level(pin(indicator_pins[i]),!(mask&(1U<<i)));}
esp_err_t Board::show() {
    if(!dirty)return ESP_OK;
    size_t at=0;
    for(auto rgb:colors) {
        uint32_t grb=((rgb&0xff00)<<8)|((rgb>>16)<<8)|(rgb&255);
        for(int bit=23;bit>=0;--bit) {
            auto& s=symbols[at++];bool one=grb&(1U<<bit);
            // WS2812B-2020-V6 数据手册时序，10 MHz 单位。
            s.duration0=one?7:3;s.level0=1;s.duration1=one?6:10;s.level1=0;
        }
    }
    auto& reset=symbols[at];reset.duration0=1500;reset.level0=0;reset.duration1=1500;reset.level1=0;
    rmt_transmit_config_t cfg{};
    ESP_RETURN_ON_ERROR(rmt_transmit(rmt,encoder,symbols.data(),sizeof(symbols),&cfg),"basic","pixels");
    ESP_RETURN_ON_ERROR(rmt_tx_wait_all_done(rmt,100),"basic","pixels wait");dirty=false;return ESP_OK;
}
void Board::render(const Lights& lights,int64_t now) {
    render_pixels(lights,now,[&](unsigned i,uint32_t rgb,float brightness){pixel(i,rgb,brightness);});
}
bool Board::tone(unsigned hz,unsigned duration,unsigned volume) {
    if(hz<100||hz>10000||duration>2000)return false;
    if(!duration||!volume) {ledc_stop(LEDC_LOW_SPEED_MODE,LEDC_CHANNEL_0,0);tone_until=0;return true;}
    if(ledc_set_freq(LEDC_LOW_SPEED_MODE,LEDC_TIMER_0,hz)!=ESP_OK)return false;
    if(ledc_set_duty(LEDC_LOW_SPEED_MODE,LEDC_CHANNEL_0,(std::min(volume,100u)*512+50)/100)!=ESP_OK||ledc_update_duty(LEDC_LOW_SPEED_MODE,LEDC_CHANNEL_0)!=ESP_OK)return false;
    tone_until=esp_timer_get_time()/1000+duration;return true;
}
}
