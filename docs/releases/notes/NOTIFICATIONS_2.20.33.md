# Thông báo 2.20.33 — áp dụng thống nhất theo tình huống

Phiên bản này xử lý ba điểm còn thiếu sau rà soát 2.20.32: phần hiển thị dùng đúng kết quả chọn kênh, tác vụ hoàn tất có cảnh báo được báo khi chạy nền, và toast chỉ mở một nơi xử lý. Không thay thuật toán nhận diện, dựng timeline, caption hoặc các bước xác minh sau sự cố.

## Hành vi thực tế

| Tình huống | Hiển thị và hành vi |
| --- | --- |
| SRT chưa chọn/không hợp lệ trong bước kiểm tra đầu vào | Báo tại trường SRT, viền lỗi và hướng dẫn cụ thể. Không thêm popup, toast hoặc yêu cầu focus Windows. |
| Số thiết lập hoặc ngôn ngữ không hợp lệ | Báo cạnh đúng trường. Mở vùng tùy chỉnh nếu đang thu gọn; khi panel đang có focus và tác vụ đã dừng, chuyển focus bàn phím tới trường cần sửa. |
| Lỗi đã xác định chưa thay đổi timeline | Banner lỗi không khóa panel; có giải thích, nhật ký và thao tác khắc phục phù hợp. Nếu tác vụ lỗi trong nền, áp dụng kênh chú ý theo tùy chọn người dùng. |
| Lỗi sau thay đổi/không rõ kết quả hoặc lỗi giao diện fatal | Hộp nổi bật trong panel; giữ khóa chạy mới đến khi xác minh sau khôi phục. Không khóa toàn Premiere, không tự Undo/Save/retry. |
| Cần quyết định | Hộp chọn có nút hành động cụ thể; chỉ thao tác chấp thuận rõ ràng mới tiếp tục. |
| Tiến độ hoặc lâu chưa có phản hồi | Trạng thái trong panel; không tự coi là lỗi hoặc chạy lại lệnh ghi. |
| Hoàn tất không cảnh báo, tác vụ ngắn | Kết quả trong panel, không lấy focus hay toast. |
| Hoàn tất tác vụ từ 30 giây khi chạy nền, có hoặc không có cảnh báo | Toast im lặng. Nội dung có cảnh báo không được trình bày thành thành công sạch. Không lấy focus. |
| Hoàn tất có cue/marker cần người nghe hoặc kiểm tra | Báo ở nền cả khi tác vụ ngắn; không lấy focus. GPU đã fallback an toàn hoặc cleanup phụ của tác vụ ngắn vẫn chỉ báo trong panel. |
| Bấm toast | Chỉ yêu cầu mở đúng panel/sự cố hiện tại. Không tự mở cửa sổ xem riêng. |
| Chọn Xem trong cửa sổ riêng | Mở cửa sổ modeless. Chọn Mở panel sẽ đóng cửa sổ xem trước rồi yêu cầu mở panel; đóng cửa sổ xem không chấp thuận hoặc giải quyết sự cố. |
| Xem lỗi đầu vào cũ từ lịch sử | Dùng banner giải thích không khóa, không ép chuyển chế độ hay focus tới trường cũ. |

Các kênh bên ngoài vẫn tuân thủ hai tùy chọn đưa app lên trước và toast Windows. Giữ kiểm tra phiên/lượt/sự cố, khử trùng, vô hiệu callback cũ, toast im lặng và tôn trọng cài đặt Windows. Việc kiểm tra khả năng toast được thực hiện lại khi gửi; không giữ mãi kết quả bị tắt từ đầu phiên.

## Kiểm chứng và giới hạn

Kiểm thử dữ liệu/mock bao gồm: lỗi SRT và tham số qua catch/finally thật của workflow; không vừa inline vừa popup; lỗi đã ghi/fatal dùng hộp nổi bật; lỗi chưa ghi dùng banner; cảnh báo hoàn tất dài/ngắn; fallback an toàn không làm ồn; toast chỉ yêu cầu mở panel; lịch sử lỗi trường không khóa. Schema C# và ràng buộc mã nguồn bảo đảm cửa sổ riêng chỉ được gọi từ lệnh review rõ ràng.

Kết quả: 34 nhóm hồi quy đạt, 98 file PowerShell phân tích cú pháp đạt; sáu nhóm tích hợp Windows được bỏ qua. Kiểm schema C# thuần đạt 56 assertions; policy dùng chung đạt 1.849 assertions. Sau sửa đường mở lịch sử khi có lỗi tại trường, các nhóm thông báo và UI contract đã chạy lại và đạt. Log: `dist/notification-2.20.33-no-windows-tests.txt`.

Chế độ chạy kiểm thử: `tests/Run-Tests.ps1 -NoWindowsIntegration`. Không mở cửa sổ mẫu, không tự gửi toast hoặc đổi focus, không điều khiển giao diện Windows/Premiere. Helper chỉ được biên dịch để đóng gói. Các nhóm tích hợp Windows bỏ qua không được tính là đã đạt.

Các mốc 30 giây cho kết quả dài và 120 giây cho trạng thái chưa phản hồi vẫn là lựa chọn ban đầu, chưa phải kết quả nghiên cứu người dùng. Banner/click/focus/DPI và thao tác Play/Save trong Premiere của phiên bản này vẫn cần người dùng nghiệm thu. Không gọi bản này là đã tối ưu tuyệt đối chỉ dựa vào kiểm thử tự động.

Người dùng chỉ cần mở Premiere và chạy như thường lệ sau khi cài xong; kiểm tra kết quả, Play/Save và báo nếu thông báo chưa phù hợp. Không yêu cầu người dùng tự chạy script, giải nén hoặc cấu hình kỹ thuật.

## Cài đặt đã xác minh

Đã cài 2.20.33 bằng dòng lệnh ngày 15/10/2026 khi Premiere đã đóng: 56/56 file khớp manifest, shortcut đúng AUMID/đích và helper đúng checksum. Giữ nguyên 599 file dữ liệu và 22 thư mục qua đối chiếu trước/sau. Gói ZIP đã đối chiếu 64 file payload và manifest; lần quét Defender của đúng gói cuối không ghi nhận phát hiện mới.

SHA256 ZIP: `0830F9DAC31C187B30C9B02F5E8F6882712C79CE55F9F5F5EE684C6F05F422DB`. Bằng chứng cài: `dist/_installation-2.20.33-20261015-152245/verified.json`. Gói 2.20.32 vẫn được giữ để khôi phục khi cần. Không mở/đóng Premiere hoặc điều khiển giao diện Windows trong lượt này; nghiệm thu native đang chờ người dùng.
