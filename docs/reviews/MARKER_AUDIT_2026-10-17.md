# Rà soát marker trên project thật — 17/10/2026

## Phạm vi và bằng chứng

Đọc project vừa lưu lúc 10:30:59, sequence **Final** của project
`Giao tiếp với người ngoài hành tinh_1.prproj`. Đọc toàn bộ marker được sequence
tham chiếu, giải mã caption đang được track sử dụng và đối chiếu hai SRT nguồn.
Không suy số lượng từ những object caption/marker không còn được track tham chiếu.

Project có **154 marker**, chứa **160 lý do**, và **675 caption**; hai SRT nguồn
có **296 cue**. Nhật ký lần chạy 10:16:57–10:22:58 xác nhận panel **2.20.56**,
CUDA và đúng 675 caption. SHA256 project trước/sau kiểm tra:

`E2186AAA441C01EF027B0CD5E51CC66D278784DFCF2A7A80DCAC2B288E53E26D`

Không mở/đóng hoặc điều khiển Premiere, không sửa project, caption, marker hay
mã sản phẩm. Chỉ tạo tài liệu/script/dữ liệu phân tích trong workspace. Audio
kiểm tra được cắt vào thư mục phân tích từ media nguồn theo vị trí/In/Out của
136 clip A2 trong project đã lưu; toàn bộ các clip này có tỷ lệ nguồn/timeline 1:1.
Không áp lại hiệu ứng/mix Premiere. Đây không phải nghe hoặc nghiệm thu toàn bộ video.

## Thống kê toàn bộ marker

| Lý do | Số lý do | Đánh giá |
|---|---:|---|
| Giữ chữ SRT gần khớp | 58 | Đã giữ đầy đủ chữ cả 58 câu; đây là cảnh báo bất định, không phải 58 câu lỗi. |
| Cue SRT chưa xác minh, dùng ASR | 50 | Chính sách vẫn chuyển nhiều vùng sang chữ ASR; có lỗi chính tả/nội dung thực tế trong kết quả. |
| ASR tại vùng chưa có SRT khớp | 3 | Phải kiểm bằng ngữ cảnh; một vùng chứa quảng cáo lạc đề. |
| Không nhận diện được lời / chưa có subtitle | 23 | Tất cả chỉ dài 0,266–0,590 giây; cần phân biệt khoảng nghỉ với thiếu lời. |
| Timing của số chưa xác minh | 20 | Có 8 cảnh báo chứa số thập phân/phân nhóm; không đồng nghĩa đọc sai số. |
| Timing ước lượng cấp câu | 6 | Năm vùng rất ngắn có nội dung ASR lạc đề; một vùng dài 17,657 giây vẫn cần kiểm timing. |

Sáu marker gộp nhiều lý do, nên số lý do lớn hơn số marker. Không có marker
trùng thời điểm trong bộ 154 marker đã lưu. Không thấy marker mang nhãn bổ sung
cũ của các bản trước trong bộ đang được sequence Final tham chiếu.

Không thấy caption đảo thời gian, thời lượng âm/0 hoặc chồng nhau trong 675 caption.
Điều này chỉ xác nhận cấu trúc timestamp, không xác nhận nội dung hoặc căn đúng lời.

Đối chiếu 58 câu giữ chữ SRT: 56 vùng trùng đủ chuỗi từ nguồn; hai vùng có thêm
caption đầu của câu kế tiếp vì marker dùng biên cue phân tích. Cả hai vẫn bắt đầu
bằng toàn bộ chữ câu nguồn, không mất chữ SRT. Cần thu hẹp vị trí marker theo
caption cuối thay vì coi hai trường hợp này là lỗi mất chữ.

## Lỗi nhận diện thực tế và thiếu kiểm tra đầu ra

Năm vùng timing ước lượng ngắn:

| Vùng timeline (giây) | Nội dung bất thường trong caption hiện tại |
|---|---|
| 99,897–100,247 | “Khi mà các bạn có thể nhận được, thì hãy đón kết thúc cho chúng ta.” |
| 172,087–172,597 | “Hẹn gặp lại.” |
| 254,925–256,690 | Quảng cáo kênh Ghiền Mì Gõ. |
| 395,006–395,549 | Quảng cáo kênh Ghiền Mì Gõ. |
| 411,070–411,489 | Quảng cáo kênh Ghiền Mì Gõ. |

