# Nối nhiều SRT để nhận diện chung

Ngày 17/10/2026. Người dùng yêu cầu đơn giản hóa: nối các SRT thành một SRT rồi nhận diện chung. Phương án bảng ghép từng cặp SRT–voice đã được thay thế; phần mã thử tương ứng đã bỏ.

- Chọn nhiều SRT ngoài hoặc thêm từng SRT trong Project; dùng Lên/Xuống để sắp thứ tự, Bỏ để xóa khỏi danh sách.
- Giữ chữ, đánh lại số cue; giữ timestamp gốc hoặc cộng nối thời gian theo lựa chọn. Mốc sau nối cần khớp hình nguồn nếu dùng Dựng theo voice.
- Tạo một SRT tạm trong job, truyền một targetSrtPath vào engine hiện có, áp dụng cả hai chế độ. File gốc giữ nguyên; file tạm được dọn cùng job.
- Bản mới: 2.20.54. Cách dùng và kiểm chứng tại SRT_JOIN_2.20.54.md.