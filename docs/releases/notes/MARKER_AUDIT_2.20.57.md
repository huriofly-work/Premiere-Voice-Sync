# Kiểm tra toàn bộ marker của lần chạy 2.20.57

Kiểm tra ngoại tuyến project đã lưu lúc 11:25:09 ngày 17/10/2026, sequence
`Final`; đối chiếu workflow 11:17–11:23, hai SRT nguồn và cache nhận diện.
Không điều khiển Premiere, không Save/Undo hay sửa project. Bản phân tích nằm
trong `.tmp-marker-audit-2.20.57/`; hash project được kiểm lại sau khi đọc.

## Toàn bộ kết quả

671 caption, 137 marker, 141 lý do (một marker có thể chứa nhiều lý do).
Log import và project đã lưu thống nhất số caption/marker.

| Nhóm lý do | Số lượng | Kết luận |
| --- | ---: | --- |
| Giữ chữ SRT khớp phần lớn | 72 | Chữ SRT được giữ đủ ở cả 72 vùng. 70 vùng khớp toàn bộ chữ caption trong khoảng; hai vùng còn chứa phần caption kế bên do mép caption. Theo yêu cầu người dùng, bỏ loại marker này. |
| Cue SRT chưa xác minh, dùng ASR | 46 | Có cả nhận diện sai chính tả/tên riêng và nội dung chưa khớp. Không thể coi tất cả là lỗi cảnh báo. |
| ASR ở vùng chưa được SRT khớp bao phủ | 3 | Không khẳng định SRT không có câu này. Ví dụ 255,30–256,20 là “Nói cách khác,”, có trong SRT nguồn nhưng lượt đối chiếu không giữ được. |
| Timing số chưa xác minh | 11 | 8 cue phân tích ánh xạ thành 11 caption có số; không phải 11 kết luận đọc sai số. |
| Timing ước lượng cấp câu | 9 | DTW và lượt thử lại thất bại; cảnh báo có cơ sở. Dùng timing này để cắt chữ ngữ cảnh gây lỗi thực sự bên dưới. |

Không thấy caption thời lượng âm/0, chồng thời gian hoặc marker trùng vị trí.
CPS cao nhất khoảng 25,71; lỗi 255 CPS của lần trước không còn. Không còn
23 cảnh báo khoảng trống ngắn của lần trước; log mới ghi 34 khoảng nghỉ được
phân loại riêng và 0 vùng bổ sung trống. Không tìm thấy câu quảng cáo
“Ghiền Mì Gõ”, “Hãy subscribe”, “Hẹn gặp lại” từng sinh nhầm trong lần trước.
Đây là kiểm dữ liệu, chưa phải nghe lại toàn bộ 19 phút trong Premiere.

## Lỗi còn tồn tại đã xác định

1. **Lặp/mất chữ khi cắt ngữ cảnh bằng timing ước lượng.** Caption 10 kết thúc
   “chân không suốt một năm.”, caption 11 lại thêm “khùng suốt 1 năm,” tại
   16,27–17,37 giây. Caption 315 kết thúc “một ngôi sao,”, caption 316 bắt đầu
   “sao, nhằm…” tại 538,20 giây. Caption 415 ở 701,27 giây bắt đầu “sở thú
   vũ trụ…” và mất “Giả thuyết thứ hai là giả thuyết…”. Lần trước còn câu này.
   Cache ASR mới vẫn có phần đầu, nên trường hợp này có bằng chứng lỗi xử lý
   chữ sau nhận diện, không chỉ mô hình nghe thiếu.
2. **SRT đúng vẫn bị thay bằng ASR sai.** Ví dụ “hưng thịnh” thành “hương thích”
   (caption 75), “Giới hạn” thành “Rời hạn” (caption 13), “Rừng Tối” thành
   “dừng tối” (khoảng 960 giây). Điều kiện giữ cue yêu cầu hai mép exact,
   tối đa hai từ khác và >=80% exact; cue ngắn, tên riêng, cách viết số và sai
   một từ ở mép vẫn dễ thất bại. Chưa chứng minh mọi cue bị loại đều nên giữ:
   có câu/lời kết khác SRT thật, không được tự phục hồi bằng timestamp SRT cũ.
3. **Một số marker liệt kê cue của cả cụm thay vì đúng đoạn con.** Ví dụ hai
   khoảng 176,923–181,640 và 190,720–196,800 đều liệt kê SRT 55,58,59; nhóm
   kết video còn liệt kê nhiều cue không thực sự nằm ở lời cảm ơn. Đây là lỗi
   độ chính xác của diễn giải marker, không chứng minh các cue đó cùng bị mất.

Phát lại cache bằng chính `Convert-PvsReferenceRecognition` và
`Select-PvsSubtitleRecognitionWindow` tái hiện đúng ba trường hợp lặp/mất chữ
ở mục 1, không chạy lại ASR. Bằng chứng: `cached-crop-replay.json`.
Khi fallback cấp câu phân bố đều timestamp từ, cắt theo midpoint từ ở biên
2,5 giây sẽ lấy nhầm phần cuối câu trước hoặc cắt mất đầu câu cần giữ.
Mốc neo ngữ cảnh hiện đòi chuỗi exact 4–8 từ; ASR sai “không/khùng” hoặc
“tinh/tình” có thể khiến mốc neo không dùng được. Kiểm năng lượng không bắt
được trường hợp này vì vùng vẫn có tiếng nói thật, mật độ chữ vẫn hợp lý.

## Phương án khắc phục tiếp theo

- Không dùng timestamp từ ước lượng để quyết định loại chữ ở biên ngữ cảnh.
  Cần căn lại phần nhận diện với câu trước/sau bằng mốc chữ và âm thanh; nếu
  chưa giải quyết được biên, thử lại cửa sổ/DTW rồi giữ cảnh báo cụ thể, không
  âm thầm coi phần chữ còn lại là đầy đủ. Kiểm mất đầu/đuôi và lặp ngữ cảnh.
- Căn lại chữ ASR bổ sung với cụm SRT tương ứng trước khi chốt đầu ra; giữ
  SRT ở sai khác chính tả có bằng chứng hai bên, số/tên riêng có ngữ cảnh.
  Không chỉ hạ ngưỡng 80% toàn cục, không phục hồi cue đã bị cắt khỏi voice.
- Ánh xạ marker bổ sung về cue/caption thực sự giao đoạn con; lời ngoài SRT
  thật dùng nhãn riêng, không gán toàn bộ cue chưa khớp của phần cuối video.
- Ca nghiệm thu bắt buộc: ba lỗi biên trên; tên riêng/số; câu SRT ngắn;
  voice đã bỏ câu; thêm lời ngoài SRT; CTA thật; toàn bộ đầu ra của project.

## Thay đổi 2.20.58 theo yêu cầu mới

Chỉ bỏ marker có lý do bắt đầu “Giữ chữ SRT khớp phần lớn”. Giữ dữ liệu
`referenceReviewCues` trong báo cáo và thống kê/vị trí trong workflow log.
Cảnh báo timing, số, ASR bổ sung và các loại review khác vẫn hoạt động độc lập.
Trên dữ liệu hiện tại, bỏ 72 lý do này còn **65 marker / 69 lý do**.
Con số này là lọc/phát lại dữ liệu đã lưu, chưa phải lần chạy native 2.20.58.
Các lỗi xử lý chữ nêu trên chưa được sửa trong bản chỉ thay marker này.

Marker cũ trong project chỉ được đối soát khi chạy lại trong phạm vi tương ứng;
cài bản mới không tự sửa caption/marker đang có trong project.
