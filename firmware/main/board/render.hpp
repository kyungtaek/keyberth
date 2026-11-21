// SPDX-License-Identifier: MIT
#pragma once
#include "pins.hpp"
#include "../protocol/protocol.hpp"
#include <cmath>

namespace aim {
template<class Pixel>
void render_pixels(const Lights& lights,int64_t now,const Pixel& pixel) {
    auto draw=[&](unsigned index,const Light& light,unsigned position,unsigned count) {
        uint32_t color=light.rgb;
        float b=light.brightness;
        double phase=std::fmod(now/1000.0*(0.2+light.speed*2.0),1.0);
        switch(light.effect) {
            case 0: b=0; break;
            case 2: {
                // Overlap neighbouring pixels as the peak travels around the ring.
                double angle=(phase-double(position)/count)*6.283185307;
                double wave=(1.0+std::cos(angle))*0.5;
                b*=wave*wave*wave;
                break;
            }
            case 3: {
                auto wave=[&](double offset){return uint32_t((0.5+0.5*std::sin((phase+offset)*6.2831853))*255);};
                color=(wave(0)<<16)|(wave(1.0/3)<<8)|wave(2.0/3);
                break;
            }
            case 4: b*=0.5-0.5*std::cos(phase*6.2831853); break;
            case 5: b*=0.4+0.6*phase; break;
            case 6: b*=0.75-0.25*std::cos(phase*6.2831853); break;
        }
        pixel(index,color,b);
    };
    for(unsigned i=0;i<8;i++) draw(i,lights.ambient,i,8);
    for(unsigned i=0;i<agent_pixels.size();i++) draw(agent_pixels[i],lights.agents[i],0,1);
    for(unsigned i=0;i<command_pixels.size();i++) {
        if(lights.individual) draw(command_pixels[i],lights.functions[i],0,1);
        else draw(command_pixels[i],lights.commands,i,command_pixels.size());
    }
}
}
