# 2.20.47 — marker tại các mốc cần kiểm tra

Trước bản này, Auto edit chỉ gắn marker clip cho tốc độ, gộp hình và một số trường hợp căn voice. Cảnh báo đọc số, DTW, timing ước lượng, xung đột caption và các vùng SRT cần kiểm tra chủ yếu nằm trong nhật ký. Chỉ tạo subtitle chưa có bước gắn marker.

Bản này dùng chung marker sequence tên `VOICE SYNC - Can kiem tra` cho Auto edit, dựng chẩn đoán baseline/fast/no-delay và Chỉ tạo subtitle. Màu vàng chỉ mốc cần nghe/xem lại; màu đỏ chỉ lỗi hậu kiểm có vị trí xác định. Mỗi ghi chú chứa lý do, cue khi có và khoảng thời gian đầu ra. Nhiều lý do cùng frame được gộp trong ghi chú.

- Đọc số chưa xác minh; DTW chưa xác minh; timing ước lượng; xung đột căn voice/caption; độ tin cậy thấp; timestamp đã phục hồi/nội suy.
- Chữ SRT khác nhận diện; lời nói bổ sung ngoài SRT; vùng nhận diện dự phòng; vùng chưa tìm được lời nói; mép caption đã điều chỉnh do chồng nhau.
- Hậu kiểm xác định được vị trí sai V1/A1/A2, mất link, khe hở hình, đuôi hình/audio sai, speed không hội tụ hoặc API không đọc được speed.
- Lỗi native cắt/retime/di chuyển có vị trí được chụp trước thao tác: marker đỏ tại vùng thao tác trên timeline đang dựng dở, kèm lỗi và yêu cầu kiểm tra trước khi chạy lại. Chỉ tạo khi vẫn đúng active sequence; không đoán vị trí từ lỗi toàn cục hoặc yêu cầu dừng của người dùng.

Auto edit ánh xạ cue qua caption cuối cùng và giao các vùng audio với từng đoạn voice giữ lại để quy đổi sang timeline mới, kể cả sau DTW/gộp hình. Chỉ tạo subtitle dùng thời gian sequence từ các vùng xuất audio. Cue từ nhiều vùng rời nhau được đánh số duy nhất trước bước kiểm timing.

Marker clip tốc độ/gộp hình vẫn được giữ. Marker sequence chỉ được cập nhật/dọn khi có đúng tên và dấu sở hữu của workflow, nằm trong phạm vi đang xử lý. Marker người dùng, marker của workflow khác và marker ngoài vùng được giữ. Nếu frame đã có marker người dùng, tìm frame trống trong chính khoảng cảnh báo; hết chỗ thì báo lỗi. Khi thay thế không đầy đủ, giữ cảnh báo cũ. Không tạo được marker là lỗi cần chú ý, không báo tác vụ thành công; vẫn giữ trạng thái caption đã thêm để tránh chạy lại nhầm. Lỗi riêng màu được báo, không làm mất vị trí/ghi chú.

Lỗi đầu vào, GPU đã chuyển CPU thành công và sự cố không xác định được vị trí không được gán một mốc đoán trên timeline; vẫn có thông báo/nhật ký. Chẩn đoán đầu vào chỉ đọc sequence, không tạo marker.

## Kiểm chứng

Kiểm tự động gồm quy đổi thời gian sau dựng, cue tách nhiều caption, vùng voice rời nhau, phân quyền marker theo workflow/phạm vi, nhiều lý do cùng frame, chạy lại, va chạm marker người dùng và lỗi API/vị trí/màu. Mock host kiểm marker trong Chỉ tạo subtitle, executor trực tiếp và cả ba profile chia đợt, đồng thời giữ hành vi `captionCreated` khi marker thất bại.

Ngày 16/10/2026: `Run-Tests.ps1 -NoWindowsIntegration` đạt 43 nhóm, parse 112 script PowerShell; sáu nhóm tích hợp Windows được bỏ qua theo runner. Fixture bảo mật tạo junction được chạy ngoài sandbox, TEMP/TMP nằm trong workspace. Log `.tmp-marker-review/verified-suite.log`. Kiểm riêng executor trực tiếp/chia đợt, lỗi native, marker và pause/cancel cũng đạt sau các sửa cuối; generator khớp nguồn host. Trên dữ liệu phân tích có sẵn gồm 615 cue, kế hoạch cơ sở, DTW và gộp hình đều quy đổi thành 86 mục cần kiểm tra nằm trong timeline đầu ra; không chạy nhận diện lại hoặc sửa media/SRT nguồn.

Các kiểm mô phỏng không xác nhận marker hiển thị, màu, Preview/Play, Undo hoặc Save trong Premiere thật. Cần kiểm trên project thử trước khi nghiệm thu. Không tự điều khiển hay lưu project Premiere.
