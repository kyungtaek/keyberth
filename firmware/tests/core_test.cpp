// SPDX-License-Identifier: MIT
#include "protocol/protocol.hpp"
#include "board/input_logic.hpp"
#include "board/pins.hpp"
#include "cJSON.h"
#include <cassert>
#include <cstring>
#include <iostream>
#include <vector>
using Packet=std::array<uint8_t,63>;
std::vector<Packet> packets(const std::string& text) {
    std::vector<Packet> out;assert(aim::send_fragments(text,[&](const uint8_t* b,size_t n){assert(n==63);Packet p{};std::memcpy(p.data(),b,n);out.push_back(p);return true;}));return out;
}
void expect_error(aim::Protocol& p,const std::string& input,int code) {
    auto text=p.request(input);cJSON* j=cJSON_Parse(text.c_str());assert(j);
    auto error=cJSON_GetObjectItemCaseSensitive(j,"error");assert(error);
    assert(cJSON_GetObjectItemCaseSensitive(error,"code")->valueint==code);cJSON_Delete(j);
}
int main() {
    aim::Framer usb,ble;std::vector<std::string> complete;
    auto callback=[&](const std::string& s){complete.push_back(s);};
    std::string json="{\"id\":7,\"method\":\"example\",\"params\":{\"text\":\""+std::string(140,'a')+"}\\\"[\"}}";
    auto frames=packets(json);
    for(auto& frame:frames)usb.feed(frame.data(),frame.size(),10,callback);
    assert(complete.size()==1&&complete[0]==json);
    // 半包分属不同传输时不可拼接。
    complete.clear();usb.feed(frames[0].data(),63,20,callback);
    for(size_t i=1;i<frames.size();++i)ble.feed(frames[i].data(),63,20,callback);
    assert(complete.empty());
    usb.reset();ble.reset();
    Packet invalid{};invalid[0]=2;invalid[1]=62;usb.feed(invalid.data(),63,30,callback);assert(usb.errors==1);
    auto timed=packets("{\"text\":\""+std::string(120,'x')+"\"}");
    usb.feed(timed[0].data(),63,100,callback);usb.feed(timed[1].data(),63,1200,callback);assert(usb.errors>=2);
    usb.reset();complete.clear();
    for(auto& p:packets("{\"x\":1}{\"y\":2}"))usb.feed(p.data(),63,1400,callback);
    assert(complete.size()==2);
    usb.reset();complete.clear();
    std::string oversized="{\"x\":\""+std::string(4200,'a')+"\"}\n";
    for(size_t i=0;i<oversized.size();i+=61) {Packet p{};p[0]=2;p[1]=uint8_t(std::min(size_t(61),oversized.size()-i));std::memcpy(p.data()+2,oversized.data()+i,p[1]);usb.feed(p.data(),63,1500,callback);}
    assert(complete.empty());
    for(auto& p:packets("{\"ok\":true}"))usb.feed(p.data(),63,1600,callback);
    assert(complete.size()==1);
    bool called=false;assert(!aim::send_fragments(std::string(4097,'x'),[&](const uint8_t*,size_t){called=true;return true;}));assert(!called);
    aim::Protocol protocol("0.1.0-ai-micro-basic");protocol.status=[]{return "{\"battery\":50}";};
    assert(protocol.request(R"({"id":"abc","method":"sys.version"})").find("0.1.0-ai-micro-basic")!=std::string::npos);
    assert(protocol.request(R"({"id":2,"method":"device.status"})").find("50")!=std::string::npos);
    expect_error(protocol,"{",-32700);expect_error(protocol,"{} trailing",-32700);
    expect_error(protocol,R"({"id":1})",-32600);
    expect_error(protocol,R"({"id":1,"method":"unknown"})",-32601);
    assert(protocol.request(R"({"method":"unknown"})").empty());
    assert(protocol.request(R"({"id":3,"method":"v.oai.thstatus","params":[{"id":0,"c":255,"b":0.4,"e":"breath"}]})").find("true")!=std::string::npos);
    assert(protocol.lights.agents[0].rgb==255&&protocol.lights.agents[0].effect==4);
    expect_error(protocol,R"({"id":4,"method":"v.oai.thstatus","params":[{"id":0,"c":1},{"id":7}]})",-32602);
    assert(protocol.lights.agents[0].rgb==255); // 拒绝整批，不部分应用
    expect_error(protocol,R"({"id":5,"method":"v.oai.thstatus","params":[{"id":0},{"id":0}]})",-32602);
    expect_error(protocol,R"({"id":6,"method":"v.oai.rgbcfg","params":{"ambient":{"b":2}}})",-32602);
    expect_error(protocol,R"({"id":6,"method":"v.oai.rgbcfg","params":{"a":{}}})",-32602);
    assert(protocol.request(R"({"id":7,"method":"v.oai.rgbcfg","params":{"ambient":{"c":16711680},"keys":{"e":3}}})").find("true")!=std::string::npos);
    assert(protocol.lights.ambient.rgb==0xFF0000&&protocol.lights.commands.effect==3);
    assert(aim::Protocol::key("AG00",true,0).find("\"ag\":0")!=std::string::npos);
    assert(aim::Protocol::radial(aim::angle(aim::Direction::Up),1).find("0.75")!=std::string::npos);
    aim::Debounce key;assert(!key.update(true,0));assert(!key.update(false,5));assert(!key.update(true,10));assert(key.update(true,30));assert(key.stable);
    assert(!key.update(false,35));assert(key.update(false,55));assert(!key.stable);
    aim::Encoder encoder;int turns=0;for(auto v:{1,0,2,3})turns+=encoder.update(v);assert(std::abs(turns)==1);
    assert(aim::direction(0,0)==aim::Direction::Center);assert(aim::direction(700,0)==aim::Direction::Right);
    assert(aim::direction(0,-700)==aim::Direction::Down);
    for(size_t a=0;a<aim::key_bits.size();++a)for(size_t b=a+1;b<aim::key_bits.size();++b)assert(aim::key_bits[a]!=aim::key_bits[b]);
    std::cout<<"PASS: framing, RPC, invalid input, light transactions, key map, debounce, encoder, joystick\n";
}
