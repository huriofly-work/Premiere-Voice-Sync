# Premiere Voice Sync 2.20.61 — giữ câu có số và câu cuối SRT trong Short

## Hai lỗi được xác nhận

Đọc bản project được lưu lúc 15:27:24 ngày 17/10/2026 và cache của lượt 15:25:55–15:26:42, sequence Final vertical: 45 caption và 2 marker. Chỉ đọc file; không điều khiển Premiere hoặc sửa project.

1. Caption 10, 15,200–18,367 giây: ASR ghi “khoảng cách đó và khoảng 9,46.000 tỷ km,” thay cho SRT 5 “Khoảng cách đó vào khoảng 9 phẩy 46 nghìn tỷ kilomet.”. Bộ nhận dạng cũ từ chối cả câu vì phần số khác nhau dù ngữ cảnh nhận ra được câu.
2. Caption 41–45, 62,667–71,033 giây: marker bổ sung chứa cả SRT 20 “một cuộc trao đổi đơn giản nhất cũng có thể tiêu tốn hàng chục nghìn năm.” rồi mới đến lời “Phần hay nhất…”. SRT có 109 cue; audio Short chỉ dùng đến cue 20. Vùng chưa giải quyết gồm cue 20–109, vượt giới hạn 40 cue của bước phục hồi cả khối. Chiếu toàn bộ SRT còn để cue kế tiếp lấy mất đuôi “chục”, khiến cue 20 không vượt kiểm tra nhận dạng.

Không có bằng chứng playback để kết luận voice đọc số sai; ở đây đã xác nhận chữ ASR khác chữ SRT.

## Thay đổi

Luồng Chỉ tạo subtitle nhận dạng ngữ cảnh hai bên một cụm số, với số lượng và tỷ lệ từ khớp tối thiểu. Khi ngữ cảnh xác định được câu, giữ nguyên SRT. Hai cách ghi số tương đương rõ ràng được chuẩn hóa; nếu khác hoặc ASR ghi mơ hồ, marker ghi số SRT, số nhận diện và việc đã giữ SRT. Marker trỏ caption cuối chứa số; không khôi phục cảnh báo timing số đã bỏ ở 2.20.60. Không tạo timestamp từ giả để ép khớp phần số.

Sau bước phục hồi cả khối, thử riêng từng câu chưa nhận ra trong audio được câu lân cận giới hạn. Chỉ nhận câu đạt kiểm tra nhận dạng/timing hiện có, giới hạn 30 giây/400 từ nhận diện/200 từ SRT và ngân sách chiếu tích lũy. Câu lặp không đủ neo vẫn bị từ chối. Phần SRT nằm sau audio không được tự thêm. Chỉ sau bước này mới nhận diện bổ sung khoảng còn lại, nên câu cuối hợp lệ không bị đổi sang ASR cùng outro.

Không đổi core chứng minh bỏ hình của Auto edit. Không tự chỉnh project, caption hoặc marker đã tạo.

## Bằng chứng và giới hạn

Phát lại cùng 317 từ từ cache nhận diện với SRT 109 cue: mã 2.20.60 giữ 18 cue (thiếu 5 và 20); mã mới giữ đủ 20 cue đầu, bỏ qua 89 cue ngoài Short. Giữ đúng câu SRT 5 và nội dung số, báo đối chiếu “9 phẩy 46 nghìn tỷ” với “9 46 000 tỷ”. SRT 20 khớp 62,190–66,080 giây theo cache. Phần bổ sung duy nhất từ 66,080–70,960 giây chứa “Phần hay nhất vẫn còn ở phía sau hãy nhấn vào video dài ở phần video liên quan bên dưới để xem đầy đủ”. Đây là phát lại cache với mốc cấp segment; không phải nhận diện/DTW mới hoặc playback trong Premiere.

Bằng chứng cục bộ: `.tmp-short-reference-2.20.61/markers.json`, `captions.json`, `baseline-selection.json`, `replay-summary.json`, `complete-replay.json`. Project gốc được đối chiếu hash sau thao tác. Kiểm hồi quy mới gồm Short/SRT dài, chỉ bổ sung CTA, không chèn cue tương lai, số khác giá trị, số khác cách ghi, metadata dấu thập phân, ngữ cảnh không liên quan và marker theo caption chứa số.

Bộ hồi quy đạt 51 nhóm, parse 121 script PowerShell; sáu nhóm Windows integration được runner bỏ qua. Log `.tmp-short-reference-2.20.61/suite-final.log`. Core ReferenceAlignment/Alignment, engine Auto edit và host Premiere khớp byte với gói 2.20.60. Hash project gốc giữ nguyên sau kiểm tra.

Cần chạy lại tạo subtitle và nghe lại hai điểm trong Premiere để xác nhận hành vi native mới. Kiểm thử cache và mã không thay thế nghiệm thu playback.

Gói đã kiểm đủ 70 file payload, 71 mục ZIP/checksum và khớp nguồn runtime; 12 bộ VM chạy trên mã đóng gói đạt. Bằng chứng `.tmp-short-reference-2.20.61/package-verified.json`, `package-tests.log`. ZIP SHA256: `C1567785F222B7380CFB90967761828E5A583E47032439DF2460902610C53AC5`. Các kết quả đóng gói/cài đặt được bổ sung vào tài liệu repository sau build; ZIP đã kiểm được giữ nguyên.

Đã cài từ 2.20.60 lúc 15:47–15:49 ngày 17/10/2026 (UTC+7), khi Premiere/helper đã đóng. 62/62 file panel đúng checksum; giữ nguyên 3.501 file dữ liệu, 22 thư mục và registry CEP. Đã sao lưu panel cũ. Bằng chứng `dist/_installation-2.20.61-20261017T084751Z/verified.json`; hash project vẫn giữ nguyên sau cài. Không có lượt chạy native 2.20.61 trong lần kiểm tra này.
