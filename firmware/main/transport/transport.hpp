// SPDX-License-Identifier: MIT
#pragma once
#include "esp_err.h"
#include <cstddef>
#include <cstdint>
namespace aim {
enum class Link:uint8_t { Usb,Ble };
using Receive=bool(*)(Link,const uint8_t*,size_t);
esp_err_t usb_begin(Receive);
bool usb_active();
bool usb_report(uint8_t id,const uint8_t*,size_t);
void usb_line(const char*);
bool usb_read_line(char* output,size_t capacity);
bool usb_download_requested();
[[noreturn]] void enter_download_mode();
esp_err_t ble_begin(Receive);
void ble_enable(bool);
void ble_forget();
esp_err_t forget_inactive_channel(unsigned channel);
bool ble_connected();
bool ble_ready();
bool ble_report(uint8_t id,const uint8_t*,size_t);
void ble_battery(uint8_t);
unsigned ble_bonds();
int ble_security_status();
int ble_disconnect_reason();
bool ble_advertising();
int ble_advertise_status();
esp_err_t bonds_begin();
}
