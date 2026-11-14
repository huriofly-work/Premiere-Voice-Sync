# Thông báo nhiều kênh — ứng viên 2.20.31

Đã tích hợp vào ứng viên, chưa thay panel 2.20.30 đang cài và chưa nghiệm thu trong Premiere thật. Quyết định thiết kế dựa trên [bản đánh giá 13 hình thức thông báo](../../reviews/NOTIFICATION_CHANNEL_REVIEW_2026-10-15.md).

## Chọn kênh theo tình huống

| Tình huống | Cách hiển thị |
| --- | --- |
| Xác định được lỗi SRT trước khi ghi timeline | Đánh dấu trường SRT, giải thích cạnh trường và giữ thông báo sự cố có hướng xử lý |
| Tiến độ hoặc chưa có phản hồi mới | Trạng thái trong panel; không tự kết luận timeout, không chạy lại lệnh ghi |
| Cảnh báo đã có fallback an toàn | Banner trong panel; không lấy focus hoặc phát tiếng |
| Lỗi hoặc quyết định giữa tác vụ, panel đang có focus | Thông báo nổi bật trong panel; không gửi thêm toast |
| Lỗi hoặc quyết định giữa tác vụ, panel ở nền | Thử mở đúng panel/đưa đúng Premiere lên trước một lần nếu tùy chọn đang bật; chờ ngắn để xác minh focus; nếu chưa thấy panel thì gửi toast im lặng |
| Người dùng tắt đưa app lên trước | Chỉ nhấp nháy taskbar có giới hạn; tùy chọn toast độc lập |
| Tác vụ thành công kéo dài ít nhất 30 giây, panel ở nền | Toast im lặng, không lấy focus |
| Muốn vừa đọc lỗi vừa kiểm tra timeline | Nút **Xem trong cửa sổ riêng**; cửa sổ WinForms modeless có nội dung cuộn và hai nút rõ ràng |

Mốc 30 giây là lựa chọn sản phẩm có thể điều chỉnh sau sử dụng. Windows áp dụng cài đặt thông báo/Không làm phiền; tool không dùng loại alarm/reminder để vượt cài đặt này. Âm thanh tắt. Không triển khai đồng thời một cửa sổ CEP modeless thứ hai vì helper native đã đảm nhiệm việc xem riêng; vẫn cần nghiệm thu tương tác host.

## Xét duyệt và vòng đời

- Quyết định tiếp tục/hủy vẫn nằm trong panel. Cửa sổ riêng chỉ hiển thị giải thích và yêu cầu mở panel; đóng cửa sổ không giải quyết, chấp thuận hoặc chạy lại tác vụ.
- Toast và các nút của cửa sổ riêng chỉ gửi yêu cầu xem sự cố đang sống. Không có lệnh dựng/retry/Undo/Save từ thông báo Windows.
- Kiểm tra phiên, lượt chạy và sự cố ở cả hai đầu pipe. Đóng thông báo trong panel hoặc bắt đầu lượt mới sẽ xóa native incident, đóng cửa sổ liên quan và gỡ toast của phiên đó. Không xóa toast của phiên panel khác.
- Callback cũ/đã đóng không mở lại sự cố. Hết phiên không khởi động lại công việc. Shortcut khởi chạy nguội chỉ thoát an toàn, không tự mở Premiere.
- Callback `ToastNotification.Activated` chỉ phục vụ phiên helper còn sống; click/banner thật, đặc biệt từ Notification Center, vẫn cần nghiệm thu trên máy đích. Không coi `Show` trả về thành công là người dùng đã thấy hoặc đã bấm.
- Lỗi sau khi đã thay đổi Project hoặc chưa rõ kết quả giữ khóa chạy mới như 2.20.30; cửa sổ xem riêng không bỏ qua bước xác minh sau khôi phục.

## Helper và cài đặt

Helper C# WinForms/WinRT được biên dịch bằng .NET Framework của Windows, không tải framework/NuGet khi chạy. Mã nguồn nằm trong `extension/native` và đi kèm gói ZIP. `helper-lock.json` ghi SHA256 nhị phân; panel kiểm tra hash và đường dẫn không có link trước khi spawn.

Giao tiếp qua stdin/stdout riêng của tiến trình con, không socket/port/protocol handler. Helper ràng buộc PID cha thực tế, phiên Windows và thời gian tạo tiến trình; thoát khi pipe đóng hoặc cha biến mất. Giới hạn kích thước thông điệp và thời gian handshake. Helper không đọc cây dữ liệu job/cache/model/project.

