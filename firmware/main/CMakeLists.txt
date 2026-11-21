idf_component_register(
    SRCS "app_main.cpp" "trial.cpp" "board/board.cpp" "protocol/protocol.cpp" "protocol/agent.cpp"
         "transport/usb.cpp" "transport/ble.cpp" "transport/bonds.cpp" "preferences.cpp"
    INCLUDE_DIRS "."
    PRIV_REQUIRES bt nvs_flash app_update mbedtls esp_adc esp_driver_gpio esp_driver_ledc esp_driver_rmt
                  esp_driver_touch_sens esp_timer esp_system esp_psram json usb)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
target_compile_definitions(${COMPONENT_LIB} PRIVATE BASIC_VERSION="${PROJECT_VER}")
