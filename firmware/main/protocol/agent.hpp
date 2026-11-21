#pragma once
#include "protocol.hpp"

namespace aim {
// USB report 7, independent of the BLE/report 6 JSON transport.
class Agent {
public:
    using Output = std::function<bool(const uint8_t*, size_t)>;
    explicit Agent(Output output) : send(std::move(output)) {}
    void receive(const uint8_t* packet, size_t size, int64_t now);
    bool active() const { return !session.empty(); }
    bool controls() const { return active() && generic && sessionKeys; }
    void tick(bool connected, int64_t now);
    void input(const std::string& id, bool pressed);
    std::function<void()> alert;
    Lights lights{};
private:
    Output send;
    std::string session, partial;
    uint8_t fragment = 0;
    std::array<bool,6> defaultRunning{};
    unsigned sequence = 0, inputSequence = 0;
    int64_t lastCommand = 0;
    bool generic = false, sessionKeys = false, assembling = false;
    void reset();
    void command(const std::string& line, int64_t now);
    bool reply(const std::string& line);
};
}
