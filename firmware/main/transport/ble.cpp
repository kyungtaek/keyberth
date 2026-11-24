// SPDX-License-Identifier: MIT
#include "transport.hpp"
#include "hid.hpp"
#include "../preferences.hpp"
#include "esp_mac.h"
#include "esp_log.h"
#include "host/ble_hs.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_store.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include <atomic>
#include <array>
#include <cstring>
namespace aim {
namespace {
Receive receiver=nullptr;
std::atomic<bool> enabled{false},connected{false},secure{false},subscribed{false},agent_subscribed{false},keyboard_subscribed{false};
std::atomic<unsigned> bond_count{0};
std::atomic<int> security_status{0},disconnect_reason{0};
std::atomic<int> advertise_status{0};
std::atomic<uint16_t> handle{BLE_HS_CONN_HANDLE_NONE};
std::atomic<uint8_t> battery{0};
bool synced=false;
ble_npl_event control_event{};
std::atomic<bool> forget_requested{false};
uint16_t keyboard_handle=0,vendor_handle=0,agent_handle=0;
const uint8_t agent_map[]={0x06,0x31,0xff,0x09,1,0xa1,1,0x85,7,0x15,0,0x26,0xff,0,0x75,8,0x95,19,0x09,1,0x81,2,0x09,2,0x91,2,0xc0};
uint8_t protocol_mode=1;
ble_uuid16_t hid_uuid=BLE_UUID16_INIT(0x1812),info_uuid=BLE_UUID16_INIT(0x2A4A),map_uuid=BLE_UUID16_INIT(0x2A4B);
ble_uuid16_t control_uuid=BLE_UUID16_INIT(0x2A4C),report_uuid=BLE_UUID16_INIT(0x2A4D),mode_uuid=BLE_UUID16_INIT(0x2A4E);
ble_uuid16_t ref_uuid=BLE_UUID16_INIT(0x2908),dis_uuid=BLE_UUID16_INIT(0x180A),pnp_uuid=BLE_UUID16_INIT(0x2A50);
ble_uuid16_t manufacturer_uuid=BLE_UUID16_INIT(0x2A29),version_uuid=BLE_UUID16_INIT(0x2A26);
ble_uuid16_t bas_uuid=BLE_UUID16_INIT(0x180F),level_uuid=BLE_UUID16_INIT(0x2A19);
enum Attribute {Info=1,Map,Mode,Control,Keyboard,VendorIn,VendorOut,AgentIn,AgentOut,KeyboardRef,VendorInRef,VendorOutRef,AgentInRef,AgentOutRef,Pnp,Manufacturer,Version,Battery};
int append(os_mbuf* om,const void* b,size_t n) {return os_mbuf_append(om,b,n)==0?0:BLE_ATT_ERR_INSUFFICIENT_RES;}
int access(uint16_t,uint16_t,ble_gatt_access_ctxt* ctx,void* argument) {
    auto field=static_cast<Attribute>(reinterpret_cast<uintptr_t>(argument));
    bool reading=ctx->op==BLE_GATT_ACCESS_OP_READ_CHR||ctx->op==BLE_GATT_ACCESS_OP_READ_DSC;
    if(reading) {
        static const uint8_t info[]={0x11,0x01,0,0x02},pnp[]={2,0x3A,0x30,0x60,0x83,1,1};
        static const uint8_t kref[]={1,1},viref[]={6,1},voref[]={6,2};
        static const uint8_t empty[63]{};
        switch(field) {
            case Info:return append(ctx->om,info,sizeof(info));
            case Map:{int rc=append(ctx->om,hid_map,sizeof(hid_map));return rc?rc:append(ctx->om,agent_map,sizeof(agent_map));}
            case Mode:return append(ctx->om,&protocol_mode,1);
            case AgentIn:case AgentOut:return append(ctx->om,empty,19);
            case AgentInRef:{static const uint8_t ref[]={7,1};return append(ctx->om,ref,2);}
            case AgentOutRef:{static const uint8_t ref[]={7,2};return append(ctx->om,ref,2);}
            case Keyboard:return append(ctx->om,empty,8);
            case VendorIn:case VendorOut:return append(ctx->om,empty,63);
            case KeyboardRef:return append(ctx->om,kref,2);
            case VendorInRef:return append(ctx->om,viref,2);
            case VendorOutRef:return append(ctx->om,voref,2);
            case Pnp:return append(ctx->om,pnp,sizeof(pnp));
            case Manufacturer:return append(ctx->om,"CodexMicro",10);
            case Version:return append(ctx->om,BASIC_VERSION,std::strlen(BASIC_VERSION));
            case Battery:{uint8_t b=battery;return append(ctx->om,&b,1);}
            default:return BLE_ATT_ERR_READ_NOT_PERMITTED;
        }
    }
    if(ctx->op!=BLE_GATT_ACCESS_OP_WRITE_CHR)return BLE_ATT_ERR_WRITE_NOT_PERMITTED;
    uint16_t count=0;uint8_t buf[63]{};
    if(ble_hs_mbuf_to_flat(ctx->om,buf,sizeof(buf),&count))return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    if(field==VendorOut||field==AgentOut) {
        if(!secure)return BLE_ATT_ERR_INSUFFICIENT_AUTHEN;
        if(count!=(field==AgentOut?19:63))return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        return receiver&&receiver(Link::Ble,buf,count)?0:BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    if((field==Mode||field==Control)&&count==1&&buf[0]<=1) {
        if(field==Mode&&buf[0]!=1)return BLE_ATT_ERR_VALUE_NOT_ALLOWED; // 只实现 Report 模式
        return 0;
    }
    return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
}
ble_gatt_dsc_def refs[5][2]{};
ble_gatt_chr_def hid_chars[10]{},dis_chars[4]{},bas_chars[2]{};
ble_gatt_svc_def services[4]{};
void characteristic(ble_gatt_chr_def& c,const ble_uuid16_t& uuid,Attribute a,ble_gatt_chr_flags flags,uint16_t* value=nullptr,ble_gatt_dsc_def* descriptors=nullptr) {
    c.uuid=&uuid.u;c.access_cb=access;c.arg=reinterpret_cast<void*>(uintptr_t(a));c.flags=flags;c.val_handle=value;c.descriptors=descriptors;
}
void setup_services() {
    const auto read=BLE_GATT_CHR_F_READ|BLE_GATT_CHR_F_READ_ENC;
    const auto write=BLE_GATT_CHR_F_WRITE|BLE_GATT_CHR_F_WRITE_NO_RSP|BLE_GATT_CHR_F_WRITE_ENC;
    for(unsigned i=0;i<5;++i) {
        refs[i][0].uuid=&ref_uuid.u;refs[i][0].access_cb=access;refs[i][0].att_flags=BLE_ATT_F_READ|BLE_ATT_F_READ_ENC;
        refs[i][0].arg=reinterpret_cast<void*>(uintptr_t(KeyboardRef+i));
    }
    characteristic(hid_chars[0],info_uuid,Info,read);
    characteristic(hid_chars[1],map_uuid,Map,read);
    characteristic(hid_chars[2],mode_uuid,Mode,read|write);
    characteristic(hid_chars[3],control_uuid,Control,BLE_GATT_CHR_F_WRITE_NO_RSP|BLE_GATT_CHR_F_WRITE_ENC);
    characteristic(hid_chars[4],report_uuid,Keyboard,read|BLE_GATT_CHR_F_NOTIFY,&keyboard_handle,refs[0]);
    characteristic(hid_chars[5],report_uuid,VendorIn,read|BLE_GATT_CHR_F_NOTIFY,&vendor_handle,refs[1]);
    characteristic(hid_chars[6],report_uuid,VendorOut,read|write,nullptr,refs[2]);
    characteristic(hid_chars[7],report_uuid,AgentIn,read|BLE_GATT_CHR_F_NOTIFY,&agent_handle,refs[3]);
    characteristic(hid_chars[8],report_uuid,AgentOut,read|write,nullptr,refs[4]);
    characteristic(dis_chars[0],pnp_uuid,Pnp,BLE_GATT_CHR_F_READ);
    characteristic(dis_chars[1],manufacturer_uuid,Manufacturer,BLE_GATT_CHR_F_READ);
    characteristic(dis_chars[2],version_uuid,Version,BLE_GATT_CHR_F_READ);
    characteristic(bas_chars[0],level_uuid,Battery,BLE_GATT_CHR_F_READ);
    services[0].type=BLE_GATT_SVC_TYPE_PRIMARY;services[0].uuid=&hid_uuid.u;services[0].characteristics=hid_chars;
    services[1].type=BLE_GATT_SVC_TYPE_PRIMARY;services[1].uuid=&dis_uuid.u;services[1].characteristics=dis_chars;
    services[2].type=BLE_GATT_SVC_TYPE_PRIMARY;services[2].uuid=&bas_uuid.u;services[2].characteristics=bas_chars;
}
void refresh_bonds() {ble_addr_t peers[1]{};int count=0;if(!ble_store_util_bonded_peers(peers,&count,1))bond_count=count;}
bool allowed_peer(const ble_gap_conn_desc& desc) {
    if(!bond_count)return true;
    ble_addr_t peers[1]{};int count=0;
    return !ble_store_util_bonded_peers(peers,&count,1)&&count==1&&
        (peers[0].type&1)==(desc.peer_id_addr.type&1)&&
        std::memcmp(peers[0].val,desc.peer_id_addr.val,6)==0;
}
int gap(ble_gap_event*,void*);
const char* channel_name() {
    switch(kb::prefs.channel) {
        case 2:return "AI Micro 2";
        case 3:return "AI Micro 3";
        default:return "AI Micro";
    }
}
void advertise() {
    if(!synced||!enabled||connected||ble_gap_adv_active())return;
    ble_hs_adv_fields fields{};fields.flags=BLE_HS_ADV_F_DISC_GEN|BLE_HS_ADV_F_BREDR_UNSUP;
    fields.appearance=0x03C1;fields.appearance_is_present=1;
    fields.uuids16=&hid_uuid;fields.num_uuids16=1;fields.uuids16_is_complete=1;
    const char* name=channel_name();fields.name=reinterpret_cast<const uint8_t*>(name);fields.name_len=std::strlen(name);fields.name_is_complete=1;
    if(ble_gap_adv_set_fields(&fields)) {ESP_LOGE("basic_ble","advertising fields failed");return;}
    ble_gap_adv_params params{};params.conn_mode=BLE_GAP_CONN_MODE_UND;params.disc_mode=BLE_GAP_DISC_MODE_GEN;
    int rc=ble_gap_adv_start(BLE_OWN_ADDR_RANDOM,nullptr,BLE_HS_FOREVER,&params,gap,nullptr);
    advertise_status=rc;
    if(rc)ESP_LOGE("basic_ble","advertise: %d",rc);
}
void control(ble_npl_event*) {
    if(!synced)return;
    if(forget_requested.exchange(false)) {
        if(connected)ble_gap_terminate(handle,BLE_ERR_REM_USER_CONN_TERM);
        int rc=ble_store_clear();refresh_bonds();
        ESP_LOGI("basic_ble","clear own bonds: %d",rc);
    }
    if(!enabled) {
        if(ble_gap_adv_active())ble_gap_adv_stop();
        if(connected)ble_gap_terminate(handle,BLE_ERR_REM_USER_CONN_TERM);
    } else advertise();
}
int gap(ble_gap_event* e,void*) {
    switch(e->type) {
        case BLE_GAP_EVENT_CONNECT: {
            ble_gap_conn_desc desc{};
            // IDF 5.5.4 在读取对端能力后通知 CONNECT；失败也可能仍持有连接对象。
            if(ble_gap_conn_find(e->connect.conn_handle,&desc)) {
                ble_npl_eventq_put(nimble_port_get_dflt_eventq(),&control_event);break;
            }
            if(e->connect.status) {ble_gap_terminate(e->connect.conn_handle,BLE_ERR_REM_USER_CONN_TERM);break;}
            handle=e->connect.conn_handle;connected=true;secure=desc.sec_state.encrypted&&allowed_peer(desc);subscribed=false;keyboard_subscribed=false;agent_subscribed=false;
            if(!enabled) {ble_gap_terminate(handle,BLE_ERR_REM_USER_CONN_TERM);break;}
            ble_gap_security_initiate(handle);
            ble_gattc_exchange_mtu(handle,nullptr,nullptr);
            break;
        }
        case BLE_GAP_EVENT_DISCONNECT:
            disconnect_reason=e->disconnect.reason;
            connected=false;secure=false;subscribed=false;keyboard_subscribed=false;agent_subscribed=false;handle=BLE_HS_CONN_HANDLE_NONE;advertise();break;
        case BLE_GAP_EVENT_ENC_CHANGE: {
            security_status=e->enc_change.status;
            ble_gap_conn_desc desc{};
            bool accepted=e->enc_change.status==0&&!ble_gap_conn_find(e->enc_change.conn_handle,&desc)&&desc.sec_state.encrypted;
            // 连接建立时主机可能仍使用临时地址；加密完成后核对解析的绑定身份。
            if(accepted)accepted=allowed_peer(desc);
            secure=accepted;
            if(!accepted&&e->enc_change.status==0)ble_gap_terminate(e->enc_change.conn_handle,BLE_ERR_REM_USER_CONN_TERM);
            refresh_bonds();break;
        }
        case BLE_GAP_EVENT_SUBSCRIBE:
            if(e->subscribe.attr_handle==vendor_handle)subscribed=e->subscribe.cur_notify;
            if(e->subscribe.attr_handle==agent_handle)agent_subscribed=e->subscribe.cur_notify;
            if(e->subscribe.attr_handle==keyboard_handle)keyboard_subscribed=e->subscribe.cur_notify;
            break;
        case BLE_GAP_EVENT_REPEAT_PAIRING:return BLE_GAP_REPEAT_PAIRING_IGNORE;
        case BLE_GAP_EVENT_ADV_COMPLETE:advertise();break;
        default:break;
    }
    return 0;
}
void sync() {
    uint8_t mac[6]{};ESP_ERROR_CHECK(esp_read_mac(mac,ESP_MAC_BT));
    uint8_t addr[6];for(int i=0;i<6;++i)addr[i]=mac[5-i];
    // Keep channel one's legacy identity. Each other channel must have a stable
    // identity of its own so hosts can retain independent encryption keys.
    addr[0]^=0x42;
    addr[4]^=static_cast<uint8_t>((kb::prefs.channel-1)<<6);
    addr[5]|=0xC0;
    if(ble_hs_id_set_rnd(addr)) {ESP_LOGE("basic_ble","identity failed");return;}
    synced=true;refresh_bonds();advertise();
}
void host(void*) {nimble_port_run();nimble_port_freertos_deinit();}
}
esp_err_t ble_begin(Receive receive) {
    receiver=receive;esp_err_t err=nimble_port_init();if(err!=ESP_OK)return err;
    ble_svc_gap_init();ble_svc_gatt_init();ble_svc_gap_device_name_set(channel_name());ble_svc_gap_device_appearance_set(0x03C1);
    ble_hs_cfg.sync_cb=sync;ble_hs_cfg.sm_io_cap=BLE_HS_IO_NO_INPUT_OUTPUT;
    ble_hs_cfg.sm_bonding=1;ble_hs_cfg.sm_sc=1;
    ble_hs_cfg.sm_our_key_dist=BLE_SM_PAIR_KEY_DIST_ENC|BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist=BLE_SM_PAIR_KEY_DIST_ENC|BLE_SM_PAIR_KEY_DIST_ID;
    err=bonds_begin();if(err!=ESP_OK)return err;
    setup_services();
    if(ble_gatts_count_cfg(services)||ble_gatts_add_svcs(services))return ESP_FAIL;
    ble_att_set_preferred_mtu(128);ble_npl_event_init(&control_event,control,nullptr);
    nimble_port_freertos_init(host);return ESP_OK;
}
void ble_enable(bool value) {if(enabled.exchange(value)!=value)ble_npl_eventq_put(nimble_port_get_dflt_eventq(),&control_event);}
void ble_forget() {forget_requested=true;ble_npl_eventq_put(nimble_port_get_dflt_eventq(),&control_event);}
bool ble_connected() {return connected;}
bool ble_ready() {return connected&&secure&&subscribed&&ble_att_mtu(handle)>=66;}
unsigned ble_bonds() {return bond_count;}
int ble_security_status() {return security_status;}
int ble_disconnect_reason() {return disconnect_reason;}
bool ble_advertising() {return ble_gap_adv_active();}
int ble_advertise_status() {return advertise_status;}
void ble_battery(uint8_t percent) {battery=percent;}
bool ble_report(uint8_t id,const uint8_t* b,size_t n) {
    if(!enabled||!connected||!secure)return false;
    if(id==6) {if(!ble_ready()||n!=63)return false;}
    else if(id==7) {if(!agent_subscribed||n!=19)return false;}
    else if(id==1) {if(!keyboard_subscribed||n!=8)return false;}
    else return false;
    os_mbuf* packet=ble_hs_mbuf_from_flat(b,n);if(!packet)return false;
    return ble_gatts_notify_custom(handle,id==6?vendor_handle:(id==7?agent_handle:keyboard_handle),packet)==0;
}
}
