# 2.20.90 — Nhận diện bằng Whisper large-v3-turbo

Model nhận diện đổi từ Whisper Small sang **Whisper large-v3-turbo**, dùng cho
cả **Dựng theo voice** lẫn **Chỉ tạo subtitle**. Đây là model duy nhất trong
gói; không còn Small và không tự đổi model giữa chừng.

## Thay đổi người dùng thấy

- Nhận chữ tiếng Việt chính xác hơn. Trên bộ mẫu nghiên cứu, lỗi chữ sau chuẩn
  hóa số giảm từ 8,93% (Small) xuống 3,48% (Turbo).
- File ZIP lớn hơn: khoảng 1,6 GB thay vì khoảng 490 MB, vì model lớn hơn.
- **Chạy bằng CPU chậm hơn khoảng 2 lần so với Small.** Đây là chế độ mặc định
  trên máy chưa bật tải GPU, và trên máy AMD/Intel. Máy NVIDIA nên bật
  **Cho phép tải backend GPU từ GitHub** để chạy CUDA.
- Lần đầu chạy sau khi cập nhật, panel kiểm lại GPU với model mới thay vì dùng
  kết quả kiểm cũ của Small.

## Đã kiểm

- Replay toàn engine ngoại tuyến trên audio Nam Cực dựng lại (766,5 giây, SRT
  255 câu, CUDA), kiểm caption cuối bằng `tools/Verify-CaptionReplay.py`:
  Turbo giữ 254/255 câu SRT, 0 vùng timing ước lượng, đoạn outro sai 3/77 từ
  (Small cùng engine: 255/255, 2 vùng ước lượng, 7/77).
- Bộ hồi quy đạt với `-NoWindowsIntegration`; 6 nhóm Windows integration
  (cài đặt, rollback, registry, shortcut, thông báo) không chạy.
- Khóa runtime chỉ chấp nhận đúng file Turbo đã pin hash
  (`1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69`).

## Còn mở

- **Chưa kiểm trên Premiere thật**: import, phát, timing caption, marker, thời
  gian chạy và bộ nhớ GPU khi chạy cùng Premiere.
- Cue 138 của project Nam Cực ("nước hồ giàu sắt"): Turbo nghe thành "dầu sắc",
  không đủ ngưỡng giữ chữ SRT nên caption hiện chữ nhận diện và câu được đánh
  dấu để sửa tay. Small giữ được câu này.
- Chưa đo các ngôn ngữ ngoài tiếng Việt.
- File Small cũ trong `%LOCALAPPDATA%\PremiereVoiceSync\Models` không bị xóa
  khi cập nhật; có thể xóa tay nếu cần chỗ trống.
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài. Bản
  2.20.89 vẫn giữ trên GitHub để quay lại.
