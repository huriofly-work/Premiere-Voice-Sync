# Bản chờ kiểm thử 2.20.35 — chỉ nhận diện track voice

Chỉ tạo subtitle có thêm **Track voice cần nhận diện**. Mặc định A2; nếu chỉ một track audio thì dùng A1. Người dùng chọn track khác theo project. Lựa chọn giữ trong cùng sequence; đổi sequence đặt lại mặc định, track đã xóa không tự thay bằng track khác. Chọn clip vẫn chỉ xác định phạm vi thời gian.

Khi xuất WAV, host đọc và lưu mute của mọi track audio trước khi thay đổi. Tool tạm mute các track khác, bật track voice, xác minh lại trước/sau từng lần xuất. Khối finally cố khôi phục mọi track và cả In/Out độc lập, nên lỗi một track không bỏ qua những phần còn lại. Nếu khôi phục hoặc cô lập không xác minh được, tool dừng trước ASR/import, giữ lỗi xuất gốc cùng chi tiết khôi phục và yêu cầu kiểm tra trạng thái. Không bảo đảm khôi phục nếu Premiere/tiến trình bị tắt đột ngột; không sửa timeline trong lúc chạy.

Chỉ tách theo track, không tách nhạc/giọng khác đã trộn trong cùng file hoặc cùng track. Nested sequence và hiệu ứng của track voice vẫn thuộc audio xuất. Cần kiểm routing/submix, hiệu ứng và Solo thực tế trong Premiere để xác nhận nội dung WAV. Tool không thay nút Solo.

API mute dùng `isMuted()` và `setMute(0/1)` theo [mẫu tham chiếu CEP của Adobe](https://github.com/Adobe-CEP/Samples/blob/master/TypeScript/PProPanel-vscode/payloads/api_doc.html). Không dựa vào giá trị trả về setMute để khẳng định thành công; đọc lại trạng thái sau thao tác.

Kế thừa sửa captionTracks và thông báo của 2.20.34; xem [ghi chú trước](NOTIFICATIONS_2.20.34.md). Không thay engine căn lời, SRT, điểm cắt/speed hoặc thân executor dựng. File diagnostic được sinh lại để cập nhật hash host.

Nghiệm thu native cần: đặt nhạc A1/A3 và voice A2; kiểm WAV/caption chỉ có voice; thử voice ban đầu mute; thử A1/A3 làm voice; các trạng thái mute hỗn hợp; lỗi xuất; nhiều vùng chọn; nested/routing/hiệu ứng/Solo; nghe lại, Play và Save. Kiểm tự động/mô phỏng không thay thế nghiệm thu này. Chưa cài thay panel đang dùng.

Kiểm cục bộ ngày 15/10/2026: `Run-Tests.ps1 -NoWindowsIntegration` đạt 35 nhóm, parse 99 script PowerShell; sáu nhóm tích hợp installer/registry/helper Windows được bỏ qua theo chế độ này. Sau gia cố khôi phục khi đọc mute lỗi và đồng bộ số phiên bản hiển thị, chạy lại host/UI caption, parity executor, JS syntax và repository/version đều đạt. Browser fixture đạt 320/385/560 px ở cả hai chế độ, không tràn ngang; ảnh được xem lại. Các bước này không gọi Premiere hoặc nhận diện media thật.
