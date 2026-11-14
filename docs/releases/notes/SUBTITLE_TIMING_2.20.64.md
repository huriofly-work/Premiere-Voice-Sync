# Premiere Voice Sync 2.20.64 — giữ SRT trong Short và chỉ rõ chữ ASR

## Kiểm tra project Ý thức đến từ đâu

Đọc project `Ý thức đến từ đâu_1.prproj` được lưu lúc 16:46:52 ngày 17/10/2026,
sequence `Final vertical`; đối chiếu workflow 16:38:36–16:39:16, `Source.srt`
615 cue và toàn bộ cache nhận diện của lượt chạy. Sequence có 49 caption và
3 marker, chứa 5 lý do. Không điều khiển Premiere hoặc sửa project.

- Marker 0 giây chứa ba lý do: timing ước lượng 0–14,547 giây, toàn vùng
  0–75,100 giây không khớp SRT, và chữ ASR cho caption 1–49. Không phải riêng
  câu đầu không có trong SRT: **không cue SRT nào được giữ trong cả lượt chạy**.
- Marker 14,633 giây cảnh báo timing ước lượng 14,648–34,530 giây;
  marker 34,600 giây cảnh báo timing ước lượng 34,614–50,247 giây.
  Các lần DTW chính và retry đều gặp `CAPTION_DTW_ANCHOR_SPAN_INVALID`.
  Đây là cảnh báo có bằng chứng timestamp xung đột, không kết luận voice sai.
- Cache ASR ghi “bộ náo”, “vụ trụ”, “thư có thể”, “lời dài”…; caption dùng
  chữ nhận diện đó khi nhánh đối chiếu SRT thất bại. Không có phép thay chữ
  “não” thành “náo” trong SRT. Marker có cảnh báo ASR nhưng gộp 49 caption và
  cắt trích dẫn ở 220 ký tự nên không chỉ rõ các chỗ thay chữ phía sau.
- Caption đã lưu không có thời lượng âm/0, chồng thời gian hoặc đảo thứ tự;
  ba marker có vị trí khác nhau. Toàn bộ 49 caption được đưa vào kiểm dữ liệu.

## Nguyên nhân và sửa

`Find-PvsEditedReferenceMatches` tìm thấy nhiều câu đầu đúng thứ tự, rồi cue
360 “Về ý thức” tình cờ khớp ba từ bên trong câu 6. Cụm ngắn ở phần tương lai
làm `Ordered=false`; `Resolve-PvsEditedReference` trả null và bỏ toàn bộ các
câu đã nhận ra. Scope dự phòng còn đòi khớp hai mép toàn audio, trong khi
Short có CTA ngoài SRT, nên cả vùng bị chuyển sang ASR.

Chỉ adapter subtitle yêu cầu neo câu có ít nhất bốn từ. Cụm ngắn được phục hồi
trong khoảng có ngữ cảnh, không được dùng để phủ nhận mọi neo mạnh. Thêm một
lượt xét ngược các câu chưa nhận ra khi câu được phục hồi sau đó tạo đủ hai
mép; dùng chung ngân sách chiếu, không xét lại tương lai thiếu neo bên phải.
Ví dụ cue 29 được giữ sau khi cue 30–31 đã chặn đúng phần đuôi trước CTA.
Tham số mới của core mặc định bằng 0; Auto edit vẫn dùng hành vi cũ và các
guard chứng minh bỏ hình cũ. Không tạo timestamp cho từ thiếu.

Kiểm audio còn tái hiện một chữ “dài.” thừa sau SRT “lời giải.”: ASR ở ngữ cảnh
đọc “lời dài” nhưng độ gần chính tả chưa đủ để cắt phần đuôi câu đã giữ.
Với neo ngữ cảnh 6–8 từ, cho phép đúng một khác biệt chính tả có độ gần >=0,5
và mọi từ còn lại khớp; neo ngắn giữ ngưỡng cũ. Nhiều từ khác, từ không liên
quan, số và cụm lặp vẫn bị từ chối. Chỉ dùng để nhận phần hàng xóm đã giữ,
không dùng để thêm câu SRT hoặc làm bằng chứng cắt hình.

