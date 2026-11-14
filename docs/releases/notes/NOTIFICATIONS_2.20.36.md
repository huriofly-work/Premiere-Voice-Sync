# 2.20.36 — kiểm tra lỗi xuất WAV trước khi tạo subtitle

Điều tra ngày 15/10/2026: hai log caption-only lúc 20:40:53 và 21:01:13 (UTC+7) đều thất bại tại audio-export, sau 127647 ms và 112279 ms. Không có bước caption-alignment. Preset cài trong Premiere Pro 2026 là Waveform Audio 48 kHz 16-bit, DoVideo=false, DoAudio=true. Bản panel cài hiện tại là 2.20.35; log cũ ghi nhầm toolVersion=2.20.30 vì hằng số chưa cập nhật.

Tool gọi `Sequence.exportAsMediaDirect` đồng bộ. [Mẫu CEP chính thức của Adobe](https://github.com/Adobe-CEP/Samples/blob/master/PProPanel/jsx/PPRO/Premiere.jsx) ghi rõ cách xuất này chặn tương tác Premiere cho tới khi render xong. Giao diện không phản hồi trong bước này không đủ để kết luận PC hỏng hoặc Whisper/GPU lỗi. Hai log hiện có không lưu lỗi native cụ thể, không đủ để xác định nguyên nhân Encoding đứng 0%.

## Sửa lỗi xác định được trong tool

- Trước đây bỏ qua giá trị trả về của exportAsMediaDirect và chỉ xét WAV tồn tại, dài hơn 44 byte. Nay chặn false, số âm và chuỗi lỗi/hủy rõ ràng, kể cả còn file WAV dở dang. Chi tiết native được trả về panel; không tiếp tục nhận diện/import.
- Xác minh toàn bộ phạm vi có giá trị hữu hạn trước khi đổi mute, kiểm tra Premiere nhận đúng In/Out (dung sai một frame) trước khi encoding; dùng workAreaType=1 rõ ràng.
- Giữ khôi phục mute/In/Out trong finally, kể cả khi native trả lỗi thay vì ném exception.
- Log đúng 2.20.36 và lưu exportFailurePhase theo danh sách cố định. Không ghi chuỗi lỗi gốc, tên media hoặc lời nói vào log tự động.
- Trạng thái panel nói rõ Premiere đang xuất WAV và có thể hủy trong bảng Encoding. Không đặt timeout giả vì timeout JavaScript không hủy được export native; cleanup/khôi phục sớm có thể chạy đua với encoder.

## Giới hạn và kiểm chứng còn cần

Đây là bản sửa kiểm tra lỗi và bổ sung chẩn đoán, **chưa phải bằng chứng đã sửa được kẹt Encoding 0%**. Không đổi preset/renderer/driver/cache; không tự đóng Premiere hoặc lưu Project. Cần xuất thủ công WAV cùng vùng/track, cùng preset để so sánh. Nếu thủ công thành công còn tool kẹt, tiếp tục kiểm chứng tương tác mute/In/Out và native scripting; nếu cả hai kẹt, điều tra audio graph/media/effect của Premiere. Không tự chuyển sang FFmpeg đọc media nguồn vì có thể mất speed, routing, nested sequence và hiệu ứng đang nghe trên timeline.

Kiểm native: xuất thành công, hủy khi 0%, lỗi trả về có WAV dở, nhiều vùng chọn, track voice ban đầu mute, routing/hiệu ứng/Solo, khôi phục In/Out, Caption/Play/Save. Kiểm mô phỏng không thay nghiệm thu Premiere thật. Chưa cài bản này vào panel đang chạy.

Kiểm tự động: `tests/Run-Tests.ps1 -NoWindowsIntegration` đạt 35 nhóm, parse 99 script; sáu nhóm tích hợp Windows được bỏ qua. Lần chạy sandbox đầu bị hạn chế ghi cache fixture; chạy lại ngoài sandbox đạt. Sau khi thêm ca UI lỗi export, test UI chạy lại đạt và xác minh engine/import không được gọi. JS syntax, repository/version và generator parity đạt. Đây không phải kiểm native encoding.
