# Nhận diện khó chuyển sang review và tiếp tục — 2.20.83

## Quyết định và hành vi

Người dùng yêu cầu ngày 2026-10-21: chương trình không được hủy tác vụ chỉ
vì một lỗi nhận diện mà model hiện tại chưa giải quyết được. Đây là thay
đổi chính sách đã được yêu cầu trực tiếp, thay trạng thái pending của 82.

Auto edit vẫn thử recovery/resolver có chốt cũ. Một vùng đã có phạm vi
nguồn/voice được chứng minh nhưng chưa nhận đúng lời được giữ đủ thành
khối review, kể cả dài hơn 30 giây/40 cue/800 từ. Không chia điểm cắt bên trong
khối, không bỏ hình/voice, không nâng timestamp ước lượng thành DTW.
Giới hạn của retry và đường tự chia chắc chắn không đổi; đường bảo toàn
không giả rằng model đã khớp cả đoạn. Planner giữ cả mép vật lý của mỗi
chapter trong job có manual block, không xén mép theo ASR/DTW chưa chắc.

Không có neo hoặc không gán được chapter thì trả preserveTimeline và các
vùng cần xử lý thủ công; panel hoàn tất phân tích với cảnh báo, không gọi
planner/executor. Không báo đã dựng xong hoặc tạo caption khi chưa làm.

## Các luồng đã rà/sửa

| Luồng | Kết quả |
|---|---|
| Auto edit thường/DTW/gộp hình | Dùng chung alignment: giữ khối khó, tiếp tục phần khác; global preservation không chạy executor |
| Resolver omission/caption recovery | Chốt giữ nguyên; khối review không có editedSourceMap hoặc omission authority |
| Planner/DTW/speed/marker | Giữ cả frame voice mép chapter và hình nguồn; metadata review/cell chữ giữ qua biến đổi; marker theo caption cuối |
| Caption-only primary/retry/supplement | Retry mép không đạt giữ bản sao primary, metadata rejected chỉ phần chưa được caption phủ; không bịa chữ thiếu |
| Caption-only không có kết quả dùng được | Hoàn tất có cảnh báo và vị trí, không import caption giả/rỗng |
| CPU/CUDA/cache/cancel/IO | Không đổi recipe/model/cache; chỉ allowlist lỗi chất lượng nhận diện thành review, lỗi runtime/IO/cancel vẫn truyền đúng |

## Bằng chứng thực tế và giới hạn

Alien 319 cue/3 voice qua alignment → planner → DTW trial → speed merge:
695 caption cuối,276 cue giữ nguyên chữ SRT qua các cell/split,43 cue pending;
56 khối review,4 khối dài được giữ cả khối. Mọi cell caption bảo toàn chữ;
toàn bộ frame hình và voice được giữ, không omission mới, không điểm cắt
DTW bổ sung.56/43/4 là metadata review, không phải số lỗi đã nghe xác nhận.
SRT/3MP3 nguồn giữ hash; project đã được người dùng lưu lại sau snapshot82,
nên geometry replay là metadata lịch sử, không phải timeline đang mở.
Không gọi host Premiere, Save hoặc Undo trong replay.

[Partition](../../../tests/unit/Test-AutoEditPartition.ps1) kiểm khối dài không
hủy job, raw text/SRT đã chứng minh được giữ, planner thật/speed conservation,
mép chapter không mất frame; giữ ca guard strict cũ.
[Recognition policy](../../../tests/unit/Test-AutoEditRecognitionPolicy.ps1)
chạy catch/writer thật của hai entrypoint: model-quality→review, tail giữ
primary, IO/runtime/cancel không bị nuốt, không tạo kết quả caption giả.
[Panel](../../../tests/unit/default-edit-ui.test.js) và
[caption panel](../../../tests/unit/workflow-notice-ui.test.js) kiểm hoàn tất warning,
vị trí review, không gọi native edit/import khi cần bảo toàn toàn bộ timeline.

Đạt 69 nhóm hồi quy, parse 146 PowerShell; kiểm 73 payload/74 ZIP entry
khớp nguồn và 20 bộ Node chạy runtime trong gói. Ca ASR rỗng cũng hoàn tất
phân tích có review trước khi vào mapper yêu cầu words khác rỗng.
Cài 65 file runtime, giữ nguyên 6.260 file dữ liệu/22 thư mục và registry CEP;
không gọi Premiere, Save/Undo hoặc khởi chạy helper. Chi tiết hash trong
[metadata phát hành](../2.20.83.json). Chưa có native Premiere
import/retime/playback/timing/marker/Save acceptance cho 83.
Raw ASR trong43 cue pending có thể sai; cần sửa tay, không hứa tự phát hiện
mọi lỗi. Whisper Small vẫn là model production; không tự merge/stable.
