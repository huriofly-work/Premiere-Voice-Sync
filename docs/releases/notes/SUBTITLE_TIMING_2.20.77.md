# 2.20.77 — giữ primary DTW khi lượt bổ sung chỉ còn timing ước lượng

Đã truy riêng Medium và Turbo, không suy lỗi model từ caption cuối. Cả hai
có lời cảm ơn ở ASR ban đầu; lượt nhận diện bổ sung có ngữ cảnh lại bị suy
giảm và chỉ còn timing estimated.

- Medium: 80 từ nhận diện gồm 5 từ ngữ cảnh và outro; không nhận ra mốc trái.
  Cắt theo vị trí ước lượng chỉ giữ 69 từ, làm mất “Xin cảm ơn các nhà khám”.
  Raw primary còn đuôi hoàn chỉnh 74 từ DTW, khác một số chữ so với lượt sau.
- Turbo: lượt bổ sung sinh lời quảng bá khác; cả 13 từ được chấp nhận sau
  crop đều estimated, trong khi primary còn 75 từ DTW của lời cảm ơn thật.

## Chính sách chung, không theo riêng checkpoint

Đường lui 2.20.76 vốn chỉ chạy khi supplement rỗng. 2.20.77 cho phép dùng
lại primary khi toàn bộ từ được chấp nhận ở lượt bổ sung là estimated.
Primary vẫn phải đạt mọi guard của 76: đuôi cuối source, mốc SRT trái duy
nhất, ít nhất bốn từ mới, toàn bộ DTW/origin/anchor/bounds/source/chapter/
thứ tự và hỗ trợ âm thanh hợp lệ. Không cắt ngang từ, không lấp khoảng
trong hoặc cue SRT unresolved, không bỏ lỗi native.

Lượt bổ sung có DTW hoặc timing hỗn hợp giữ nguyên. Nếu primary không đạt,
giữ đường xử lý cũ và chẩn đoán estimated; không nâng estimated thành DTW,
không bỏ phiếu bản chép bằng confidence, không lọc cứng tên quảng bá hay
sửa chữ bằng lời chuẩn. Ghi reason `estimated-context-rerecognition` trong
`primarySupplementReuseRanges`; đường rỗng của 76 vẫn có reason riêng.

Chỉ snapshot primary khi dùng SRT; luồng tạo caption không SRT không giữ
thêm bản snapshot không dùng tới. Model lock, raw ASR, preset, thuật toán
SRT/omission, bộ kiểm âm thanh và ngưỡng timing không đổi.

## Kết quả toàn engine ngoại tuyến

Cùng audio Nam Cực dựng lại 766,5s, source SRT 255 cue, weights/preset đúng
checkpoint, engine mới dùng chung. Đã kiểm nguyên chuỗi SRT ở caption cuối
qua các chỗ tách, không chỉ số selected. WER outro dùng 77 token người dùng
cung cấp, bỏ khác biệt hoa/thường/dấu câu và giữ dấu tiếng Việt.

| Model | Giữ SRT | Lỗi outro 76 → 77 | Kết quả |
|---|---:|---:|---|
| Small | 255/255 | 7 → 7 |Caption giống từng byte 76|
| Medium | 254/255 | 9 → 5 |Có lại đầu câu cảm ơn, 74 token primary|
| Turbo | 254/255 | 75 → 3 |Có lại lời thật, 75 token primary|
| Large-v3 | 255/255 | 3 → 3 |Giữ fix 76, caption giống từng byte 76|

Không đổi model production: vẫn Small. Medium/Turbo còn cue 138 và mọi model
vẫn sai tên Null Seek. Mốc cuối câu SRT trước outro của Medium vẫn 750,26s,
trong khi có khoảng lặng đo được trước đó; bản này khôi phục chữ, chưa
xác minh/sửa riêng mốc ấy. Không dùng số vùng estimated hoặc bảng này để
khẳng định timing đã chính xác trong Premiere hay chọn model thắng chung.

## Hồi quy và nghiệm thu

[Test primary supplement](../../../tests/unit/Test-SubtitlePrimarySupplement.ps1)
thất bại trên 76 với `PRIMARY_DTW_LOST_TO_ESTIMATED_SUPPLEMENT`, rồi đạt sau
sửa. Kiểm primary không đạt vẫn giữ local, local mixed/DTW không bị thay,
reason/provenance, raw bất biến và tất cả guard của 76. 59 nhóm hồi quy đạt,
132 script PowerShell parse local; replay lịch sử giữ đúng 27 cue Short và
199 cue có nhãn A/C. [Số đo/hash/trace](../../benchmarks/SRT_REGRESSION_2.20.77.json).

Gói/cài/CI ghi trong metadata phát hành. Native Premiere import/playback/
word timing/marker/Auto edit còn chờ; audio dựng lại không gồm mix/effect
native. Các bảng 76 và trước đó giữ nguyên nhãn lịch sử, không ghi đè asset.
