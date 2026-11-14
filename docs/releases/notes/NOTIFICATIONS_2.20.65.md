# Premiere Voice Sync 2.20.65 — thông báo và giao diện gọn hơn

## Thay đổi

- Luồng chính: **Chọn nguồn → Tùy chọn → Chạy và xem kết quả**. CPU/GPU, lịch sử cảnh báo và hỗ trợ nằm trong phần phụ thu gọn. Tên SRT hiện ngắn gọn; đường dẫn đầy đủ nằm ở tooltip.
- Kết quả và lỗi nằm ngay dưới nút chạy. Chỉ quyết định cần phê duyệt mới dùng hộp thoại che panel: dựng trực tiếp timeline, xóa cache hoặc xác minh thủ công sau sự cố. Không thêm xác nhận cho tác vụ tạo phụ đề bình thường.
- Nhật ký `warn`, fallback CPU đã xử lý và cleanup đơn thuần không tự biến thành cảnh báo người dùng. Khôi phục mặc định, chẩn đoán thành công, xuất log và xóa cache thành công chỉ phản hồi cạnh thao tác, không thêm cảnh báo chưa xem.
- Hoàn tất bình thường không gửi thông báo Windows, kể cả tác vụ lâu. Tác vụ nền chỉ nhắc khi lỗi, cần quyết định hoặc có kết quả cần xem lại. Người mới mặc định không bị chuyển focus; giữ nguyên lựa chọn focus đã lưu.
- Kết quả cần kiểm tra có nút **Xem vị trí cần kiểm tra**. Danh sách giữ timecode đầu ra, phụ đề nếu đã có định danh và lý do; gộp lý do cùng phạm vi, đếm vùng chồng nhau một lần. Không cộng marker xanh dương thông tin vào cảnh báo chất lượng. Khi thiếu marker, vẫn giữ danh sách và nói rõ trong nội dung chính.
- Thông báo mặc định ngắn gọn, tối đa hai nút hành động; lỗi thô và số liệu thuật toán nằm trong **Chi tiết → Thông tin kỹ thuật**. Trường hợp không giữ được chữ SRT hoặc không ghi được trạng thái phục hồi vẫn được nêu rõ ở nội dung chính.

## Các chốt được giữ

Đóng thông báo, xem lịch sử và bấm toast không phê duyệt hoặc cho chạy lại sau lỗi. Giữ kiểm timeline/sequence, trạng thái chưa xác minh, Caption Track API không khả dụng, khôi phục audio/In/Out, dừng và tạm dừng tại điểm an toàn. Không tự Save, Undo hay đóng Premiere. Không đổi thuật toán nhận diện, căn thời gian hoặc vòng đời marker.

## Kiểm chứng

52 nhóm hồi quy đạt, parse 122 script PowerShell; runner bỏ qua sáu nhóm tích hợp Windows. Có kiểm model/renderer bằng VM và kiểm bố cục trình duyệt với dữ liệu mô phỏng cho hai chế độ ở 320/385/560 px, phần chi tiết dài ở chiều cao 520 px. Bộ kiểm mới bao phủ im lặng cho fallback/cleanup/thành công lâu, lựa chọn focus, lịch sử, gộp vùng đầu ra, thiếu marker, marker xanh thông tin, lỗi thô và khóa phục hồi. Log `suite-verified.log`, `preview-final.log` và ảnh nằm trong `.tmp-notice-2.20.65/`. Kết quả kiểm gói và cài đặt được ghi riêng sau khi hoàn tất.

Đây chưa phải nghiệm thu native Premiere. Sau cài, mở lại panel và xác nhận 2.20.65; chạy dựng/tạo phụ đề trên project sao lưu, kiểm vùng cần xem lại, thông báo khi panel ẩn, Play/Preview và tự Save khi kết quả phù hợp. Kiểm Windows DND/nhấp toast còn cần thực hiện trong điều kiện sử dụng thật. Bản cài không sửa caption hoặc marker của các lần chạy trước.

## Gói và cài đặt đã xác minh

Gói có 70 tệp payload/71 mục ZIP, khớp checksum và mã nguồn. 19 bộ kiểm VM chạy trên mã trong gói đạt. Toàn bộ 48 tệp engine/host khớp 2.20.64, xác nhận đợt này không sửa thuật toán hoặc mã thao tác timeline. Bằng chứng: `.tmp-notice-2.20.65/package-verified.json` và `package-tests.log`.

ZIP SHA256: `75F4DFE9E706AFEC1975D5FDEBF164418ABDD4B4C12477A7173F283C95BFA25C`.

Đã cài từ 2.20.64 lúc 17:45 ngày 17/10/2026 (UTC+7), khi Premiere/helper đã đóng: 62/62 tệp panel khớp gói, giữ nguyên hash 3.640 tệp dữ liệu/22 thư mục và registry CEP. Không mở helper hay thao tác project. Bản sao panel trước và bằng chứng nằm tại `dist/_installation-2.20.65-20261017T104541Z/previous-panel` và `verified.json`. Phần bằng chứng này được bổ sung sau build; gói ZIP đã kiểm được giữ nguyên. Nghiệm thu native vẫn chờ người dùng.
