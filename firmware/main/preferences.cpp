#include "preferences.hpp"
#include "esp_partition.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "cJSON.h"
#include <cmath>
#include <memory>
#include <array>
#include <algorithm>
#include <cstring>
namespace kb {
Settings prefs;
bool initialized=false;
static nvs_handle_t handle;
static unsigned bootChannel=1;
const char* bond_namespace() {
    static const char* names[]={"ble1","ble2_v2","ble3_v2"};
    return names[bootChannel-1];
}
esp_err_t init_settings() {
    // Reserved in the manufacturer's Basic layout, outside all stock partitions.
    esp_err_t err=esp_partition_register_external(nullptr,0xc30000,0xf000,"kb_nvs",
        ESP_PARTITION_TYPE_DATA,ESP_PARTITION_SUBTYPE_DATA_NVS,nullptr);
    if(err!=ESP_OK)return err;
    const esp_partition_t* marker=nullptr;
    if((err=esp_partition_register_external(nullptr,0xc3f000,0x1000,"kb_marker",ESP_PARTITION_TYPE_DATA,
            ESP_PARTITION_SUBTYPE_DATA_UNDEFINED,&marker))!=ESP_OK)return err;
    constexpr char magic[]="keyberth-settings-v1";
    char storedMagic[sizeof(magic)];
    if((err=esp_partition_read(marker,0,storedMagic,sizeof(storedMagic)))!=ESP_OK)return err;
    if(std::memcmp(storedMagic,magic,sizeof(magic))) {
        const auto* data=esp_partition_find_first(ESP_PARTITION_TYPE_DATA,ESP_PARTITION_SUBTYPE_DATA_NVS,"kb_nvs");
        std::array<uint8_t,256> block;
        for(const auto* part:{data,marker}) {
            if(!part)return ESP_ERR_NOT_FOUND;
            for(unsigned offset=0;offset<part->size;offset+=block.size()) {
                if((err=esp_partition_read(part,offset,block.data(),block.size()))!=ESP_OK)return err;
                if(!std::all_of(block.begin(),block.end(),[](auto byte){return byte==0xff;}))return ESP_ERR_INVALID_STATE;
            }
        }
        if((err=esp_partition_write(marker,0,magic,sizeof(magic)))!=ESP_OK)return err;
    }
    if((err=nvs_flash_init_partition("kb_nvs"))!=ESP_OK)return err;
    if((err=nvs_open_from_partition("kb_nvs","settings",NVS_READWRITE,&handle))!=ESP_OK)return err;
    nvs_handle_t maintenance;
    if((err=nvs_open_from_partition("kb_nvs","maintenance",NVS_READWRITE,&maintenance))!=ESP_OK)return err;
    uint8_t reset=0;
    err=nvs_get_u8(maintenance,"reset",&reset);
    if(err!=ESP_OK && err!=ESP_ERR_NVS_NOT_FOUND){nvs_close(maintenance);return err;}
    if(reset) {
        for(const char* name:{"settings","ble1","ble2","ble3","ble2_v2","ble3_v2"}) {
            nvs_handle_t h;
            if((err=nvs_open_from_partition("kb_nvs",name,NVS_READWRITE,&h))!=ESP_OK)break;
            err=nvs_erase_all(h);
            if(err==ESP_OK)err=nvs_commit(h);
            nvs_close(h);
            if(err!=ESP_OK)break;
        }
        if(err==ESP_OK && (err=nvs_erase_key(maintenance,"reset"))==ESP_OK)err=nvs_commit(maintenance);
        if(err!=ESP_OK){nvs_close(maintenance);return err;}
    }
    nvs_close(maintenance);
    size_t n=sizeof(Settings);Settings stored;
    err=nvs_get_blob(handle,"v2",&stored,&n);
    if(err==ESP_ERR_NVS_NOT_FOUND) {
        LegacySettings legacy;
        size_t oldSize=sizeof(legacy);
        err=nvs_get_blob(handle,"v1",&legacy,&oldSize);
        if(err==ESP_OK && oldSize!=sizeof(legacy))return ESP_ERR_INVALID_SIZE;
        if(err==ESP_OK)static_cast<LegacySettings&>(stored)=legacy;
        n=sizeof(stored);
    }
    if(err==ESP_ERR_NVS_NOT_FOUND)return ESP_OK;
    if(err!=ESP_OK)return err;
    if(n!=sizeof(stored)||stored.channel<1||stored.channel>3||stored.sleep>120||stored.volume>100||
       stored.standby<1||stored.standby>120||stored.onPower>1||stored.onBluetooth>1||stored.buzzer>1)return ESP_ERR_INVALID_STATE;
    prefs=stored;initialized=true;bootChannel=stored.channel;return ESP_OK;
}
bool request_factory_reset() {
    nvs_handle_t h;
    if(nvs_open_from_partition("kb_nvs","maintenance",NVS_READWRITE,&h)!=ESP_OK)return false;
    bool ok=nvs_set_u8(h,"reset",1)==ESP_OK && nvs_commit(h)==ESP_OK;
    nvs_close(h);return ok;
}
bool save(Settings next) {
    next.revision=prefs.revision+1;
    if(nvs_set_blob(handle,"v2",&next,sizeof(next))!=ESP_OK||nvs_commit(handle)!=ESP_OK)return false;
    prefs=next;initialized=true;return true;
}
std::string preference_request(const char* payload,bool write) {
    using Json=std::unique_ptr<cJSON,decltype(&cJSON_Delete)>;
    Json in(cJSON_Parse(payload),cJSON_Delete), out(cJSON_CreateObject(),cJSON_Delete);
    auto field=[&](const char* k){return cJSON_GetObjectItemCaseSensitive(in.get(),k);};
    auto integer=[&](const char* k,double low,double high){auto n=field(k);return cJSON_IsNumber(n)&&
        n->valuedouble>=low&&n->valuedouble<=high&&std::floor(n->valuedouble)==n->valuedouble;};
    cJSON_AddNumberToObject(out.get(),"id",integer("id",0,UINT32_MAX)?field("id")->valuedouble:0);
    const char* error=nullptr;
    if(!integer("id",0,UINT32_MAX))error="invalid_id";
    else if(write) {
        if(!integer("revision",prefs.revision,prefs.revision))error="stale_revision";
        else if(!integer("version",1,1)||!integer("sleepMinutes",0,120)||!integer("volumePercent",0,100)||
             !integer("standbyMinutes",1,120)||!cJSON_IsBool(field("standbyPowered"))||!cJSON_IsBool(field("standbyBluetooth")))error="invalid_preferences";
        else {
            Settings next=prefs;
            next.sleep=field("sleepMinutes")->valueint;next.volume=field("volumePercent")->valueint;
            next.standby=field("standbyMinutes")->valueint;next.onPower=cJSON_IsTrue(field("standbyPowered"));
            next.onBluetooth=cJSON_IsTrue(field("standbyBluetooth"));
            if(!initialized && field("initialBuzzerEnabled") && cJSON_IsBool(field("initialBuzzerEnabled")))
                next.buzzer=cJSON_IsTrue(field("initialBuzzerEnabled"));
            if(field("brightness")) {
                if(!integer("brightness",0,100))error="invalid_brightness";
                else next.brightness=field("brightness")->valueint;
            }
            if(auto styles=field("styles")) {
                if(!cJSON_IsArray(styles)||cJSON_GetArraySize(styles)!=14)error="invalid_styles";
                for(int i=0;!error && i<14;++i) {
                    auto item=cJSON_GetArrayItem(styles,i);
                    if(!cJSON_IsString(item)){error="invalid_style";break;}
                    const char* s=item->valuestring;
                    if(*s && (std::strlen(s)!=11 || std::strspn(s,"0123456789abcdefABCDEF")!=11 ||
                       s[6]<'0'||s[6]>'6'||std::strtoul(std::string(s+7,2).c_str(),nullptr,16)>100 ||
                       std::strtoul(s+9,nullptr,16)>100)){error="invalid_style";break;}
                    std::strcpy(next.styles[i],s);
                }
            }
            if(!error && !save(next))error="storage_error";
        }
    }
    cJSON_AddBoolToObject(out.get(),"ok",!error);
    if(error)cJSON_AddStringToObject(out.get(),"error",error);
    cJSON_AddNumberToObject(out.get(),"version",1);cJSON_AddNumberToObject(out.get(),"revision",prefs.revision);
    cJSON_AddNumberToObject(out.get(),"sleepMinutes",prefs.sleep);cJSON_AddNumberToObject(out.get(),"volumePercent",prefs.volume);
    cJSON_AddNumberToObject(out.get(),"standbyMinutes",prefs.standby);cJSON_AddBoolToObject(out.get(),"standbyPowered",prefs.onPower);
    cJSON_AddBoolToObject(out.get(),"standbyBluetooth",prefs.onBluetooth);cJSON_AddBoolToObject(out.get(),"buzzerEnabled",prefs.buzzer);
    cJSON_AddNumberToObject(out.get(),"brightness",prefs.brightness);
    auto styles=cJSON_AddArrayToObject(out.get(),"styles");
    for(const auto& style:prefs.styles)cJSON_AddItemToArray(styles,cJSON_CreateString(style));
    cJSON_AddBoolToObject(out.get(),"storageReady",handle!=0);
    char* encoded=cJSON_PrintUnformatted(out.get());std::string result=encoded?encoded:"{}";cJSON_free(encoded);return result;
}
}