Nhận diện CPU ngoại tuyến mới bằng Whisper small trên năm cửa sổ audio có thêm
ngữ cảnh trước/sau không tạo lại các câu lạc đề này. Thay vào đó nhận được các
câu thuộc nội dung đang nói: nền văn minh, tự hủy diệt, xác suất sự sống, giao tiếp
và thiên văn. Đây là bằng chứng mạnh cho hallucination khi nhận diện đoạn quá ngắn,
không phải câu thực sự có trong SRT nhưng bị bỏ qua. Các lượt ASR đối chứng vẫn có
lỗi chính tả, không được coi là bản chép lời đã xác minh bởi người nghe.

Caption 62 chứa 34 ký tự trong khoảng 0,133 giây (255 ký tự/giây); các caption
quảng cáo ở 395 và 411 giây cũng chỉ có vài phần mười giây. Bộ hậu kiểm hiện chặn
đảo/chồng/thời gian không hợp lệ và giới hạn chiều dài dòng, nhưng chưa chặn tốt
chữ ASR không có đủ bằng chứng âm thanh hoặc quá nhiều chữ trong đoạn cực ngắn.
Không nên chỉ bỏ marker để che những caption này.

## Cảnh báo quá mức hoặc chưa đủ chính xác

- 23 vùng “chưa có subtitle” dài tổng 9,691 giây. Trên audio A2 dựng lại không có
  hiệu ứng, 94,3–100% cửa sổ RMS 5 ms của từng vùng nằm dưới -35 dBFS; bảy vùng
  không có cửa sổ nào vượt ngưỡng. Đây là các vùng gần như im lặng hoặc sát mép lời.
  Cả 23 đều được caption cuối che phủ một phần; năm vùng được che ít nhất 95%.
  Vì vậy nhãn “chưa có subtitle” không phản ánh chính xác trạng thái đầu ra cuối.
  Chưa kết luận mọi vùng đều có thể bỏ cảnh báo: vẫn phải kiểm lời SRT được kỳ vọng.
- 53 vùng bổ sung dài tổng 397,952 giây (khoảng 35% phạm vi 1137,533 giây của
  các vùng cảnh báo). Không phải toàn bộ thời gian này là lời sai, nhưng mức dùng
  ASR thay chữ SRT vẫn lớn. Có các dạng số/viết khác nhau, I/II/III, tên riêng và
  lỗi nghe gần âm khiến việc khớp nguyên văn bị đứt. Một số vùng cuối còn có nội dung
  voice thực sự khác SRT, nên không được khôi phục nguyên cả cụm một cách máy móc.
- Ba vùng bổ sung dài hơn 30 giây. `Resolve-PvsEditedReference` yêu cầu cửa sổ
  gồm cả câu neo không quá 30 giây; adapter giữ chữ một phần cũng bỏ qua khoảng
  dài hơn 30 giây. Cần chia vùng kiểm lại có ngữ cảnh, tránh đẩy cả cụm sang ASR.
- `Repair-PvsNumericCaptionTimings` thử lại cả câu có chữ số; thất bại khớp từ
  khác trong câu cũng có thể tạo cảnh báo timing của số. `Join-PvsRecognizedNumericWords`
  chủ yếu xử lý số nguyên; dạng thập phân, cách đọc và I/II/III cần chính sách riêng.

## Lỗi tiềm ẩn đã tái hiện bằng fixture

Nhánh phục hồi của `Resolve-PvsEditedReference` tạo lại word bằng bốn trường
Text/Start/End/Chapter, làm mất `SubtitleTimingQuality` và các trường nguồn timing.
Đã tái hiện: retry trả các từ có `SubtitleTimingQuality=estimated`, sau phục hồi
không còn từ nào giữ trường chất lượng; `Test-PvsSubtitleDtwCue` có thể trả true.
Vì thế timing ước lượng có nguy cơ được coi là đủ điều kiện DTW. Chưa xác định
cụ thể những cue nào của lần chạy thật đi qua lỗi này vì kết quả job đã bị dọn.

