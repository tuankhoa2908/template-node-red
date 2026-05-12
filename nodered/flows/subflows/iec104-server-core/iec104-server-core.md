# Hướng dẫn sử dụng Subflow: iec104-server-core

Subflow `iec104-server-core` là một thành phần trung tâm dùng để bọc (wrapper) và quản lý tiến trình của một IEC104 Server bên trong Node-RED. Nó tự động chạy server, nhận dữ liệu thô (stdout), xử lý chuỗi JSON, và phân loại luồng dữ liệu (routing) để gửi tới các flow khác.

## 1. Chức năng chính
- Khởi chạy và quản lý vòng đời của tiến trình `json-iec104-server` thông qua node daemon.
- Đọc luồng dữ liệu từ tiêu chuẩn đầu ra (stdout) của tiến trình, tách từng dòng dữ liệu và parse thành object JSON.
- Phân tích và phân luồng thông điệp IEC104 thành các loại khác nhau: trạng thái kết nối, lệnh điều khiển (commands), log kiểm toán (audit), và lỗi.

## 2. Đầu vào (Inputs)

Subflow này có duy nhất **1 cổng đầu vào**:
- **`msg.payload`**: Dùng để gửi chuỗi JSON (hoặc object) trực tiếp vào luồng tiêu chuẩn đầu vào (stdin) của daemon. Cho phép tương tác 2 chiều với IEC104 server nếu cần thiết.

## 3. Đầu ra (Outputs)

Subflow này có **5 cổng đầu ra** được đánh số thứ tự từ trên xuống dưới, phục vụ cho các mục đích xử lý khác nhau:

1. **Raw Data (Dữ liệu thô):** Trả về toàn bộ dữ liệu sự kiện IEC104 đã được parse sang JSON mà không qua lọc.
2. **Connection Status (Trạng thái kết nối):** Trả về object chứa thông tin trạng thái khi server có client (SCADA) kết nối hoặc ngắt kết nối (`iec104_connected: true/false`).
3. **Command Object (Lệnh điều khiển):** Trả về các lệnh điều khiển từ SCADA (vd: type 45 hoặc 50). Các lệnh này đã được map với `IOA_MAP_JSON` để trở thành các action (ví dụ: `set_power_draw_kw`) có thể dễ dàng sử dụng cho luồng write-back tới thiết bị thật.
4. **Audit Log:** Trả về dữ liệu chi tiết của các lệnh điều khiển kèm theo `event_id`, dùng để lưu log kiểm soát hệ thống.
5. **Errors:** Trả về các log lỗi định dạng chuẩn từ quá trình thực thi daemon (stderr) hoặc mã lỗi khi tiến trình ngưng hoạt động (exit code).

## 4. Biến môi trường (Subflow Properties / Environment Variables)

Để sử dụng cho các dự án khác nhau, bạn có thể thiết lập các biến môi trường cấu hình (Environment Variables) trực tiếp trên Properties của subflow khi kéo ra flow chính:

| Biến (Variable) | Kiểu dữ liệu | Giá trị mặc định | Mô tả |
| :--- | :--- | :--- | :--- |
| **`SERVER_COMMAND`** | String | `/usr/local/bin/json-iec104-server` | Đường dẫn tuyệt đối đến file thực thi binary của iec104 server. |
| **`IOA_MAP_JSON`** | JSON | *(Xem ví dụ bên dưới)* | Một Object JSON mapping các địa chỉ IOA sang định dạng dữ liệu (key, type, unit) để phân tích các lệnh. |
| **`DEFAULT_DEVICE_ID`** | String | `inverter-01` | ID thiết bị mặc định được gán cho các command và audit event nếu dữ liệu gốc không có. |
| **`DEFAULT_ZONE_ID`** | String | `zone-01` | ID khu vực mặc định được gán cho các sự kiện. |

### Ví dụ cấu hình `IOA_MAP_JSON`:
```json
{
  "1": {
    "key": "power_draw_kw",
    "type": "M_ME_NC_1",
    "unit": "kw"
  },
  "2": {
    "key": "export_limit_kw",
    "type": "M_ME_NC_1",
    "unit": "kw"
  },
  "3": {
    "key": "inverter_status",
    "type": "M_SP_NA_1",
    "unit": "bool"
  }
}
```

## 5. Cách sử dụng trong luồng (Flow)
1. Cài đặt các thư viện cần thiết cho Node-RED nếu có (như `node-red-node-daemon`).
2. Kéo subflow `iec104-server-core` vào không gian làm việc.
3. Click đúp vào subflow để mở bảng Properties. Tùy chỉnh đường dẫn `SERVER_COMMAND` cho đúng với hệ thống thực tế (nếu chạy bằng Docker, cần đảm bảo file binary nằm đúng đường dẫn map bên trong container).
4. Sửa lại cấu hình `IOA_MAP_JSON` với danh sách các địa chỉ điều khiển (IOA) cho phù hợp với dự án.
5. Nối các dây tương ứng từ 5 cổng ra vào các node như `debug`, `mqtt out`, hoặc logic xử lý write-back xuống các thiết bị vật lý (Inverter, Load, v.v.).
