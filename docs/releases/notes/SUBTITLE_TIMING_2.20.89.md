# 2.20.89 — Caption giữ đúng mốc đã căn, không nới 5 frame

Bản đầu tiên của big update xây trực tiếp trên 2.20.x thay vì chạy song song
một hệ thống mới. Bản này chưa thêm luồng Beta mới trong panel; hai nút
**Dựng theo voice** và **Chỉ tạo subtitle** vẫn đi luồng hiện tại.

## Thay đổi người dùng thấy

- Caption giữ đúng mốc bắt đầu/kết thúc đã căn theo lời nói. Bản trước nới
  tối đa 5 frame ở mỗi mép khi còn chỗ; bản này không nới nữa (quyết định
  ngày 25/10). Áp dụng cho cả Dựng theo voice và Chỉ tạo subtitle.
- Hai caption kề nhau vẫn không chồng lên nhau: chồng lấn 1 frame do làm tròn
  vẫn được gỡ, chồng lấn lớn hơn vẫn bị từ chối như trước.
- Không đổi chữ, cách chia dòng, giới hạn ký tự, marker review, hình hay voice.

## Thay đổi bên trong

- Gia cố đường dẫn: đường dẫn mạng (UNC) hoặc thiết bị bị từ chối trước khi
  chạm tới đĩa; phần kiểm link dùng chung giữa panel và engine giờ đi từ gốc ổ
  xuống. Hành vi với đường dẫn cục bộ bình thường không đổi.
- Mã nghiên cứu cue-first (chưa bật trong panel) khóa Python dùng để đọc lại.

## Đã kiểm và còn chờ

- Bộ hồi quy 75 nhóm đạt; 6 nhóm Windows integration (cài đặt, rollback,
  registry, shortcut, thông báo) không chạy trong lượt này. Cả bộ cũng đạt khi
  TEMP là đường dẫn 8.3.
- **Chưa kiểm trên Premiere thật.** Caption sẽ hiện ngắn hơn bản trước khoảng
  5 frame mỗi mép; khoảng trống giữa hai caption sát nhau có thể dễ thấy hơn.
  Nếu thấy khó đọc, báo lại để chỉnh trong bản sau.
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài. Bản
  2.20.88 vẫn giữ trên GitHub để quay lại.