Các vùng timing ước lượng được cộng dồn từ lượt chính, retry và supplement;
chưa gắn đầy đủ với việc dữ liệu của lượt đó có được dùng ở caption cuối hay không.
Cần kiểm provenance thay vì xem mọi lần thử đều là một lỗi đầu ra riêng.

ASR cue tự sinh được gán `Confidence=1.0` trong `New-PvsRecognizedSubtitleCues`.
Đây không phải độ tin cậy âm học của Whisper; bộ lọc dựa vào trường này không đủ
để chặn hallucination. Cần tách độ khớp chữ, chất lượng timing và độ tin cậy ASR.

Log tự lưu chỉ giữ thời gian/cache/số caption, không lưu thống kê marker theo
nguyên nhân; job bị dọn sau thành công. Thiếu dữ liệu để tái hiện chính xác mọi
quyết định của lần chạy. Nên lưu thống kê vị trí/loại/chất lượng đã lược thông tin
nhạy cảm và có báo cáo chẩn đoán tùy chọn, không tự lưu toàn bộ lời nói/đường dẫn.

## Phương án sửa đề xuất

1. Bổ sung các ca lỗi thực tế trên làm hồi quy trước khi đổi thuật toán. Chặn
   hallucination bằng bằng chứng âm thanh và đối chiếu ngữ cảnh; không dùng danh
   sách cấm cố định các câu quảng cáo vì người dùng có thể thực sự nói các câu đó.
2. Nhận diện khoảng thiếu kèm lời trước/sau, rồi chỉ lấy phần mới được căn vào
   khoảng cần bổ sung. Khoảng nghỉ không tạo subtitle/marker thiếu lời nếu không
   có chữ SRT được kỳ vọng. Nếu vẫn chưa chắc thì giữ trạng thái chưa xác minh;
   không bịa chữ hoặc bịa timestamp để hoàn tất.
3. Ưu tiên bản chữ SRT qua đối chiếu có chuẩn hóa số/cách đọc/I–II–III theo ngữ
   cảnh, hỗ trợ biến thể chính tả có căn cứ; chia cụm dài để kiểm từng phần. Không
   hạ đồng loạt ngưỡng khớp, không phục hồi câu thực sự bị cắt hoặc thay nội dung.
4. Giữ đầy đủ nguồn/chất lượng timing qua các bước phục hồi. Chỉ phát marker từ
   dữ liệu được dùng trong caption cuối; tách thông tin đã phục hồi khỏi lỗi nội
   dung và lỗi timing cần can thiệp. Thu hẹp marker đến đúng caption/ranh giới.
5. Lưu thống kê chẩn đoán sau dọn job. Kiểm bộ dữ liệu thật ngoại tuyến trước,
   sau đó đóng gói/cài và thử trên sequence sao chép trong Premiere. Giữ nguyên
   điều kiện Auto edit xóa hình, marker thủ công và dữ liệu/cache/model/jobs/backups.

Tiêu chí: năm vùng ASR lạc đề không còn sinh chữ giả; CTA có thật vẫn được giữ;
câu SRT gần khớp không bị đổi thành chữ ASR sai; khoảng nghỉ không báo mất lời
vô cớ; timing ước lượng không bị nâng thành DTW đã xác minh; caption không mất,
trùng, đảo/chồng hoặc vượt phạm vi. Vẫn giữ marker cho lỗi/độ bất định có căn cứ.
Không đặt mục tiêu bằng cách ép số marker về 0.

## Dữ liệu kiểm tra toàn bộ

Trong `.tmp-marker-audit-20261017/`: `markers.json` (154 marker), `issues.json`
(160 lý do với SRT/caption đối chiếu), `captions.json` (675 caption),
`references.json`, `summary.json`, `empty-caption-coverage.json`,
`numeric-issues.json`, `voice-map.json`, `voice-energy.json`, các WAV vùng kiểm
và `context-asr*.json/log`. `project.xml` là bản giải nén chỉ phục vụ đọc.

## Theo dõi sửa lỗi

Đã triển khai, kiểm thử, đóng gói và cài **2.20.57** sau khi người dùng cho phép
tiếp tục. Các vùng lỗi được đưa vào kiểm hồi quy ngoại tuyến; project/caption/
marker gốc giữ nguyên. Xem [kết quả và giới hạn](../releases/notes/SUBTITLE_TIMING_2.20.57.md).
