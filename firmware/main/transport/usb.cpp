// SPDX-License-Identifier: MIT
#include "transport.hpp"
#include "hid.hpp"
#include "tinyusb.h"
#include "tinyusb_default_config.h"
#include "tinyusb_cdc_acm.h"
#include "tusb.h"
#include "esp_mac.h"
#include "esp_system.h"
#include "soc/rtc_cntl_reg.h"
#include "soc/usb_serial_jtag_reg.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <atomic>
#include <cstdio>
#include <cstring>
namespace {
aim::Receive receiver=nullptr;
std::atomic<bool> download{false};
char serial_number[32];
const char* strings[]={reinterpret_cast<const char*>(u"\u0409"),"CodexMicro","Project2077",serial_number,"AI Micro Basic CDC","AI Micro Basic HID"};
const tusb_desc_device_t device={
    .bLength=sizeof(tusb_desc_device_t),.bDescriptorType=TUSB_DESC_DEVICE,.bcdUSB=0x0200,
    .bDeviceClass=TUSB_CLASS_MISC,.bDeviceSubClass=MISC_SUBCLASS_COMMON,.bDeviceProtocol=MISC_PROTOCOL_IAD,
    .bMaxPacketSize0=64,.idVendor=0x303A,.idProduct=0x8360,.bcdDevice=0x0101,
    .iManufacturer=1,.iProduct=2,.iSerialNumber=3,.bNumConfigurations=1};
const uint8_t agent_descriptor[]={
    0x06,0x31,0xff,0x09,0x01,0xa1,0x01,0x85,7,0x15,0,0x26,0xff,0,
    0x75,8,0x95,19,0x09,1,0x81,2,0x09,2,0x91,2,0xc0
};
const uint8_t config[]={
    TUD_CONFIG_DESCRIPTOR(1,4,0,TUD_CONFIG_DESC_LEN+TUD_CDC_DESC_LEN+2*TUD_HID_INOUT_DESC_LEN,0,100),
    TUD_CDC_DESCRIPTOR(0,4,0x81,8,0x02,0x82,64),
    TUD_HID_INOUT_DESCRIPTOR(2,5,HID_ITF_PROTOCOL_NONE,sizeof(aim::hid_map),0x03,0x83,64,1),
    TUD_HID_INOUT_DESCRIPTOR(3,5,HID_ITF_PROTOCOL_NONE,sizeof(agent_descriptor),0x04,0x84,64,1)};
void coding(int,cdcacm_event_t* e) {
    if(e&&e->type==CDC_EVENT_LINE_CODING_CHANGED&&e->line_coding_changed_data.p_line_coding&&
       e->line_coding_changed_data.p_line_coding->bit_rate==1200)download=true;
}
void IRAM_ATTR rom_boot() {REG_WRITE(RTC_CNTL_OPTION1_REG,RTC_CNTL_FORCE_DOWNLOAD_BOOT);}
}
extern "C" const uint8_t* tud_hid_descriptor_report_cb(uint8_t instance) {return instance==1?agent_descriptor:aim::hid_map;}
extern "C" uint16_t tud_hid_get_report_cb(uint8_t,uint8_t,hid_report_type_t,uint8_t*,uint16_t) {return 0;}
extern "C" void tud_hid_set_report_cb(uint8_t instance,uint8_t id,hid_report_type_t type,const uint8_t* b,uint16_t n) {
    if(type!=HID_REPORT_TYPE_OUTPUT) return;
    if(instance==1) {
        if(n==20 && b[0]==7) {id=7;++b;--n;}
        if(id==7 && n==19 && receiver) receiver(aim::Link::Usb,b,n);
        return;
    }
    if(n==64&&b[0]==6) {id=6;++b;--n;}
    if(id==6&&n==63&&receiver)receiver(aim::Link::Usb,b,n);
}
namespace aim {
esp_err_t usb_begin(Receive receive) {
    receiver=receive;uint8_t mac[6]{};
    ESP_ERROR_CHECK(esp_read_mac(mac,ESP_MAC_WIFI_STA));
    std::snprintf(serial_number,sizeof(serial_number),"AIMB-%02X%02X%02X%02X%02X%02X",mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
    tinyusb_config_t cfg=TINYUSB_DEFAULT_CONFIG();cfg.descriptor.device=&device;
    cfg.descriptor.full_speed_config=config;cfg.descriptor.string=strings;cfg.descriptor.string_count=6;
    esp_err_t err=tinyusb_driver_install(&cfg);if(err!=ESP_OK)return err;
    tinyusb_config_cdcacm_t cdc{};cdc.cdc_port=TINYUSB_CDC_ACM_0;cdc.callback_line_coding_changed=coding;
    return tinyusb_cdcacm_init(&cdc);
}
bool usb_active() {return tud_mounted()&&!tud_suspended();}
bool usb_report(uint8_t id,const uint8_t* data,size_t size) {
    if((id==6&&size!=63)||(id==1&&size!=8)||(id==7&&size!=19)||(id!=1&&id!=6&&id!=7))return false;
    for(int i=0;i<100&&usb_active();++i) {
        uint8_t instance=id==7?1:0;
        if(tud_hid_n_ready(instance))return tud_hid_n_report(instance,id,data,uint16_t(size));
        vTaskDelay(pdMS_TO_TICKS(1));
    }
    return false;
}
void usb_line(const char* text) {
    if(!tud_cdc_connected())return;
    size_t length=std::strlen(text),offset=0;
    for(unsigned attempt=0;offset<length&&attempt<20;++attempt) {
        offset+=tinyusb_cdcacm_write_queue(TINYUSB_CDC_ACM_0,reinterpret_cast<const uint8_t*>(text)+offset,length-offset);
        tinyusb_cdcacm_write_flush(TINYUSB_CDC_ACM_0,5);
    }
    if(offset==length) {
        static const uint8_t nl='\n';tinyusb_cdcacm_write_queue(TINYUSB_CDC_ACM_0,&nl,1);
        tinyusb_cdcacm_write_flush(TINYUSB_CDC_ACM_0,5);
    }
}
bool usb_read_line(char* out,size_t capacity) {
    static char pending[768];static size_t used=0;static bool overflow=false;
    uint8_t c=0;size_t n=0;
    while(tinyusb_cdcacm_read(TINYUSB_CDC_ACM_0,&c,1,&n)==ESP_OK&&n) {
        if(c=='\n') {
            if(overflow||used>=capacity) {used=0;overflow=false;usb_line("ERR line too long");continue;}
            pending[used]=0;std::memcpy(out,pending,used+1);used=0;return true;
        }
        if(c=='\r')continue;
        if(used+1>=sizeof(pending))overflow=true;
        if(!overflow)pending[used++]=char(c);
    }
    return false;
}
bool usb_download_requested() {return download.load();}
[[noreturn]] void enter_download_mode() {
    tinyusb_cdcacm_deinit(TINYUSB_CDC_ACM_0);ESP_ERROR_CHECK(tinyusb_driver_uninstall());
    // 归还 GPIO19/20 的 PHY 后进入 ESP32-S3 ROM USB Serial/JTAG。
    CLEAR_PERI_REG_MASK(RTC_CNTL_USB_CONF_REG,RTC_CNTL_SW_HW_USB_PHY_SEL|RTC_CNTL_SW_USB_PHY_SEL|RTC_CNTL_USB_PAD_ENABLE);
    CLEAR_PERI_REG_MASK(USB_SERIAL_JTAG_CONF0_REG,USB_SERIAL_JTAG_PHY_SEL|USB_SERIAL_JTAG_USB_PAD_ENABLE);
    vTaskDelay(pdMS_TO_TICKS(50));
    SET_PERI_REG_MASK(USB_SERIAL_JTAG_CONF0_REG,USB_SERIAL_JTAG_USB_PAD_ENABLE);
    vTaskDelay(pdMS_TO_TICKS(100));
    ESP_ERROR_CHECK(esp_register_shutdown_handler(rom_boot));esp_restart();
    while(true)vTaskDelay(portMAX_DELAY);
}
}
