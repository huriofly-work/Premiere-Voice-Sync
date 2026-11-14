# Auto edit: tự giải quyết timing trước khi yêu cầu sửa tay

Log chạy bản2.20.84 trên Alien vẫn có19 nhóm voice cho319 câu SRT và695
caption. Bản84 chỉ sửa cách tạo marker; hình vẫn retime theo các khối dài.
Resolver tạo56 proxy từ recognition ban đầu, gắn confidence0/không word
timing để bảo toàn. Planner cấm cắt cả proxy, trong khi bước caption đã có
luồng DTW đầy đủ4510 từ nhưng loại các từ nằm trong proxy khỏi overlay.

## Thay đổi và bất biến

`AutoEditAcousticPartitions.ps1` tìm ngữ cảnh bốn từ cuối/trước ranh giới và
bốn từ đầu/sau ranh giới. Cả hai phải duy nhất trong toàn bộ reference và
raw DTW, liền nhau, cùng chapter; tám timing hữu hạn, dương, đúng thứ tự,
quality DTW. Chỉ cắt trên frame grid, trong một khoảng lặng đã đo, giữ
silence tối thiểu/safety margin hiện có. Không dùng cue confidence tổng hợp,
chữ proxy hoặc timestamp ước lượng làm quyền cắt. Clip có inPoint khác0
không nhận quyền mới này; vẫn dùng đường bảo toàn cũ.

Planner tính lại proof từ raw stream và silence hiện tại, chia picture/voice
độc lập với ownership caption. Mỗi cell chỉ xuất một lần rồi đi qua voice
map hoàn chỉnh, kể cả khi nằm qua nhiều nhóm hình hoặc có gap chèn thêm.
Giữ mọi frame nguồn và mọi frame voice, không thêm omission. Hậu kiểm kiểm
reference/source/frame/chapter coverage và từng mốc cắt. Optional additive
DTW bảo vệ metadata; speed merge chỉ được gộp nếu giữ mốc đồng bộ trong
một frame. Hai host direct/diagnostic dùng cùng plan, không đổi Save/Undo.

Caption trong proxy được căn lại trên raw DTW, giữ nguyên chữ. Cần đủ word
timing, ít nhất85% exact, hai mép exact và mọi kiểm physical timing hiện có.
Phần chưa đạt được nhận diện lại trong cửa sổ cục bộ tối đa30 giây; không
đổi model hay hạ ngưỡng. Chỉ nhận lại khi qua cùng guard, từ chối proposal
xung đột với hàng xóm; giữ các cell tốt khác. Timing retry không tự cấp
quyền cắt hình hoặc phục hồi/bỏ chữ SRT.
Ngay cả khi không có khoảng lặng để cắt hình, capability caption độc lập
vẫn cho dùng timing đã xác minh, giữ nguyên khối hình/voice. Fixture riêng
kiểm trường hợp một nhóm hình nhưng mọi cell được căn DTW tự động.
Kết quả retry thiếu bằng chứng nằm
trong log; marker theo cell cuối, không nhân cảnh báo từ lần thử đã thất bại.
IO/runtime/cancel vẫn truyền lỗi thật. Caption-only và omission resolver giữ
điều kiện cũ.

## Đo tự động trên Alien

Replay bốn shipping stage với ba MP3/SRT thật và geometry lưu lịch sử,
không đọc hoặc sửa timeline đang mở:

| Chỉ số | 2.20.84 | 2.20.85 |
|---|---:|---:|
| Nhóm dựng hình/voice |19|158|
| Ranh giới độc lập xác minh mới |0|155|
| Cell trong proxy có timing DTW |0/268|231/268|
| Caption cuối |695|695|
| Khối còn một phần timing ước lượng |56|17|
| Marker vị trí dự kiến |111|74|

60 cửa sổ retry tự động phục hồi thêm31 cell so với200 cell đã căn từ luồng
DTW đầy đủ.37 cell còn ước lượng thành25 vùng timing; vẫn giữ36 vùng chữ
ASR chưa khớp,4 cảnh báo DTW ngoài proxy và14 gap nguồn chưa tách.79 issue
gộp theo vị trí thành74 marker dự kiến; marker tốc độ V1 riêng vẫn còn11.
39 câu SRT pending/36 vùng ASR là metadata cần rà, chưa phải lỗi nghe xác
nhận. Giữ280/319 câu SRT đã có bằng chứng, toàn bộ chữ đầu ra bản84 và
kiểm ownership4503 từ ở giai đoạn recognition ban đầu; không thay project/SRT/MP3 nguồn.

Kiểm tham khảo11 cue nội bộ không dùng làm ngữ cảnh của155 mốc cắt: độ lệch
giữa tâm cue SRT chiếu theo V1 và tâm speech DTW giảm median1,884→0,454s,
p954,093→1,018s, max7,167→1,152s. Một cue tăng0,205→0,454s. Đây là proxy
từ cùng dữ liệu/model, không phải gold độc lập hoặc nghiệm thu nghe hình;
không khẳng định mọi cảnh đã đồng bộ chính xác từ số đo này.

## Phạm vi kiểm tra và phần còn mở

70 nhóm hồi quy/148 PowerShell, gồm fixture trước/sau, estimated/extra/mơ
hồ/overlap/chapter/trim/fps, cục bộ retry/fatal, đủ chữ/frame và tamper;
speed merge không hủy sync anchor; marker chỉ cảnh báo phần chưa phục hồi.
Island chuẩn giữ30/30 cue/66 caption, gap125frame và sparse timing không
được nâng DTW. Fixture cố ý SRT103 vẫn giữ raw102,5 khối/65 caption,
20 cell được căn DTW; không phục hồi câu103 sai. Ca lịch sử27 và199 vẫn đạt.
Allowlist build/security/install có module mới, gói và source được đối hash;
chi tiết gói/cài trong [metadata](../2.20.85.json).

Native Premiere import/playback/retime/voice/caption/marker acceptance vẫn
pending. Không điều khiển Premiere, Save/Undo, dọn marker live, đóng ứng
dụng/helper, merge PR hoặc promote stable. Quyền phân hoạch không biến các
đoạn lời khó còn lại thành đã đúng; người dùng chỉ cần chú ý các vị trí còn
cảnh báo khi thấy cần sửa, không phải rà lại toàn bộ bài dựng.
