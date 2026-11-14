# Thông báo 2.20.32 — gia cố và kiểm thử không điều khiển Windows

Ứng viên này giữ cách chọn kênh của 2.20.31, bổ sung xử lý dữ liệu lỗi và áp dụng tùy chọn toast ngay trong lúc thông báo đang chờ. Panel đang cài được giữ ở 2.20.30. Gói 2.20.31 được giữ nguyên để đối chiếu; gói mới có số phiên bản riêng.

Theo yêu cầu mới của người dùng, lượt thực hiện này không điều khiển giao diện Windows, không mở cửa sổ mẫu, không thử lấy focus/gửi toast và không điều khiển Premiere. Việc sửa code tính năng đưa cửa sổ lên trước vẫn nằm trong phạm vi chương trình đã yêu cầu; tính năng đó không được gọi để kiểm thử ở lượt này.

## Các điểm đã sửa

- Bridge kiểm tra cấu trúc thông điệp sau JSON.parse. Dữ liệu `null`, mảng, số, chuỗi hoặc thiếu trường định danh làm kênh native dừng an toàn; không ném lỗi sang luồng tác vụ. Dữ liệu đến sau khi đã dừng không kích hoạt lại bridge.
- Helper kiểm schema bằng lớp C# thuần trước khi chuyển dữ liệu lên luồng UI. Kiểm kiểu dữ liệu, kích thước và định danh; không chấp nhận các lệnh approve/retry/Save/Undo. Có kiểm tra phòng vệ thêm ở bộ xử lý.
- Tắt toast trong lúc đang chờ kết quả focus sử dụng tùy chọn mới nhất, thay vì bản chụp tùy chọn lúc phát sinh sự cố.
- Tắt toast trước handshake đổi cả thông điệp đang xếp hàng, tránh gửi rồi mới ẩn. Nếu toast đã tồn tại, lệnh hide-toast ẩn riêng toast và vô hiệu hóa callback cũ, vẫn giữ nguyên sự cố/cửa sổ xem/lựa chọn xét duyệt.
- Sự kiện báo trạng thái gửi kiểm cả ID phiên, lượt chạy và sự cố.
- Script mở cửa sổ mẫu yêu cầu cờ `--show-window` rõ ràng. Không chạy script đó trong lượt này.

## Kiểm thử không tích hợp Windows

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1 -NoWindowsIntegration
```

Chế độ này bỏ qua sáu nhóm liên quan helper native, registry, shortcut và vòng đời cài/gỡ. Danh sách bỏ qua được in rõ, không được tính là đạt. Vẫn chạy mock DOM/tiến trình, schema C# thuần, kiểm planner/engine và kiểm đóng gói bằng fixture file. Kiểm tra an toàn đường dẫn tạo junction riêng trong fixture; không thay đường dẫn dữ liệu người dùng.

Bộ kiểm schema C# chạy 52 assertions, không tham chiếu WinForms/WinRT hoặc gọi API cửa sổ. Kiểm định tuyến dùng chung 1.841 assertions. Kết quả cửa sổ/toast/installer của phiên bản trước chỉ là bằng chứng lịch sử; không được coi là nghiệm thu native của 2.20.32.

Kết quả lượt này: 34 nhóm kiểm thử đạt, 98 file PowerShell phân tích cú pháp đạt; sáu nhóm tích hợp Windows được bỏ qua. Log tại `dist/notification-2.20.32-no-windows-tests.txt`. Helper chỉ được biên dịch để đóng gói, không chạy trong lượt này.

## Bước nghiệm thu do người dùng thực hiện

Chỉ thực hiện khi sẵn sàng dùng ứng viên, trên bản sao Project:

| Bước | Kết quả cần thấy |
| --- | --- |
| Đóng Premiere rồi tự giải nén đầy đủ gói 2.20.32, chạy Setup-Panel.cmd | Setup hoàn tất; mở panel thấy đúng 2.20.32 |
| Kiểm tra SRT/đầu vào bằng tác vụ nhỏ | Lỗi xác định được hiện cạnh trường, thông báo có giải thích và hướng xử lý |
| Bấm Xem trong cửa sổ riêng khi có lỗi | Cửa sổ đọc được đầy đủ; vẫn thao tác được Premiere; đóng cửa sổ không chấp thuận tác vụ |
| Với sự cố phát sinh khi chạy nền, bật/tắt từng tùy chọn thông báo | Bật đưa app lên trước: thử một lần; tắt: không lấy focus; toast tuân thủ lựa chọn riêng và cài đặt Windows |
| Tắt toast khi đang chờ hoặc đang hiện | Toast không gửi thêm hoặc được ẩn; sự cố vẫn còn trong panel để kiểm tra |
| Đóng sự cố/bắt đầu lượt mới, sau đó thử thông báo cũ nếu còn | Không mở lại hoặc thực hiện tác vụ của lượt cũ |
| Kiểm timeline, Play và Save sau lượt thử | Kết quả đúng; phản hồi/lưu bình thường |

Chưa thực hiện các bước trên trong lượt phát triển này. Không cài tự động ứng viên hoặc mở/đóng Premiere.

## Cập nhật cài đặt theo yêu cầu tiếp theo

Đã cài 2.20.32 bằng dòng lệnh ngày 15/10/2026 sau khi xác nhận Premiere đã đóng. Đối chiếu 56/56 file cài đúng manifest; shortcut thông báo đúng AUMID/đích; helper khớp SHA256. Toàn bộ 599 file dữ liệu hiện có và 22 thư mục được giữ nguyên qua đối chiếu trước/sau. Lần quét Defender của gói không ghi nhận phát hiện mới.

Không mở/đóng Premiere, không chạy helper giao diện hoặc điều khiển cửa sổ. Người dùng chỉ cần mở Premiere, mở panel nếu cần và chạy thử bình thường; kiểm tra Play/Save rồi báo kết quả. Các bước cài/giải nén trong bảng trên đã được thực hiện thay người dùng. Chưa xác nhận nghiệm thu native.

Bằng chứng: `dist/_installation-2.20.32-20261015-145423/verified.json`. Gói 2.20.30 và 2.20.31 vẫn được giữ để đối chiếu/khôi phục.
