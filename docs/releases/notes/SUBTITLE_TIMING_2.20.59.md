# Premiere Voice Sync 2.20.59 — nhận ra câu để giữ chữ SRT

Theo yêu cầu người dùng, khi nhận ra lời nói tương ứng với một câu SRT thì
giữ nguyên chữ SRT. Không yêu cầu ASR nhận đúng từng từ, không thay cả câu
bằng ASR chỉ vì sai vài từ, dấu thanh hoặc cách phát âm. Việc nhận ra câu và
việc xác minh timing từng từ là hai kết luận riêng.

## Thay đổi

Thêm tiêu chí nhận dạng câu trong luồng subtitle, sau khi đã ánh xạ đúng nguồn,
thứ tự và vùng lời nói. Dùng nhiều từ làm dấu hiệu của cả câu, cho phép vài từ
bị sai/thiếu/thừa hoặc ở đầu/cuối câu. Câu ngắn từ ba từ cũng được xét. Chữ
SRT, dấu câu và cách viết số/tên riêng được giữ nguyên; không sửa chữ nguồn.

So khớp dấu thanh và độ gần chính tả chỉ bổ sung bằng chứng nhận dạng câu,
không khẳng định ASR/người nói đã đọc chính xác từng từ. Tiêu chí gồm ít nhất
hai từ neo, ít nhất một nửa từ có dấu hiệu mạnh, điểm toàn câu tối thiểu 0,7
(hai phần ba cho câu ba từ); giới hạn số từ chưa chắc chắn tùy độ dài câu.
Không còn điều kiện hai mép exact hoặc tối đa hai từ khác áp dụng cho mọi câu.
Những timestamp đã quan sát được được giữ; không tạo mốc DTW cho từ bị thiếu.

Sửa thêm trường hợp câu SRT lặp ở những vị trí khác nhau, như “Nói cách khác”
hoặc “Theo Nguyên lý Tầm thường”: hai câu hàng xóm phân biệt được lần xuất hiện
thì vẫn giữ đúng câu. Chỉ còn mơ hồ khi nhiều bản sao nằm trong cùng một vùng
chưa xác định. Khôi phục cả câu đã được lượt đọc lại nhận đủ nhưng bị bộ tìm
cue exact loại lần nữa vì văn bản có bản sao ở nơi khác trong SRT.

Chỉ dùng ASR làm chữ cuối khi không xác định được câu SRT tương ứng hoặc có
lời nói ngoài SRT. Cue đã được bằng chứng dùng chung phân loại là bỏ khỏi voice
không được phục hồi. Không thay điều kiện Auto edit cho phép xóa hình.
Luật 2.20.58 không tạo marker “Giữ chữ SRT khớp phần lớn” được giữ nguyên.
Các cảnh báo timing/số độc lập vẫn hoạt động.

## Kiểm chứng

Ca kiểm mới đi qua chọn SRT → bổ sung → tách caption, xác nhận giữ nguyên chữ
trong các trường hợp: câu ngắn, sai dấu/phát âm, sai đầu/cuối câu, ASR bỏ/thừa
vài từ, câu lặp có ngữ cảnh phân biệt; từ chối nội dung khác và bỏ cả cue.
Kiểm riêng rằng chính sách subtitle không thay bằng chứng cho Auto edit.

Đối chiếu lại cùng 4.505 từ từ cache ASR của project thật với 296 cue SRT:
tiêu chí cũ giữ được 207 cue, tiêu chí nhận ra câu giữ được 281 cue, tăng 74 cue.
Đây là so sánh chính sách trên cùng mapping và timestamp cấp segment cũ,
không phải chạy lại DTW/ASR hay số marker native mới. Những câu source đã
bị bỏ và phần outro khác SRT vẫn không được tự chèn lại.

Phát lại chính `Select-PvsSubtitleReference` trên dữ liệu cache và recovery
có giới hạn xác nhận kết quả lựa chọn cuối; bằng chứng ở
`.tmp-srt-priority-2.20.59/selection-summary.json`. Các dữ liệu thực dùng để
so sánh nằm trong `policy-summary.json`, `policy-replay.json` cùng thư mục.

Không mở/đóng Premiere, Play, Save/Undo, sửa marker hoặc caption trong project.
Cần chạy lại workflow để tạo caption theo tiêu chí mới; cài đặt không tự sửa
caption/marker cũ. Căn biên của các vùng ASR ngoài SRT vẫn cần nghe lại nếu
không đủ timing; không suy độ chính xác toàn bộ 19 phút từ kiểm ngoại tuyến.

## Kết quả phát hành và cài đặt

Kiểm hồi quy đạt **49 nhóm / 119 script PowerShell parse hợp lệ**; sáu nhóm
Windows integration được runner bỏ qua. TEMP/LOCALAPPDATA thử nghiệm nằm trong
workspace; lượt đầu bị quyền sandbox chặn cache/junction, lượt môi trường riêng
ngoài sandbox đạt. Log: `.tmp-srt-priority-2.20.59/suite-final.log`.

Kiểm đủ 71 entry ZIP (70 payload + checksum manifest), đối chiếu nguồn,
12 bộ VM trên runtime của gói và sáu nhóm engine trên thư viện lấy nguyên byte
từ gói đều đạt. Thư viện engine duy nhất thay đổi so với 2.20.58 là
`CaptionOnly.ps1`; shared reference core, engine Auto edit và host giữ nguyên.
Mã nguồn C# helper không đổi; binary/lock được builder dựng lại.

Đã cài **2.20.59 từ 2.20.58**, 62/62 file panel đúng hash, giữ nguyên
2.852 file dữ liệu/22 thư mục theo snapshot ngay trước/sau cài. Registry CEP
không đổi, panel trước được sao lưu, Premiere/helper đã đóng tại lúc cài.
Không chạy helper, Save/Undo hoặc can thiệp project.

ZIP SHA256: `FBCF625DA4D617FF1881E3D84BE60701FB4E3B385675EFC563D6FBA8A3905D6A`.
Bằng chứng cài: `dist/_installation-2.20.59-20261017T074352Z/verified.json`.
Các file `package-verified.json`, `package-tests.log`, `package-engine-tests.log`
nằm trong `.tmp-srt-priority-2.20.59/`.

Log lượt native **2.20.58** lúc 14:11–14:18 ngày 17/10/2026 xác nhận
671 caption/65 marker. Project được người dùng lưu lại lúc 14:21 nên đã khác
snapshot 2.20.57 dùng cho kiểm ngoại tuyến. **Chưa có lượt native 2.20.59**;
không dùng kết quả 281 cue để suy ra số marker hoặc độ chính xác timing cuối.
Mục kết quả này được bổ sung vào tài liệu repository sau đóng gói, không sửa ZIP.
