#include "trial.hpp"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/sha256.h"
#include <algorithm>
#include <array>

namespace {
bool matches_stock(const esp_partition_t* factory) {
    constexpr size_t image_size=890416;
    constexpr std::array<unsigned char,32> stock={
        0x64,0xec,0xb6,0x13,0xe2,0x79,0xdf,0x28,0xbb,0x28,0xca,0x78,0x73,0x85,0x1e,0xbb,
        0x22,0x34,0xc7,0xf7,0xf5,0x47,0x53,0x19,0x67,0xc6,0xaa,0xb2,0x62,0xc7,0x78,0x15};
    if (!factory || factory->address!=0x20000 || factory->size<image_size) return false;
    mbedtls_sha256_context context;
    mbedtls_sha256_init(&context);
    bool ok=mbedtls_sha256_starts(&context,0)==0;
    std::array<unsigned char,1024> buffer;
    std::array<unsigned char,32> digest{};
    for (size_t offset=0;ok && offset<image_size;offset+=buffer.size()) {
        size_t n=std::min(buffer.size(),image_size-offset);
        ok=esp_partition_read(factory,offset,buffer.data(),n)==ESP_OK &&
            mbedtls_sha256_update(&context,buffer.data(),n)==0;
    }
    ok=ok && mbedtls_sha256_finish(&context,digest.data())==0;
    mbedtls_sha256_free(&context);
    return ok && digest==stock;
}
}
bool arm_trial_return() {
    auto running=esp_ota_get_running_partition();
    if (!running || (running->subtype!=ESP_PARTITION_SUBTYPE_APP_OTA_0 &&
                     running->subtype!=ESP_PARTITION_SUBTYPE_APP_OTA_1)) return false;
    auto factory=esp_partition_find_first(ESP_PARTITION_TYPE_APP,ESP_PARTITION_SUBTYPE_APP_FACTORY,nullptr);
    auto bootData=esp_partition_find_first(ESP_PARTITION_TYPE_DATA,ESP_PARTITION_SUBTYPE_DATA_OTA,nullptr);
    if (!bootData || bootData->address!=0xf000 || bootData->size!=0x2000) return false;
    if (!matches_stock(factory) || esp_ota_set_boot_partition(factory)!=ESP_OK) return false;
    auto next=esp_ota_get_boot_partition();
    if (!next || next->address!=factory->address) return false;
    return true; // Next reset returns to the verified factory partition.
}

bool resume_custom_on_wake() {
    const auto* run=esp_ota_get_running_partition();
    return run && run->subtype==ESP_PARTITION_SUBTYPE_APP_OTA_0 && esp_ota_set_boot_partition(run)==ESP_OK;
}
