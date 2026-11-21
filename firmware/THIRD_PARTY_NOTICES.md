# 第三方依赖

自有源码和说明使用根目录 MIT 许可。以下依赖由公开上游获取，许可不被本工程 MIT 替换。

| 依赖 | 固定版本 | 来源及许可 |
|---|---|---|
| ESP-IDF | 5.5.4 | https://github.com/espressif/esp-idf/tree/v5.5.4 ，主要为 Apache-2.0；包含按各自许可分发的组件及 Espressif 二进制库 |
| esp_tinyusb | 2.2.1 | https://components.espressif.com/components/espressif/esp_tinyusb ，Apache-2.0 |
| TinyUSB | 0.21.0~1 | https://components.espressif.com/components/espressif/tinyusb ，MIT |
| Apache NimBLE | ESP-IDF 5.5.4 固定的子模块 | https://github.com/apache/mynewt-nimble ，Apache-2.0 |
| cJSON | ESP-IDF 5.5.4 固定的子模块 | https://github.com/DaveGamble/cJSON ，MIT |

源码包不嵌入这些依赖，使用依赖清单和锁定文件获取。预编译包附带构建依赖中的 LICENSE / NOTICE / COPYING 等许可文件及上游来源清单；Espressif 的预编译蓝牙控制器等库仍遵循其上游许可，不属于本工程自有开源源码。

不包含 Work Louder / OpenAI 桌面应用或专有 SDK 的源代码、安装包或派生代码。HID 描述与 RPC 仅为本设备互操作的独立实现，不构成第三方官方认证。USB/BLE 的兼容标识不授予其他硬件使用第三方标识的权利。
