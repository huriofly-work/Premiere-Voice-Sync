# 2.20.94 — Marker gọn hơn: không chồng, dạng điểm, gộp theo loại

Prerelease. **Chưa nghiệm thu trên Premiere**; 2.20.91 vẫn là stable/Latest.

Lượt chạy 2.20.93 trên project thật (Sông Congo, 18/11/2026) dựng timeline trong 64,5 giây
(2.20.92: 85,5 giây), nhưng lộ ra lỗi marker: mỗi lần chạy trên sequence mới, file voice
có thêm một bộ marker review (15 → 37 → 59 marker). Marker dạng đoạn cũng che sóng âm khi
dựng. Bản này sửa marker theo các quyết định của user ngày 18/11.

## Thay đổi người dùng thấy

- **Marker review không chồng qua các lần chạy** (#58). Chạy lại Auto edit hoặc Tạo phụ đề
  trên cùng file voice sẽ thay bộ marker review cũ của cùng chức năng, kể cả khi dùng sequence
  mới. Marker Auto edit và Tạo phụ đề được giữ riêng. Marker bạn tự đặt không bị đụng. Lần chạy
  đầu tiên với bản này sẽ dọn các bộ marker đang trùng.
- **Marker là điểm ở giữa đoạn cảnh báo** (#59). Không còn marker kéo dài che sóng âm. Nếu
  điểm giữa đã có marker, marker được đặt ở frame trống gần nhất trong đoạn. Marker dạng đoạn
  của bản cũ được đổi thành dạng điểm ở lần chạy tới.
- **Mỗi đoạn một marker cho mỗi loại** (#62). Marker cảnh báo voice nằm giữa đoạn voice;
  marker cảnh báo SRT nằm giữa đoạn cue. Cảnh báo cùng loại chồng hoặc chạm nhau trên cùng clip
  được gộp vào một marker. Hai loại khác nhau trùng chỗ thì đặt sát bên nhau.
- **Không còn marker dự phòng trên thước timeline** (#63). Mọi marker gắn lên clip. Tạo phụ đề
  ở chế độ trộn hoặc nhiều track gắn vào track đầu tiên (từ A1) đang bật tiếng có clip phủ đoạn
  cảnh báo. Cảnh báo không gắn được clip được liệt kê trong nhật ký panel kèm lý do và đếm trong
  thông báo cuối. Lần chạy tới dọn marker dự phòng cũ của tool trên thước.

## Đã kiểm và còn chờ

- Bộ hồi quy `-NoWindowsIntegration` đạt 73 nhóm; 6 nhóm Windows integration không chạy.
- Mỗi thay đổi có test tái hiện chạy đỏ trên code trước đó và xanh sau khi sửa. Lệnh sửa
  timeline giữ nguyên trên 42 fixture ở cả bốn chế độ chạy; ghi marker trước khi cắt, chạy lại
  không ghi thêm, khôi phục marker khi lỗi hoặc Dừng vẫn đạt.
- **Chưa chạy trên Premiere thật**: chưa xem marker dạng điểm hiển thị trên clip, chưa xác nhận
  marker mới tạo đã có In = Out, chưa đo thời gian ghi marker, chưa thử Tạo phụ đề chế độ trộn.
- Ở lần chạy đầu sau khi cập nhật, marker căn voice có thể lệch một frame nếu marker review cũ
  nằm đúng chỗ giữa; lần chạy sau tự về đúng chỗ.
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài.
