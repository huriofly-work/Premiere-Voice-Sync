# Khoảng không lời bị nuốt khi gộp câu — 2.20.80

## Nguyên nhân

Người dùng đặt ngưỡng0,5s và báo tại00:00:42:27 trên timeline sau dựng.
CEP lưu đúng0,5; kiểm mã đã cài qua load/apply/readSettings→job cho đúng năm
thông số70/130%,gap0,5s,voice-group2s,42ký tự, cả chuỗi nhập `0,5`.
Engine cũng đọc đúng0,5. Job native đã tự dọn; log79 không lưu snapshot thông
số nên không gọi bản tái hiện mặc định1s là bằng chứng lượt native đó.

Planner79 gộp theo dấu câu rồi gộp tiếp nếu không được phép cắt voice. Sau
đó mới xét gap giữa các nhóm. Gap nằm bên trong câu chưa hết dấu hoặc nhóm
quanh cue phục hồi đã bị nuốt và retime cùng lời. DTW trial chỉ giữ các gap
đã có trong baseline; speed merge không vượt gap nhưng cũng không thể tạo
lại gap baseline đã bỏ sót.

Replay đảo với đúng0,5s tái hiện gap nguồn48,28–52,44s,4,16s, giữa cue11
“có một không hai” và cue12 “Úc, một lục địa…” bị retime vào42,77–45,50s,
chứa mốc người dùng báo. Không dùng gap SRT làm bằng chứng cắt voice.

## Thay đổi và invariant

- Xét gap trước punctuation grouping. Gap đủ ngưỡng cùng chapter có điểm
  cắt silence an toàn sẽ kết thúc đơn vị câu, kể cả trước dấu phẩy. Giữ
  nguyên duration nguồn theo frame, không speed-merge qua gap.
- Giữ nguyên ngưỡng confidence/noise/min-silence/search/margin/collapse cũ.
  Cue phục hồi vẫn chặn cut thông thường. Riêng gap nguồn có thể có bằng
  chứng độc lập: bốn raw token DTW liên tiếp, ngữ cảnh duy nhất, coverage
  đầy đủ, chapter/bounds/order hợp lệ và cả hai mép. Token số viết gộp chỉ
  được nhận khi đúng toàn chuỗi chữ số và ngữ cảnh như78. Không chia span
  thành word timestamp. Hai mép phải bao một khoảng lặng đo được duy nhất;
  frame cut nằm trong quiet đã trừ margin và cách hai mép speech đủ margin.
- Chỉ tính bằng chứng raw ở cue cần review và hàng xóm của nó. Không thay
  chữ/cue bounds/word timing/acoustic eligibility hoặc cấp DTW cho estimated.
  Manual block vẫn nguyên khối; gap bên trong chỉ được ghi review.
- Alignment mang snapshot gap nguồn. Planner chốt từng gap đạt ngưỡng thành
  preserved hoặc review; omission đã chứng minh chỉ xét gap của cue còn giữ,
  đổi physical→compact coordinates đúng một lần. Không phục hồi hình đã bỏ.
- Gap chưa tách có metadata, marker theo source-frame→V1 cuối sau speed merge
  và completion nêu số khoảng cần rà tay. Không âm thầm coi gap đó đã giữ
  riêng. DTW conservation bảo vệ cả danh sách gap/review và voice partition.
- Workflow stage-end planner lưu năm thông số số đã áp dụng. Không lưu lời,
  media path hay đối tượng cấu hình tùy ý. Các job đã dọn vẫn có audit.

## Kiểm chứng

`Test-SourceDialogueGaps.ps1` thất bại trên planner79 với
`SOURCE_GAP_SWALLOWED_BEFORE_PUNCTUATION`. Sau sửa kiểm dấu phẩy, gap đúng/
dưới ngưỡng tùy chỉnh,30/29,97fps, offset voice, raw102↔chuỗi chữ số, silence
an toàn và âm tính estimated/ambiguity/sai số/NaN. Planner thật và speed
merge giữ text SRT cuối và toàn hình/voice. Không có proof thì cue phục hồi
vẫn giữ nhóm và báo review; manual block có gap vẫn không bị chia.

Các test cũ78/79 vẫn đạt khi không có capability gap mới: không dùng chữ
phục hồi để cắt, không fake DTW, không omission mới. Default UI test nay
chạy reader thật với các thông số tùy chỉnh, cả `0,5`; metrics test khóa
snapshot năm số và privacy; marker test khóa tọa độ hình cuối độc lập A2.

Replay đủ bốn entrypoint trên media đảo với0,5s giữ **30/30 cue→66 caption**,
không mất/lặp chữ, interval dương không chồng.28gap đạt ngưỡng được hạch
toán: **27preserved/1review**. Gap11–12 giữ **125frame** (4,166667s ở30fps)
tại46,70–50,866667s trong output mới. Voice cắt34,4s, giữa raw DTW speech
end34,158465s và start34,642557s; quiet0,484024s. Timing10span của cue11
vẫn có span số estimated, không biến thành12mốc từ DTW. Còn gap5–6 nguồn
22,64–23,36s (0,72s) thiếu điểm silence phù hợp, giữ voice và báo review.

Ca reference cố ý sai vẫn giữ5manual block/65caption, raw102 thay chữ sai,
toàn hình/voice;4gap preserved/24gap review, không phá khối để ép giữ gap.
Đây là test cơ chế, không là nhãn đúng lời audio. Replay dùng metadata clip
đã lưu từ chẩn đoán, không phải đọc timeline hiện tại. File MP3/SRT gốc giữ
hash; không gọi Premiere Save/Undo hoặc sửa project.

Full regression **66nhóm/143PS**, sáu nhóm Windows integration bỏ qua.
Package/install và bằng chứng lịch sử ghi trong release metadata. Model
vẫn Small; native Premiere retime/razor/playback/timing/marker/Save pending.
