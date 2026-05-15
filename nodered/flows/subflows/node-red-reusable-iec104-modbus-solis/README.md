# Node-RED reusable IEC104 + Modbus + MQTT template

Bộ này tách flow hiện tại thành các subflow có thể tái sử dụng cho nhiều dự án Solar/Solis/IEC104.

## File chính

```text
.env.example
config/site.solis.example.json
config/iec104_config.example.json
subflows/node-red-subflows.import.json
flows/example-main-flow.import.json
```

## Cách import nhanh

1. Copy `.env.example` thành `.env` và sửa theo site thực tế.
2. Copy `config/site.solis.example.json` thành `site.solis.json`.
3. Copy `config/iec104_config.example.json` thành `iec104_config.json`.
4. Trong Node-RED, import `subflows/node-red-subflows.import.json`.
5. Import thêm `flows/example-main-flow.import.json` để có flow mẫu đã nối sẵn.
6. Deploy, kiểm tra debug của `Load config` trước.
7. Sau khi config load OK, bật Modbus poll, IEC104 publish, MQTT publish.

## Các node package cần có

Tối thiểu:

```bash
npm install node-red-contrib-modbus
npm install node-red-contrib-daemon
npm install node-red-node-ping
```

Nếu bạn vẫn dùng buffer-parser ở flow cũ:

```bash
npm install node-red-contrib-buffer-parser
```

Bộ subflow mới không bắt buộc buffer-parser vì đã parse Modbus response bằng function node.

## Subflow

| Subflow | Vai trò |
|---|---|
| `SF_CONFIG_LOAD_SITE_PROFILE` | Đọc `site.solis.json`, validate, set `global.siteConfig` và `global.iec104_templates` |
| `SF_MODBUS_POLL_AND_STORE` | Sinh request từ `modbusReads[]`, đọc Modbus, parse, lưu global key |
| `SF_MODBUS_STATUS_TO_ONLINE_FLAG` | Chuyển status Modbus thành `global.modbus_online`; phát event `invalid` khi offline |
| `SF_IEC104_POINT_PUBLISHER` | Lấy global values và mapping IEC104 để sinh bản tin IEC104 |
| `SF_IEC104_SERVER_BRIDGE` | Bridge Node-RED với daemon `json-iec104-server` |
| `SF_IEC104_COMMAND_TO_MODBUS_WRITE` | Convert command IEC104 execute thành Modbus write |
| `SF_MQTT_SET_CONNECTIVITY` | Set `global.internetAvailable` từ ping/connectivity |
| `SF_MQTT_BUILD_OR_QUEUE` | Build payload MQTT; online thì gửi, offline thì queue |
| `SF_MQTT_FLUSH_QUEUE` | Flush từng bản tin queue khi online |
| `SF_DAILY_SNAPSHOT` | Chụp giá trị cuối ngày, ví dụ `a_Inv_D` -> `a_Inv_D1` |

## Nguyên tắc cấu hình

### Đưa vào `.env`

Dùng cho thông tin thay đổi theo môi trường chạy:

- IP/port Modbus
- MQTT host/port/client ID/topic
- đường dẫn cert
- đường dẫn config/daemon
- interval poll/publish/queue
- device/site id ngắn

### Đưa vào `site.solis.json`

Dùng cho mapping phức tạp:

- danh sách Modbus register cần đọc
- datatype/byteOrder/readScale
- mapping IEC104 point IOA
- mapping IEC104 command -> Modbus write
- danh sách field publish MQTT
- snapshot source/target

### Đưa vào `iec104_config.json`

Dùng cho daemon IEC104:

- ASDU
- danh sách IOA theo type
- mode command
- deadband
- offline timeout

## Lưu ý quan trọng

1. `DAILY_SNAPSHOT_CRON=59 23 * * *` mới đúng là 23:59. Flow cũ ghi tên 23:59 nhưng cron đang là 22:00.
2. `M_ME_NC_1_config` trong file mẫu đã bỏ IOA `4` và `12` khỏi measured points vì mapping hiện tại không có measured IOA 4, còn IOA 12 đang là command `C_SE_NC_1`.
3. `byteOrder` của Modbus float có thể cần chỉnh theo thiết bị thực tế. File mẫu đang dùng `LE` theo logic gần flow cũ. Nếu giá trị đọc sai lớn bất thường, thử đổi `BE`, `CDAB`, `BADC`, hoặc `DCBA`.
4. Subflow daemon dùng `${IEC104_DAEMON_PATH}`. Nếu node `daemon` trên máy bạn không substitute env var ở ô command, sửa trực tiếp command thành đường dẫn thật, ví dụ `/usr/local/bin/json-iec104-server`.
5. MQTT out trong flow mẫu để trống topic ở node, vì topic được set bằng `msg.topic` từ subflow.

## Docker compose gợi ý

```yaml
services:
  node-red:
    image: your-node-red-image:latest
    env_file:
      - .env
    ports:
      - "1880:1880"
    volumes:
      - ./config:/data/config
      - ./certs:/data/certs:ro
      - ./flows:/data/flows
    restart: unless-stopped
```

## Checklist khi tạo dự án mới

1. Tạo bản copy `site.solis.example.json`.
2. Sửa `site.siteId`, `site.siteName`, `site.deviceId`.
3. Sửa `modbusReads[]` theo register map của thiết bị.
4. Sửa `iec104Points[]` theo IOA EVN/SCADA yêu cầu.
5. Sửa `iec104Commands[]` theo các lệnh cho phép điều khiển.
6. Sửa `.env` theo IP, MQTT, cert.
7. Import subflows và flow mẫu.
8. Test từng tầng: Config -> Modbus -> IEC104 -> MQTT.