Setup tạo shortcut `Premiere Voice Sync Notifications.lnk` trong Start Menu của người dùng với AUMID `PremiereVoiceSync.Notifications`, trỏ đúng helper đã cài. Chỉ cập nhật/gỡ khi cả AUMID và đường dẫn đích khớp; shortcut không thuộc tool làm setup dừng trước khi đổi panel. Cài lỗi khôi phục nguyên byte shortcut cũ hoặc gỡ shortcut mới. Không tạo mục Installed apps hoặc thay cài đặt DND/quyền thông báo của Windows.

Nếu helper không khả dụng, hỏng hash hoặc kết nối lỗi, thông báo trong panel vẫn hoạt động và trạng thái kênh Windows báo chưa khả dụng. Helper không được khởi động lại vòng lặp; mở lại panel để tạo phiên mới sau khi khắc phục.

## Bằng chứng và giới hạn

- Toàn bộ hồi quy: 38 nhóm đạt, 96 file PowerShell phân tích cú pháp đạt. Sau chỉnh cách báo kênh Windows bị tắt, nhóm kiểm thử helper/bridge/định tuyến đã chạy lại và đạt.
- Policy dùng chung với sản phẩm: 384 tổ hợp, 1.841 assertions.
- Kiểm thử bridge và luồng panel: giữ một helper, không gửi trùng; chờ kết quả focus; tắt riêng từng tùy chọn; kết quả dài ở nền; raw lỗi không đưa lên toast; bỏ callback cũ; lỗi pipe/hash giữ đường fallback.
- Helper EXE thật: handshake, ràng buộc cha, thay lượt chạy, từ chối clear cũ và thoát khi EOF; không mở UI trong kiểm thử tự động.
- Shortcut COM thật trong fixture: AUMID/đích, rollback khi cài mới và cập nhật, giữ nguyên byte cũ, từ chối shortcut không thuộc tool.
- Browser fixture: panel 320/385/560 px, nội dung lỗi dài ở chiều cao 520 px, nút an toàn, Escape, hai chế độ, không tràn ngang.
- Computer Use đã quan sát cửa sổ thật của helper với sự cố giả: chữ xuống dòng, đủ hai nút, nút đóng nhận focus; bấm mở panel chỉ ghi yêu cầu `open-panel-request-only`, đóng cửa sổ rồi kiểm tra không còn cửa sổ. Phép thử bắt được và sửa lỗi lần Show đầu bị ẩn do `windowsHide`, cùng lỗi cột tự nở làm mất nút bên phải.

Các bằng chứng này chưa xác nhận banner/click toast của bản tích hợp, DND, nhiều màn hình/DPI hoặc thao tác Project thật trong Premiere. Cần nghiệm thu trên Project sao lưu: lỗi trước/sau thao tác ghi, chờ xét duyệt, Premiere đang ở nền/minimize, panel bị ẩn, đóng/mở panel, kiểm timeline/Play/Save. Không tự điều khiển Premiere sau lần công cụ từ chối quyền trước đó.

Tham khảo API: [Microsoft desktop toast quickstart](https://learn.microsoft.com/en-us/windows/win32/shell/quickstart-sending-desktop-toast). Bản thử API toast độc lập ở lượt đánh giá trước không thay thế nghiệm thu bản tích hợp này.

## Gói ứng viên

`dist/Premiere-Voice-Sync-2.20.31-Panel.zip` — 466,05 MiB. Đã đối chiếu hash trực tiếp 62 file bên trong ZIP với manifest; thêm một file SHA256SUMS.txt. SHA256 ZIP: `5F5D212B679C4EDBBC8BA8DCBB717822ADAD53BDF00328530174854233308C32`.

Đối chiếu sau đóng gói: panel đang cài vẫn 2.20.30, 49/49 file khớp gói gốc, không file thừa. Không cài ứng viên hoặc đóng Premiere trong lượt này. Báo cáo kiểm tra ở `dist/_notification-integration-2.20.31/verified.json`; log hồi quy ở `dist/notification-2.20.31-tests.txt`.

Đã chạy lệnh quét Defender cho ZIP và thư mục gói, signature 1.461.31.0, không có phát hiện mới trong khoảng quét. Đây là bằng chứng của lần quét, không phải chứng nhận an toàn tuyệt đối.
