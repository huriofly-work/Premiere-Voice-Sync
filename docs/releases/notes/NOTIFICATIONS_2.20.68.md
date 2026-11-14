# Thông báo hoàn tất 2.20.68

Dựng theo voice và Tạo phụ đề gửi một thông báo Windows khi hoàn tất trong
nền, kể cả thành công bình thường hoặc tác vụ chạy nhanh. Bấm thông báo để
mở panel xem kết quả. Khi đang xem panel, kết quả hiện trực tiếp trong panel.
Không cần xác nhận đã đọc và không tự chuyển focus khi hoàn tất.

Thông báo Windows mặc định bật, không phát âm thanh; giữ lựa chọn đã lưu.
Chế độ Không làm phiền và quyền thông báo Windows vẫn được tôn trọng.
Các cập nhật tiến độ, fallback đã phục hồi, thao tác thiết lập và nhật ký
kỹ thuật không tạo thêm thông báo hoàn tất.

Thay chính sách định tuyến chung và nhãn thiết lập, không thay native helper,
engine, host, dữ liệu người dùng hoặc kết quả dựng/phụ đề của 2.20.67.

Kiểm tự động bao phủ cả hai luồng, tác vụ ngắn/dài, foreground/background,
opt-out, Không làm phiền, quyền toast không khả dụng, gửi trùng và click cũ.
Hiển thị banner/click trên Windows và quay lại panel trong Premiere cần
người dùng nghiệm thu thực tế; mock và kiểm gói không thay thế bước này.

53 nhóm hồi quy đạt, parse 123 script PowerShell; runner bỏ qua sáu nhóm
tích hợp Windows. Chính sách thông báo đạt 1.855 kiểm tra. Log và bằng chứng
ở `.tmp-completion-2.20.68/`. Kết quả kiểm gói/cài đặt được ghi bổ sung sau build.

## Gói và cài đặt đã xác minh

70 tệp payload/71 mục ZIP khớp checksum và nguồn; 20 bộ VM chạy mã trong
gói đạt. 48 tệp engine/host khớp 2.20.67. ZIP SHA256:
`F93EFA44B7A69B47D7F0BE775ED52F4EE78AB9EE50B25932FD1F5D3D26A0DE2B`.

Đã cài từ 2.20.67 lúc 23:17 ngày 17/10/2026 (UTC+7), khi Premiere/helper
đã đóng. 62/62 tệp panel khớp gói; giữ nguyên hash 3.952 tệp dữ liệu/22
thư mục và registry CEP. Không mở helper hoặc thao tác project. Bằng chứng
và bản sao panel trước tại `dist/_installation-2.20.68-20261017T161720Z/`.
Phần bằng chứng được bổ sung sau build, không thay gói ZIP đã kiểm.
Hiển thị/click thông báo trong điều kiện dùng Premiere thực tế vẫn chờ
người dùng kiểm tra khi chạy tác vụ kế tiếp.
