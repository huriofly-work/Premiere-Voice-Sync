# Premiere Voice Sync 2.20.67 — nhãn một chữ trong SRT

## Bằng chứng từ lượt chạy

Workflow Tạo phụ đề 22:42:09–22:45:03 ngày 17/10/2026 dùng 2.20.66 trên
project `Não có phải bộ thu tín hiệu_1.prproj`, sequence `Final`. Đọc project
đã lưu, SRT 210 cue, log và cache nhận diện; không điều khiển Premiere.

- Caption 247, 433,967–434,600 giây: marker ghi chữ ASR “À,” chưa khớp SRT.
  SRT cue 146 có `A.`.
- Caption 256, 447,733–448,400 giây: marker ghi chữ ASR “C.” chưa khớp SRT.
  SRT cue 150 có đúng `C.`.
- Project có 357 caption trên Final, hai marker cần kiểm tra. Cache nhận diện
  chính có cả A. và C.; các cửa sổ nhận diện lại có À, và C. Vì vậy đây còn là
  lỗi giữ câu ngắn ngay cả khi chữ ASR giống SRT, không chỉ lỗi phát âm của ASR.

## Nguyên nhân và phạm vi sửa

Nhánh subtitle chỉ dùng câu từ bốn từ làm neo, tránh cụm ngắn trong SRT dài
khớp tình cờ và làm mất mọi câu đúng. Nhưng các nhánh phục hồi sau đó đòi
ít nhất ba từ hoặc bằng chứng của cả câu. Câu nhãn một chữ không đủ điều kiện,
kể cả khi retry đã khớp toàn bộ khoảng. Sau đó supplement dùng lại chữ ASR và
tạo marker “chưa khớp SRT”.

Thêm phục hồi riêng trong adapter Tạo phụ đề cho nhãn chữ hoa A–Z, có thể kèm
dấu câu. Hai cue SRT liền kề phải đã nhận ra, mỗi câu có ít nhất bốn từ,
đủ độ khớp và timestamp hợp lệ, cùng nguồn. Khoảng giữa tối đa ba giây,
chứa đúng một từ có cùng chữ sau chuẩn hóa dấu/biến thể hiện có. Chỉ dùng span
thực của từ đó, tối đa hai giây, nằm trọn giữa hai neo. Giữ nguyên chữ/dấu câu
SRT và không báo đó là lời ngoài SRT.

Không khôi phục nhãn từ khoảng im lặng, từ khác, lời thêm, hai nhãn mơ hồ cùng
khoảng, thiếu một neo, sai nguồn hoặc timestamp không hợp lệ. Không dùng
timestamp gốc SRT làm timing mới. Đánh dấu phục hồi ở adapter, không nâng
thành bằng chứng DTW hoàn chỉnh hoặc bằng chứng bỏ hình. Core
`ReferenceAlignment.ps1` và chính sách Dựng theo voice giữ nguyên.

## Kiểm chứng

Bằng chứng ở `.tmp-letter-reference-2.20.67/`. `source.json` ghi hash project
và SRT; `markers.json`, `tracks.json`, `cache-index.json` lưu dữ liệu kiểm.
Replay toàn bộ 2.346 từ từ cache chính trên 210 cue, dùng timestamp cấp segment
và callback lọc chính các từ đã nhận diện: trước sửa giữ 197 cue, sau sửa 199,
chỉ thêm cue 146 A. và 150 C. Những cue khác giữ nguyên. Đây không phải phát lại
chính xác các cửa sổ DTW/retry của lượt native; số cue giữ không đại diện kết
quả toàn engine của lượt native.

Kiểm audio riêng dựng lại vùng 420–465 giây từ các clip A2 và InPoint/speed
trong project đã lưu, chạy engine CPU small với job/cache/temp riêng trong
workspace. Không bao gồm hiệu ứng/mix native của Premiere. Trên cùng WAV,
engine 2.20.66 giữ 12 cue, không giữ cue 146/150; bản sửa giữ 14 cue gồm cả
hai nhãn đúng chữ SRT. Có 27 caption cuối, không chồng/đảo thời gian hoặc
vượt phạm vi; không có vùng timing ước lượng. Supplement còn lại ở mép cắt
465 giây, không thuộc hai nhãn. `verified.json` lưu kết quả và hash nguồn.

53 nhóm hồi quy đạt, parse 123 script PowerShell; sáu nhóm tích hợp Windows
được runner bỏ qua. Lượt sandbox đầu bị chặn tạo junction của bài kiểm bảo
mật; lượt đầy đủ sau đó đạt, giữ nguyên bài kiểm. Kết quả ở `suite-final.log`.
Kiểm gói/cài đặt được ghi bổ sung sau khi hoàn tất.

`Test-SubtitleLetterReference.ps1` kiểm nhãn đúng/khác dấu, offset nguồn,
giữ chữ tới caption cuối, không tạo supplement/marker ASR sai, các ca âm thanh
trống/khác chữ/thêm từ/mơ hồ, thiếu neo, sai chapter/span, NaN/Infinity,
và giữ nguyên bằng chứng cắt hình của core.

Cài đặt không sửa caption hoặc marker đã có. Cần chạy lại Tạo phụ đề để nhận
kết quả mới; Play, import và hiển thị marker thực tế trong Premiere vẫn chờ
người dùng kiểm tra. Không thao tác project, Save hoặc Undo.

## Gói và cài đặt

70 tệp payload/71 mục ZIP khớp checksum và nguồn; 47 tệp engine/host khớp
2.20.66, thay đổi engine duy nhất là adapter `CaptionOnly.ps1`. 20 bộ VM kiểm
mã đóng gói và bốn bộ PowerShell kiểm thư viện từ gói đều đạt. Bằng chứng:
`package-verified.json`, `package-tests.log`, `package-engine-verified.json`.

ZIP SHA256: `7C8A81BB74AEB5350D70C65530C0338B0D78599988EAE334BE1E8216388D266A`.

Đã cài từ 2.20.66 lúc 23:01 ngày 17/10/2026 (UTC+7), khi Premiere/helper đã
đóng. 62/62 tệp panel khớp gói, giữ nguyên hash 3.797 tệp dữ liệu/22 thư mục
và registry CEP. Bản sao panel cũ và xác minh tại
`dist/_installation-2.20.67-20261017T160101Z/verified.json`. Gói ZIP đã kiểm
giữ nguyên; bằng chứng cài đặt được bổ sung sau build. Hash project/SRT được
kiểm lại sau cài. Nghiệm thu chạy lại/import/Play/marker native vẫn chờ người dùng.
