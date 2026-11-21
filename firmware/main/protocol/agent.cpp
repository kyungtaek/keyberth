#include "agent.hpp"
#include <algorithm>
#include <array>
#include <charconv>
#include <cstring>
#include <string_view>

namespace aim {
namespace {
bool integer(std::string_view s, unsigned& value, int base = 10) {
    if (s.empty()) return false;
    auto r = std::from_chars(s.data(), s.data()+s.size(), value, base);
    return r.ec == std::errc{} && r.ptr == s.data()+s.size();
}
template<size_t N>
bool split(std::string_view value, char sep, std::array<std::string_view,N>& parts) {
    for (size_t i=0;i<N;i++) {
        auto end=value.find(sep);
        parts[i]=value.substr(0,end);
        if (end==value.npos) return i+1==N;
        value.remove_prefix(end+1);
    }
    return false;
}
bool style(std::string_view payload, Lights& lights) {
    std::array<std::string_view,5> fields;
    unsigned target,color,effect,brightness,speed;
    if (!split(payload,':',fields) || !integer(fields[0],target) || target>13 ||
        fields[1].size()!=6 || !integer(fields[1],color,16) ||
        !integer(fields[2],effect) || effect>6 || !integer(fields[3],brightness) ||
        brightness>100 || !integer(fields[4],speed) || speed>100) return false;
    Light next{color,brightness/100.f,speed/100.f,static_cast<uint8_t>(effect)};
    if (target==0) lights.ambient=next;
    else if (target<=6) lights.agents[target-1]=next;
    else lights.functions[target-7]=next;
    return true;
}
}
void Agent::reset() {
    session.clear(); partial.clear(); assembling=false; generic=false; sessionKeys=false;
    inputSequence=sequence=0; defaultRunning.fill(false); lights=Lights{};
}
void Agent::tick(bool connected,int64_t now) {
    if (active() && (!connected || now-lastCommand>=4000)) reset();
}
bool Agent::reply(const std::string& line) {
    for (size_t offset=0;offset<line.size();offset+=15) {
        size_t n=std::min<size_t>(15,line.size()-offset);
        uint8_t frame[19]={0xa1,static_cast<uint8_t>((offset==0?1:0)|(offset+n==line.size()?2:0)),
                           static_cast<uint8_t>(offset/15),static_cast<uint8_t>(n)};
        std::memcpy(frame+4,line.data()+offset,n);
        if (!send(frame,sizeof(frame))) return false;
    }
    return true;
}
void Agent::receive(const uint8_t* p,size_t n,int64_t now) {
    if (n!=19 || p[0]!=0xa1 || p[1]>3 || p[3]==0 || p[3]>15) { assembling=false; return; }
    if (p[1]&1) { partial.clear(); fragment=0; assembling=true; }
    if (!assembling || p[2]!=fragment++ || partial.size()+p[3]>128) { assembling=false; return; }
    partial.append(reinterpret_cast<const char*>(p+4),p[3]);
    if (p[1]&2) { assembling=false; command(partial,now); }
}
void Agent::command(const std::string& line,int64_t now) {
    std::array<std::string_view,2> hello;
    if (split(line,'\t',hello) && hello[0]=="AMHELLO" && hello[1].size()==32 &&
        hello[1].find_first_not_of("0123456789abcdef")==hello[1].npos) {
        std::string token(hello[1]); reset(); session=token; lights.individual=true; lastCommand=now;
        reply("AMHELLO\t{\"session\":\""+session+"\",\"protocol\":\"ai-micro-agent-v1\","
              "\"version\":\"" BASIC_VERSION "\",\"hardware\":\"AI Micro\",\"slots\":6,"
              "\"capabilities\":[\"input-events\",\"slot-states\",\"selected-slot\",\"keyberth-light-v1\"]}");
        return;
    }
    std::array<std::string_view,4> fields{};
    if (!split(line,'\t',fields)) {
        std::array<std::string_view,3> shorter;
        if (!split(line,'\t',shorter)) return;
        std::copy(shorter.begin(),shorter.end(),fields.begin());
    }
    unsigned seq;
    if (!active() || fields[1]!=session || !integer(fields[2],seq) || seq!=sequence+1) return;
    auto name=fields[0], value=fields[3];
    if (name=="AMMODE" && value=="generic") generic=true;
    else if (generic && name=="AMKEYMODE" && value=="sessions") sessionKeys=true;
    else if (controls() && name=="AMFRAME" && value.size()==6 && value.find_first_not_of("01234")==value.npos) {
        constexpr uint32_t colors[]={0,0xffffff,0x268aff,0xff9800,0x31c56b};
        for (size_t i=0;i<6;i++) {
            defaultRunning[i]=value[i]=='2';
            lights.agents[i]={colors[value[i]-'0'],0.55f,0.5f,static_cast<uint8_t>((defaultRunning[i] && lights.selected==i+1)||value[i]=='3'?4:1)};
        }
    } else if (controls() && name=="AMSELECT" && value.size()==1 && value[0]>='0' && value[0]<='6') {
        lights.selected=value[0]-'0';
        for(size_t i=0;i<6;i++) if(defaultRunning[i]) lights.agents[i].effect=lights.selected==i+1?4:1;
    } else if (controls() && name=="KBLED" && style(value,lights)) {
        unsigned target;
        if(integer(value.substr(0,value.find(':')),target) && target>=1 && target<=6)
            defaultRunning[target-1]=false;
    } else if (name=="AMBYE" && value.empty()) { reply("AMACK\t"+std::to_string(seq)); reset(); return; }
    else if (name!="AMHEARTBEAT" || !value.empty()) { reply("MKERR\tinvalid_command"); return; }
    sequence=seq; lastCommand=now; reply("AMACK\t"+std::to_string(seq));
}
void Agent::input(const std::string& id,bool pressed) {
    if (controls()) reply("AMINPUT\t{\"session\":\""+session+"\",\"seq\":"+std::to_string(++inputSequence)+
                          ",\"id\":\""+id+"\",\"pressed\":"+(pressed?"true}":"false}"));
}
}