Lý do lỗi biên tái xuất hiện sau 2.20.60: ca “tận” → “tật” có độ gần chính
tả vượt ngưỡng cũ 0,6; “giải” → “dài” chỉ đạt 0,5 nên nhánh nhận ra đuôi
không chạy. Bộ kiểm trước có ca biến thể gần, từ không liên quan, cụm lặp và
lời thêm thật, nhưng thiếu ca thay hai ký tự trong neo dài này. Đây là phạm
vi sửa/kiểm trước chưa đủ, không phải bằng chứng nhận diện đã đúng trên mọi
sequence. Bản mới kiểm thêm ca này và chạy toàn engine trên voice dựng lại;
không cam kết mọi lỗi ASR/timing sẽ hết khi chưa kiểm media tương ứng.

Marker ASR nay trỏ từng caption cuối, chứa nguyên chữ caption và thời gian của
caption đó. Log ghi số cue thực sự giữ từ SRT; khi bằng 0, cảnh báo và thông
báo hoàn tất nói rõ toàn bộ caption là ASR. Việc chọn SRT không còn được báo
chung là “dùng nội dung SRT” khi thực tế không giữ được câu nào.

## Bằng chứng và giới hạn

Phát lại 334 từ từ cache nhận diện gốc: bản 2.20.63 giữ 0 cue; mã mới giữ đúng
27 cue: 1–9 và 14–31, giữ nguyên chữ SRT. Không thêm cue 10–13 đã cắt khỏi
Short hoặc cue 32–615 ở ngoài Short. Đây là replay timestamp cấp segment,
không phải bằng chứng DTW/playback của lượt gốc.

Dựng lại 75,1 giây voice từ graph project đã lưu: hai đoạn nested Final tốc độ
1,15, các clip voice gốc và CTA tốc độ 1,1. Chạy toàn engine CPU small ngoại
tuyến, dùng thư mục cache/job riêng trong workspace: giữ 27 cue SRT, tạo 50
caption, phần ASR duy nhất là CTA 70,257–74,881 giây. Không còn chữ “náo”,
không còn “dài.” bị thêm lặp; không có caption âm/0, chồng hoặc vượt phạm vi.
Không còn cảnh báo timing ở lượt ngoại tuyến này. Audio dựng lại không gồm
hiệu ứng/mix âm native của Premiere, nên kết quả này không chứng minh ba lỗi
DTW của bản export gốc chắc chắn hết ở lượt chạy native tiếp theo.

Bằng chứng nằm trong `.tmp-consciousness-2.20.64/`: project.xml, source.json,
captions.json, markers.json, cache-index.json, baseline-selection.json,
replay-selection.json, voice-map.json, fresh-engine/caption-result.json.
Hash project/SRT được kiểm lại sau kiểm tra. Chưa import caption, Play, Undo,
Save hoặc thay marker trong Premiere. Cần chạy lại workflow để cập nhật output
đã tạo; bản cài không sửa caption/marker cũ.

## Kiểm gói và cài đặt

52 nhóm hồi quy đạt, parse 122 script PowerShell; sáu nhóm Windows integration
được runner bỏ qua. Lượt sandbox đầu dừng ở quyền tạo junction của test bảo
mật; lượt cuối chạy đầy đủ 52 nhóm đạt. Kiểm gói 70 file payload/71 mục ZIP và
checksum khớp nguồn; 15 bộ VM dùng mã đóng gói đạt. Log `suite-final.log`,
`package-tests.log`, `package-verified.json` trong thư mục bằng chứng trên.
ZIP SHA256: `286E0FC5143BA32B412DBBDD0C595078C5240D9CBEF1F402B28E329657F99B9D`.
Các kết quả kiểm gói/cài đặt được bổ sung sau build; ZIP đã kiểm được giữ nguyên.

Đã cài từ 2.20.63 lúc 16:58–16:59 ngày 17/10/2026 (UTC+7), khi Premiere/helper
đã đóng. 62/62 file panel khớp checksum; giữ nguyên 3.595 file dữ liệu, 22 thư
mục và registry CEP. Có bản sao panel cũ và bằng chứng tại
`dist/_installation-2.20.64-20261017T095856Z/verified.json`. Hash project gốc
giữ nguyên sau cài. Chưa chạy native/playback với bản mới.
