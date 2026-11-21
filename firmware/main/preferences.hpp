#pragma once
#include <cstdint>
#include <string>
#include "esp_err.h"

namespace kb {
struct LegacySettings {
    uint32_t revision=1;
    uint8_t sleep=15, volume=50, standby=5;
    uint8_t onPower=1, onBluetooth=0, buzzer=1, channel=1;
};
struct Settings : LegacySettings {
    uint8_t brightness=100;
    char styles[14][12]{};
};
bool request_factory_reset();
extern Settings prefs;
extern bool initialized;
esp_err_t init_settings();
bool save(Settings next);
const char* bond_namespace();
std::string preference_request(const char* payload,bool write);
}
