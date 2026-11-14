# Marker phản ánh đúng phạm vi cần rà — 2.20.84

## Nguyên nhân

Lần chạy Alien 02 bằng 2.20.83 lúc 16:31–16:35 ngày 2026-10-21
ghi nhận 695 caption, 19 đoạn voice và 620 sequence review marker.
Job đã dọn sau khi hoàn tất; log còn lại chỉ chứng minh số lượng/thời gian.
Replay lưu trước đó tái hiện đúng 620 vị trí marker, không thay thế việc
đọc/nghe toàn bộ kết quả native mới.

Manual proxy cố ý có Confidence=0 và không cấp word timing để ngăn cắt
không đủ bằng chứng. Panel lại hiểu đây là độ tin cậy nhận diện thấp của
từng caption. Với 598 caption nằm trong 56 manual block, ba loại cảnh báo
DTW/low-confidence/manual bị trải lên từng caption: 1.816 issue thành
620 marker. Planner còn tạo 11 marker A2 từ confidence tổng hợp bằng 0.
Các số này không phải số lỗi ASR đã xác nhận.

## Sửa và bất biến

- Một marker timing cho mỗi manual block, dùng tọa độ caption cuối sau
  DTW/speed merge. Không nhân theo số caption chia nhỏ; không gọi confidence
  tổng hợp của proxy là lỗi nhận diện. Confidence=0 và quyền cắt giữ nguyên.
- Chữ ASR chưa khớp được đánh dấu riêng theo đúng cell hiển thị, gộp các
  caption chia từ cùng cell; phần đã có chữ SRT được chứng minh không nhận
  cảnh báo chữ này. Thiếu ánh xạ phải báo lỗi, không im lặng bỏ cảnh báo.
- Cell raw trùng đủ nguyên câu SRT có thể giữ chữ hoa/dấu câu của SRT khi
  timestamp từ trùng nhau chưa đủ bằng chứng. Chỉ một ứng viên trong khối,
  đủ toàn bộ chuỗi từ kể cả dấu tiếng Việt; không nhận câu chứa chữ số,
  thiếu đầu/đuôi, thừa lời, ứng viên lặp hoặc đã được giữ ở cell khác.
  Lưu RecognitionOriginalText; timing vẫn estimated, không thêm word timing,
  omission hoặc quyền cắt. Đây là sửa giữ chữ, không nâng model ASR.
- Marker A2 bỏ trường hợp duy nhất do manual proxy; low confidence thật và
  timestamp phục hồi độc lập vẫn được giữ. Completion tách số vùng timing
  với số câu SRT chưa khớp, không gọi toàn bộ là lỗi nhận diện.

## Phạm vi đã rà

Auto edit thường, DTW và speed merge dùng chung marker builder/planner;
executor trực tiếp và diagnostic nhận cùng plan. Caption-only dùng cùng
builder nhưng không có manual proxy; giữ các cảnh báo timing, ASR supplement
và vị trí caption cuối hiện có. Native lỗi frame/clip/retime, khoảng không
lời nguồn và cảnh báo tốc độ không bị tắt. Marker reconciliation giữ tag
và scope cũ: thay marker tự tạo dư khi chạy lại, giữ marker tay, workflow
khác và marker ngoài phạm vi; không tự thao tác project đang mở.

## Kết quả đo và giới hạn

Replay bốn entrypoint Alien, 166 cache hit/0 miss: vẫn 695 caption và
kế hoạch segment/frame hình/voice giống bản 83. Bốn cell nguyên câu SRT
6/49/54/286 được nhận lại; 280/319 câu giữ chữ SRT, 39 câu còn pending.
114 issue thành 111 marker dự kiến: 56 vùng timing, 36 vùng chữ ASR,
4 vùng caption DTW độc lập và 18 khoảng không lời; 11 marker A2 tổng hợp
thành 0. Không coi 39 câu pending hoặc 36 vùng chữ là lỗi đã nghe xác nhận.

[Marker regression](../../../tests/unit/review-markers.test.js) fail trên runtime
83, pass sau sửa; kiểm 400 caption chỉ có một vùng timing/một vùng chữ,
và thay 620 marker owned vẫn giữ marker tay/workflow khác/ngoài scope.
[Manual review](../../../tests/unit/Test-AutoEditManualReview.ps1) kiểm nguyên
câu, từ chối phục hồi thiếu/thừa/số/ambiguity, giữ raw, bảo toàn plan và
marker confidence thật. Full suite đạt 69 nhóm/146 PowerShell; các kiểm
gói/cài đặt được ghi trong [metadata](../2.20.84.json).

Không đổi model Small, ngưỡng nhận diện, omission, word timing hoặc điểm
cắt để giảm marker. Không gọi Premiere, Save/Undo hoặc xóa marker live.
Native marker/timing/playback acceptance vẫn pending-user-test.
