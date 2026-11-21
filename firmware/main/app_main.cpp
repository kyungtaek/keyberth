// SPDX-License-Identifier: MIT
#include "board/board.hpp"
#include "trial.hpp"
#include "preferences.hpp"
#include "esp_sleep.h"
#include "driver/gpio.h"
#include "driver/rtc_io.h"
#include "protocol/agent.hpp"
#include "transport/transport.hpp"
#include "protocol/protocol.hpp"
#include "esp_mac.h"
#include "esp_timer.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "cJSON.h"
#include "sdkconfig.h"
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
namespace {
aim::Board board;
aim::Protocol protocol(BASIC_VERSION);
aim::Framer framers[2];
aim::Link agentLink=aim::Link::Usb;
aim::Agent agent([](const uint8_t* p,size_t n){return agentLink==aim::Link::Usb?aim::usb_report(7,p,n):aim::ble_report(7,p,n);});
struct Rx {aim::Link link;uint8_t data[63]; uint8_t size;};
struct Tx {aim::Link link;uint8_t report=6;char json[aim::json_limit+1];};
QueueHandle_t rx_queue=nullptr,tx_queue=nullptr;
std::atomic<unsigned> rx_dropped{0},tx_failed{0};
char base_mac[18];
esp_err_t board_error=ESP_ERR_INVALID_STATE;
bool receive(aim::Link link,const uint8_t* b,size_t n) {
    if(n!=63 && n!=19)return false;
    Rx msg{};msg.link=link;msg.size=uint8_t(n);std::memcpy(msg.data,b,n);
    if(xQueueSend(rx_queue,&msg,0)!=pdTRUE) {++rx_dropped;return false;}
    return true;
}
void enqueue(aim::Link link,const std::string& json) {
    if(json.empty()||json.size()>aim::json_limit)return;
    Tx tx{};tx.link=link;std::memcpy(tx.json,json.c_str(),json.size()+1);
    if(xQueueSend(tx_queue,&tx,0)!=pdTRUE)++tx_failed;
}
void transmit(void*) {
    static Tx msg;
    while(true) {
        if(xQueueReceive(tx_queue,&msg,portMAX_DELAY)!=pdTRUE)continue;
        auto send=[&](const uint8_t* b,size_t n) {
            return msg.link==aim::Link::Usb?aim::usb_report(msg.report,b,n):aim::ble_report(msg.report,b,n);
        };
        bool ok=msg.report==1?send(reinterpret_cast<const uint8_t*>(msg.json),8):aim::send_fragments(msg.json,send);
        if(!ok)++tx_failed;
    }
}
int64_t lastActivity=0, touchDown=-1, selectUntil=0, powerDown=-1, lastPowerClick=-1000;
unsigned selectedChannel=1;
bool suppressKnob=false,suppressPower=false,standbyLights=false;
esp_err_t bleError=ESP_ERR_INVALID_STATE;
RTC_DATA_ATTR unsigned wakeCount=0;

void sleep_board(bool manual) {
    if(gpio_get_level(gpio_num_t(aim::power_pin))==0 || gpio_get_level(gpio_num_t(aim::encoder_key_pin))==0)return;
    const uint64_t pins=(1ULL<<aim::power_pin)|(manual?0ULL:(1ULL<<aim::encoder_key_pin));
    if(esp_sleep_enable_ext1_wakeup_io(pins,ESP_EXT1_WAKEUP_ANY_LOW)!=ESP_OK || !resume_custom_on_wake())return;
    board.render(aim::Lights{},0);board.indicators(0);board.show();
    for(int p:{aim::power_pin,aim::encoder_key_pin})rtc_gpio_pullup_en(gpio_num_t(p));
    esp_deep_sleep_start();
}
std::string status() {
    cJSON* j=cJSON_CreateObject();const auto& s=board.snapshot();
    cJSON_AddStringToObject(j,"version",BASIC_VERSION);cJSON_AddStringToObject(j,"firmware",BASIC_VERSION);
    cJSON_AddStringToObject(j,"firmwareVersion",BASIC_VERSION);cJSON_AddStringToObject(j,"firmwareFamily","keyberth");
    cJSON_AddStringToObject(j,"hardwareRevision","AI Micro");cJSON_AddStringToObject(j,"hardware_revision","AI Micro");
    cJSON_AddStringToObject(j,"partitionScheme","ai-micro-basic-v1");cJSON_AddStringToObject(j,"updateProtocol","rom-only");
    cJSON_AddStringToObject(j,"base_mac",base_mac);cJSON_AddBoolToObject(j,"base_mac_valid",true);
    cJSON_AddNumberToObject(j,"profile_index",0);cJSON_AddNumberToObject(j,"layer_index",0);
    cJSON_AddStringToObject(j,"active_transport",aim::usb_active()?"usb":"ble");
    cJSON_AddBoolToObject(j,"ble_ready",aim::ble_ready());
    cJSON_AddBoolToObject(j,"ble_connected",aim::ble_connected());
    cJSON_AddBoolToObject(j,"ble_advertising",bleError==ESP_OK&&aim::ble_advertising());
    cJSON_AddStringToObject(j,"ble_init",esp_err_to_name(bleError));
    cJSON_AddNumberToObject(j,"ble_selected_channel",kb::prefs.channel);
    cJSON_AddBoolToObject(j,"ble_slot_bound",aim::ble_bonds()>0);
    cJSON_AddNumberToObject(j,"wake_count",wakeCount);
    cJSON_AddBoolToObject(j,"standby_lighting",standbyLights);
    cJSON_AddBoolToObject(j,"buzzer_enabled",kb::prefs.buzzer);
    cJSON_AddBoolToObject(j,"preferences_initialized",kb::initialized);
    if(s.battery_valid) {cJSON_AddNumberToObject(j,"battery",s.battery_percent);cJSON_AddBoolToObject(j,"is_charging",s.charging);}
    cJSON_AddBoolToObject(j,"battery_valid",s.battery_valid);cJSON_AddNumberToObject(j,"battery_mv",s.battery_mv);
    cJSON_AddBoolToObject(j,"charging",s.charging);cJSON_AddBoolToObject(j,"standby",s.standby);
    cJSON_AddNumberToObject(j,"key_register",s.key_register);cJSON_AddNumberToObject(j,"pressed_mask",s.pressed_mask);
    cJSON_AddNumberToObject(j,"joystick_x",s.joy_x);cJSON_AddNumberToObject(j,"joystick_y",s.joy_y);
    cJSON_AddNumberToObject(j,"touch_raw",s.touch_raw);cJSON_AddNumberToObject(j,"touch_baseline",s.touch_baseline);
    cJSON_AddBoolToObject(j,"touch_active",s.touched);
    cJSON_AddNumberToObject(j,"rx_dropped",rx_dropped);cJSON_AddNumberToObject(j,"tx_failed",tx_failed);
    cJSON_AddNumberToObject(j,"protocol_errors",framers[0].errors+framers[1].errors);
    cJSON_AddStringToObject(j,"board_init",esp_err_to_name(board_error));
    char* encoded=cJSON_PrintUnformatted(j);std::string result=encoded?encoded:"{}";cJSON_free(encoded);cJSON_Delete(j);return result;
}
void input(aim::InputEvent e) {
    int64_t now=esp_timer_get_time()/1000;
    lastActivity=now;
    if(e.kind==aim::InputKind::Power) {
        if(suppressPower){if(!e.pressed)suppressPower=false;return;}
        if(e.pressed)powerDown=now;
        else if(powerDown>=0) {
            if(now-powerDown>=2000)sleep_board(true);
            else if(now-lastPowerClick<=450) {
                auto next=kb::prefs;next.buzzer=!next.buzzer;
                if(kb::save(next))board.tone(2700,90,next.buzzer?next.volume:0);
                lastPowerClick=-1000;
            } else lastPowerClick=now;
            powerDown=-1;
        }
        return;
    }
    if(e.kind==aim::InputKind::EncoderPress && suppressKnob){if(!e.pressed)suppressKnob=false;return;}
    if(e.kind==aim::InputKind::Touch) {
        if(e.pressed)touchDown=now;
        else if(touchDown>=0) {
            if(now-touchDown>=2800) {
                if(selectUntil && bleError==ESP_OK) {
                    if(selectedChannel==kb::prefs.channel)aim::ble_forget();
                    else if(aim::forget_inactive_channel(selectedChannel)!=ESP_OK) {selectUntil=0;touchDown=-1;return;}
                }
                selectUntil=now+5000;
            } else if(selectUntil) {selectedChannel=selectedChannel%3+1;selectUntil=now+5000;}
            touchDown=-1;
        }
        return;
    }
    if(e.pressed&&kb::prefs.buzzer)board.tone(2700,35,kb::prefs.volume);
    if(agent.active()) {
        static aim::Direction previous=aim::Direction::Center;
        if(e.kind==aim::InputKind::Key) {
            char key[4]={'K',char('0'+(e.index+1)/10),char('0'+(e.index+1)%10),0};
            agent.input(key,e.pressed);
        } else if(e.kind==aim::InputKind::EncoderPress) agent.input("ENC_PRESS",e.pressed);
        else if(e.kind==aim::InputKind::Encoder) {
            const char* id=e.index>0?"ENC_CCW":"ENC_CW";
            agent.input(id,true); agent.input(id,false);
        } else if(e.kind==aim::InputKind::Joystick) {
            const char* names[]={"","JOY_RIGHT","JOY_UP","JOY_LEFT","JOY_DOWN"};
            if(previous!=aim::Direction::Center) agent.input(names[int(previous)],false);
            previous=aim::Direction(e.index);
            if(previous!=aim::Direction::Center) agent.input(names[e.index],true);
        }
        return;
    }
    const auto link=aim::usb_active()?aim::Link::Usb:aim::Link::Ble;
    if(e.kind==aim::InputKind::Key)enqueue(link,aim::Protocol::key(aim::key_ids[e.index],e.pressed,e.index<6?e.index:-1));
    else if(e.kind==aim::InputKind::EncoderPress)enqueue(link,aim::Protocol::key("ENC",e.pressed));
    else if(e.kind==aim::InputKind::Encoder)enqueue(link,aim::Protocol::key(e.index>0?"ENC_CC":"ENC_CW",true));
    else if(e.kind==aim::InputKind::Joystick)enqueue(link,aim::Protocol::radial(aim::angle(aim::Direction(e.index)),e.pressed?1:0));
}
}
extern "C" void app_main() {
    uint8_t mac[6]{};ESP_ERROR_CHECK(esp_read_mac(mac,ESP_MAC_WIFI_STA));
    std::snprintf(base_mac,sizeof(base_mac),"%02X:%02X:%02X:%02X:%02X:%02X",mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
    rx_queue=xQueueCreate(64,sizeof(Rx));tx_queue=xQueueCreate(8,sizeof(Tx));
    ESP_ERROR_CHECK(rx_queue&&tx_queue?ESP_OK:ESP_ERR_NO_MEM);
    // 优先提供 USB 恢复入口；驱动初始化失败也继续处理 CDC。
    ESP_ERROR_CHECK(aim::usb_begin(receive));
    if(!arm_trial_return()) {
        ESP_LOGE("keyberth","Trial not armed; USB ROM recovery only");
        for(;;) {
            if(aim::usb_download_requested()) aim::enter_download_mode();
            vTaskDelay(pdMS_TO_TICKS(10));
        }
    }
    ESP_ERROR_CHECK(kb::init_settings());
    selectedChannel=kb::prefs.channel;
    const bool woke=esp_sleep_get_wakeup_cause()==ESP_SLEEP_WAKEUP_EXT1;
    if(woke) {
        ++wakeCount;
        for(int p:{aim::encoder_key_pin,aim::power_pin})rtc_gpio_deinit(gpio_num_t(p));
    }
    board_error=board.begin();
    if(woke && board_error==ESP_OK) {
        const auto mask=esp_sleep_get_ext1_wakeup_status();
        suppressKnob=(mask&(1ULL<<aim::encoder_key_pin)) && !gpio_get_level(gpio_num_t(aim::encoder_key_pin));
        suppressPower=(mask&(1ULL<<aim::power_pin)) && !gpio_get_level(gpio_num_t(aim::power_pin));
    }
    bleError=aim::ble_begin(receive);
    ESP_LOGI("keyberth","board=%s",esp_err_to_name(board_error));
    protocol.status=status;
    ESP_ERROR_CHECK(xTaskCreate(transmit,"basic_tx",6144,nullptr,3,nullptr)==pdPASS?ESP_OK:ESP_ERR_NO_MEM);
    int64_t last_frame=0,last_status=0;
    while(true) {
        const int64_t now=esp_timer_get_time()/1000;
        if(aim::usb_download_requested())aim::enter_download_mode();
        agent.tick(agentLink==aim::Link::Usb?aim::usb_active():(!aim::usb_active()&&aim::ble_connected()),now);
        if(board_error==ESP_OK) {
            board.poll(now,input);
            // The wake press can end during initialization, before the first debounced event.
            if(suppressPower && gpio_get_level(gpio_num_t(aim::power_pin)))suppressPower=false;
            if(suppressKnob && gpio_get_level(gpio_num_t(aim::encoder_key_pin)))suppressKnob=false;
        }
        const auto& snapshot=board.snapshot();
        const bool wired=aim::usb_active(),powered=wired||snapshot.charging||snapshot.standby;
        if(bleError==ESP_OK)aim::ble_enable(!wired);
        if(selectUntil && now>=selectUntil && touchDown<0) {
            selectUntil=0;
            if(selectedChannel!=kb::prefs.channel) {
                auto next=kb::prefs;next.channel=selectedChannel;
                if(kb::save(next)&&resume_custom_on_wake())esp_restart();
            }
        }
        static int64_t lastPowered=0;
        if(powered)lastPowered=now;
        if(!powered && kb::prefs.sleep && now-std::max(lastPowered,lastActivity)>=kb::prefs.sleep*60000LL)sleep_board(false);
        standbyLights=(powered?kb::prefs.onPower:kb::prefs.onBluetooth) && now-lastActivity>=kb::prefs.standby*60000LL;
        Rx rx{};
        for(unsigned batch=0;batch<16 && xQueueReceive(rx_queue,&rx,0)==pdTRUE;batch++) {
            if(rx.size==19) {
                if((rx.link==aim::Link::Usb)!=wired)continue;
                agentLink=rx.link;agent.receive(rx.data,rx.size,now);
            }
            else framers[int(rx.link)].feed(rx.data,rx.size,now,[&](const std::string& s){enqueue(rx.link,protocol.request(s));});
        }
        static char line[768];
        if(aim::usb_read_line(line,sizeof(line))) {
            if(!std::strcmp(line,"STATUS"))aim::usb_line(("CMSTATE\t"+status()).c_str());
            else if(!std::strcmp(line,"UPDATE_INFO"))aim::usb_line(("CMUPDATE_INFO\t"+status()).c_str());
            else if(!std::strncmp(line,"PREFS_GET\t",10)||!std::strncmp(line,"PREFS_SET\t",10)) {
                const bool write=line[6]=='S';
                aim::usb_line(("CMPREFS\t"+kb::preference_request(line+10,write)).c_str());
            }
            else if(!std::strcmp(line,"BUZZER_PREVIEW")) {
                bool ok=board.tone(2700,350,kb::prefs.buzzer?kb::prefs.volume:0);
                aim::usb_line(ok?"OK BUZZER_PREVIEW":"ERR BUZZER_PREVIEW");
            }
            else if(!std::strcmp(line,"KEYBERTH FACTORY_RESET CONFIRM")) {
                if(resume_custom_on_wake() && kb::request_factory_reset())esp_restart();
                arm_trial_return();
            }
            else if(!std::strcmp(line,"KEYBERTH ROLLBACK")) esp_restart();
            else if(!std::strcmp(line,"BOOTLOADER CONFIRM"))aim::enter_download_mode();
            else aim::usb_line("ERR commands: STATUS UPDATE_INFO BOOTLOADER CONFIRM");
        }
        if(board_error==ESP_OK&&now-last_frame>=16) {
            last_frame=now;
            auto lights=standbyLights?aim::Lights{}:(agent.controls()?agent.lights:protocol.lights);
            if(standbyLights)lights.ambient={0x22aa66,0.15f,0.22f,4};
            if(!lights.individual)lights.functions.fill(lights.commands);
            for(unsigned i=0;i<14;++i) {
                const auto* style=kb::prefs.styles[i];
                auto& light=i==0?lights.ambient:(i<=6?lights.agents[i-1]:lights.functions[i-7]);
                if(*style) {
                    unsigned long long bits=std::strtoull(style,nullptr,16);
                    light={uint32_t(bits>>20),float((bits>>8)&255)/100,float(bits&255)/100,uint8_t((bits>>16)&15)};
                    if(i>=7)lights.individual=true;
                }
                light.brightness*=kb::prefs.brightness/100.0f;
            }
            lights.commands.brightness*=kb::prefs.brightness/100.0f;
            board.render(lights,now);
            unsigned indicator=1U<<(selectedChannel-1);
            board.indicators(selectUntil?((now/250)%2?indicator:0):(wired?7:((aim::ble_connected()||(now/550)%2)?indicator:0)));
            if(board.show()!=ESP_OK)ESP_LOGW("basic","LED write failed");
        }
        if(now-last_status>=1000) {
            last_status=now;
            aim::usb_line(("CMSTATE\t"+status()).c_str());
        }
        vTaskDelay(pdMS_TO_TICKS(1));
    }
}
