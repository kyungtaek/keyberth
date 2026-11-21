// SPDX-License-Identifier: MIT
#pragma once
#include <cstdint>
#include <cstdlib>
namespace aim {
struct Debounce {
    bool sample=false, stable=false;
    int64_t since=0;
    bool update(bool value, int64_t ms) {
        if(value!=sample) { sample=value; since=ms; }
        if(sample!=stable && ms-since>=20) { stable=sample; return true; }
        return false;
    }
};
// 四相完整周期产生一次事件；跳变两位丢弃该周期。
struct Encoder {
    uint8_t previous=3; int steps=0;
    int update(uint8_t value) {
        static constexpr int8_t delta[16]={0,-1,1,0,1,0,0,-1,-1,0,0,1,0,1,-1,0};
        if((previous^value)==3) steps=0;
        else steps+=delta[(previous<<2)|value];
        previous=value;
        if(value==3) { int result=steps>=4 ? 1 : steps<=-4 ? -1 : 0; steps=0; return result; }
        return 0;
    }
};
enum class Direction { Center, Right, Up, Left, Down };
inline Direction direction(int x,int y) {
    if(std::abs(x)<500 && std::abs(y)<500) return Direction::Center;
    if(std::abs(x)>=std::abs(y)) return x>0 ? Direction::Right : Direction::Left;
    return y>0 ? Direction::Up : Direction::Down;
}
inline float angle(Direction d) {
    switch(d) { case Direction::Right:return 0; case Direction::Up:return 0.75f;
        case Direction::Left:return 0.5f; case Direction::Down:return 0.25f; default:return 0; }
}
}
