# SolarEdge Multi-Inverter Reader

Module đọc hàng loạt inverter SolarEdge SunSpec (block 40070–40096) từ **1 file config duy nhất**.

## Cấu trúc file

```text
reading-data-inventer/
├── README.md                              ← File này
├── inverters.config.json                  ← Config danh sách inverter
├── sf_solaredge_inverter_reader.json      ← Subflow đọc & parse 1 inverter (tuỳ chọn)
└── flow_multi_inverter_reader.json        ← Flow chính: dispatcher + dynamic connect
```

## Nguyên lý hoạt động

```
┌──────────────┐    ┌──────────────────┐    ┌──────────────────────┐
│ inverters    │    │  Inject          │    │  Dispatcher          │
│ .config.json │───▶│  (load on start) │───▶│  (đọc global config) │
└──────────────┘    └──────────────────┘    └──────────┬───────────┘
                                                       │
                                           ┌───────────▼───────────┐
                                           │  N msg (1 per inverter)│
                                           └───────────┬───────────┘
                                                       │
                              ┌─────────────────────────▼────────────────────────┐
                              │  modbus-flex-connector (đổi IP/port động)        │
                              │  → Build fc3 request                             │
                              │  → modbus-flex-getter (đọc registers)            │
                              │  → Parse SunSpec → global.set(INVxxx, result)    │
                              └─────────────────────────┬────────────────────────┘
                                                        │
                                            ┌───────────▼───────────┐
                                            │  Join → Summary       │
                                            │  global.INV_SUMMARY   │
                                            └───────────────────────┘
```

## Cách sử dụng

### 1. Cấu hình inverters

Sửa file `inverters.config.json`:

```json
{
  "inverters": [
    {
      "name": "INV154",
      "ip": "192.168.1.154",
      "port": 1502,
      "unitid": 1,
      "enabled": true
    },
    {
      "name": "INV155",
      "ip": "192.168.1.155",
      "port": 1502,
      "unitid": 1,
      "enabled": true
    }
  ]
}
```

Muốn tạm tắt inverter nào → đặt `"enabled": false`.

### 2. Import vào Node-RED

**Cách A – Flow đầy đủ (khuyến nghị):**

1. Import `flow_multi_inverter_reader.json` (Menu → Import → chọn file)
2. Sửa đường dẫn trong node `Read inverters.config.json` cho đúng với container/hệ thống
3. Deploy

**Cách B – Subflow riêng lẻ:**

1. Import `sf_solaredge_inverter_reader.json`
2. Tự tạo dispatcher + modbus-client config cho mỗi inverter

### 3. Kiểm tra

Sau khi Deploy:

- Sidebar Debug sẽ hiện: `{ ok: true, count: 5, inverters: ["INV154", ...] }`
- Mỗi 5s sẽ đọc tuần tự tất cả inverter
- Kết quả lưu vào `global.INV154`, `global.INV155`, ...
- Tổng hợp lưu vào `global.INV_SUMMARY`

## Kết quả mỗi inverter (global.INVxxx)

```json
{
  "name": "INV154",
  "type": "INVERTER",
  "ip": "192.168.1.154",
  "unitid": 1,
  "port": 1502,
  "ts": 1716012345,
  "model_did": 103,
  "model_length": 50,
  "Pinv_out_kw": 12.345,
  "Qinv_kvar": 0.123,
  "Ua_V": 230.12,
  "Ub_V": 231.05,
  "Uc_V": 229.98,
  "Ia_A": 17.891,
  "Ib_A": 17.562,
  "Ic_A": 17.923,
  "I_total_A": 53.376,
  "frequency_Hz": 50.001,
  "pf_percent": 99.2,
  "power_factor": 0.992,
  "Ainv_total_kWh": 123456.789,
  "raw_registers": [103, 50, ...]
}
```

## Tổng hợp (global.INV_SUMMARY)

```json
{
  "ts": 1716012345,
  "total_inverters": 5,
  "total_power_kW": 61.725,
  "total_energy_kWh": 617283.945,
  "details": [
    { "name": "INV154", "kW": 12.345, "kWh": 123456.789 },
    { "name": "INV155", "kW": 12.345, "kWh": 123456.789 }
  ]
}
```

## Hai approach cho multi-inverter

### Approach 1: `modbus-flex-connector` (file `flow_multi_inverter_reader.json`)

Dùng **1 modbus-client duy nhất** + `modbus-flex-connector` để đổi IP/port **động** mỗi khi đọc inverter khác. Ưu/nhược:

| Ưu điểm | Nhược điểm |
|---|---|
| Chỉ cần 1 modbus-client config | Đọc tuần tự (sequential) |
| Config hoàn toàn từ JSON | Mỗi lần đổi IP phải reconnect TCP |
| Thêm inverter = thêm 1 dòng JSON | Có thể chậm nếu nhiều inverter (>10) |

### Approach 2: Nhiều `modbus-client` (file `sf_solaredge_inverter_reader.json`)

Tạo **1 modbus-client riêng** + **1 subflow instance** cho mỗi inverter. Ưu/nhược:

| Ưu điểm | Nhược điểm |
|---|---|
| Đọc song song (parallel) | Phải tạo modbus-client config cho mỗi inverter |
| Kết nối TCP giữ luôn (persistent) | Thêm inverter = thêm node trên canvas |
| Nhanh hơn khi có nhiều inverter | Cần quản lý nhiều config node |

**Khuyến nghị**: Dùng Approach 1 nếu ≤ 10 inverter. Dùng Approach 2 nếu cần performance cao hoặc > 10 inverter.

## Lưu ý

1. **Đường dẫn config**: Trong Docker, file nằm ở `/data/flows/...`. Nếu chạy native, sửa đường dẫn trong node `file in`.
2. **modbus-flex-connector** cần package `node-red-contrib-modbus` phiên bản ≥ 5.x.
3. Nếu `modbus-flex-connector` không khả dụng trên phiên bản Modbus của bạn, hãy dùng Approach 2 (subflow riêng lẻ).
4. **Thứ tự đọc**: Dispatcher gửi msg theo thứ tự trong config. Nếu inverter nào offline, timeout sẽ chỉ ảnh hưởng inverter đó.
