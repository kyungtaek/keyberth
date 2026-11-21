#include "protocol/agent.hpp"
#include "board/render.hpp"
#include <cassert>
#include <cstring>
#include <iostream>

int main() {
    std::string response;
    aim::Agent device([&](const uint8_t* p,size_t n) {
        assert(n==19 && p[0]==0xa1 && p[3]<=15);
        if(p[1]&1) response.clear();
        response.append(reinterpret_cast<const char*>(p+4),p[3]);
        return true;
    });
    std::string token(32,'a');
    auto write=[&](std::string line) {
        response.clear();
        for(size_t pos=0;pos<line.size();pos+=15) {
            size_t n=std::min<size_t>(15,line.size()-pos);
            uint8_t packet[19]={0xa1,uint8_t((pos==0?1:0)|(pos+n==line.size()?2:0)),uint8_t(pos/15),uint8_t(n)};
            std::memcpy(packet+4,line.data()+pos,n);
            device.receive(packet,19,100);
        }
    };
    write("AMHELLO\t"+token);
    assert(response.find("keyberth-light-v1")!=std::string::npos);
    unsigned seq=0;
    auto command=[&](std::string name,std::string payload) {
        write(name+"\t"+token+"\t"+std::to_string(++seq)+"\t"+payload);
        assert(response=="AMACK\t"+std::to_string(seq));
    };
    command("AMMODE","generic"); command("AMKEYMODE","sessions");
    command("AMFRAME","012341"); command("AMSELECT","3");
    assert(device.lights.agents[2].rgb==0x268aff && device.lights.selected==3);
    for(unsigned key=1;key<=13;++key) command("KBLED",std::to_string(key)+":123456:1:50:50");
    command("KBLED","13:00ff00:4:55:50"); command("KBLED","0:268aff:2:40:60");
    assert(device.lights.ambient.rgb==0x268aff && device.lights.ambient.effect==2);
    assert(device.lights.functions[6].rgb==0xff00 && device.lights.functions[6].effect==4);
    for(unsigned i=0;i<6;i++) assert(device.lights.functions[i].rgb==0x123456);
    std::array<unsigned,21> seen{};
    unsigned litAmbient=0;
    aim::render_pixels(device.lights,410,[&](unsigned i,uint32_t rgb,float brightness) {
        assert(i<21);
        seen[i]++;
        if(i<8 && brightness>0) { assert(rgb==0x268aff); litAmbient++; }
        if(i==10) assert(rgb==0x00ff00 && brightness>0);
        if(i>=8 && i!=10) assert(rgb==0x123456);
    });
    assert(litAmbient>=6);
    for(auto writes:seen) assert(writes==1);
    write("KBLED\t"+token+"\t"+std::to_string(seq+1)+"\t14:123456:1:50:50");
    assert(response.rfind("MKERR",0)==0 && device.lights.functions[6].rgb==0xff00);
    device.input("K13",true); assert(response.find("\"pressed\":true")!=std::string::npos);
    device.input("K13",false); assert(response.find("\"seq\":2")!=std::string::npos);
    device.tick(true,4100); assert(!device.controls() && device.lights.functions[6].rgb==0);
    std::cout<<"PASS report 7 handshake, input, all 13 keys, ambient, validation and timeout\n";
}
