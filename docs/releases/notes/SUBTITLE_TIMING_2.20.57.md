# Premiere Voice Sync 2.20.57 — nhận diện bổ sung có ngữ cảnh và bằng chứng

Bản này xử lý các vấn đề tìm thấy trong 154 marker/675 caption của project thử
ngày 17/10/2026: nhận diện đoạn rất ngắn sinh câu lạc đề, khoảng nghỉ bị báo thiếu
subtitle và mất nguồn/chất lượng timing qua phục hồi. Không sửa project đã lưu.

## Hành vi

- Khoảng cần bổ sung được nhận diện với tối đa 2,5 giây audio trước/sau, nằm
  trong nguồn đang chọn. Vùng dài được chia tối đa 20 giây, ưu tiên khoảng nghỉ;
  mỗi lần đọc cả ngữ cảnh tối đa 25 giây. Chỉ lấy lời trong vùng cần bổ sung.
- Đối chiếu mốc neo chữ duy nhất của câu trước/sau để không chèn lặp ngữ cảnh.
  Không cắt theo câu lặp mơ hồ, không đưa chữ SRT vào prompt lượt bổ sung.
- Kiểm bằng chứng âm thanh và mật độ chữ/từ để từ chối giả thuyết bị nén bất
  thường hoặc gần im lặng. Không cấm câu quảng cáo/tên kênh; lời CTA có thật vẫn
  có thể được tạo. Bộ lọc là kiểm tra thận trọng, không bảo đảm mọi lỗi ASR đều bị chặn.
- Khoảng nghỉ đo được, dài không quá 0,65 giây và được silence detector phủ ít
  nhất 90%, được ghi thông tin thay vì nhận diện thêm và báo thiếu subtitle.
  Vùng dài hoặc chưa đủ căn cứ vẫn được giữ để kiểm tra. Nhãn/vị trí cảnh báo
  thiếu caption dựa vào đầu ra cuối, không khẳng định cả vùng đều thiếu subtitle.
- Bảo toàn chất lượng/nguồn timing và các mốc token qua phục hồi. Timing cấp câu
  không được coi là DTW đã xác minh; bỏ cảnh báo của lần thử không dùng ở đầu ra.
- Có thể giữ cue SRT gần khớp trong cụm dài đến 40 cue/800 từ, có guard bộ nhớ;
  không dựa vào timestamp SRT cũ để tự điền timing. Giữ điều kiện đối chiếu từng
  câu và không phục hồi cue đã có bằng chứng bị bỏ khỏi voice.
- Cấp độ I/II/III và chữ số tương ứng là khác cách viết khi có đúng ngữ cảnh
  “cấp độ”; khác giá trị vẫn là nghi vấn nội dung. Số như 13 phẩy 8 có thể giữ
  nguyên chữ SRT khi dữ liệu ASR còn bằng chứng raw surface 13,8/13.8; không bịa
  timestamp riêng cho chữ “phẩy”. Những dạng số khác vẫn có thể cần nghe lại.
- Log tự lưu ghi `review-plan`: số lượng theo nhóm và vị trí/ID cue/caption,
  tối đa 5.000 vị trí; bước import ghi số marker thực tế. Không ghi lý do chứa
  lời nói, chữ caption hoặc đường dẫn media vào log này. Giữ sau khi dọn job.

Điều kiện Auto edit cho phép bỏ hình giữ nguyên. Phần lõi dùng chung chỉ bổ sung
bảo toàn metadata; bộ lọc chữ ASR mới được bật trong luồng Chỉ tạo subtitle.
Không tự Save, Undo, xóa marker thủ công hoặc sửa caption cũ khi cài đặt.

## Kiểm chứng

Các ca hồi quy kiểm context bị chặn theo biên nguồn, chia cửa sổ, lấy đúng chữ,
không lặp mốc neo, câu lặp mơ hồ, im lặng, chữ bị nén, CTA hợp lệ, nguồn timing,
không nâng ước lượng lên DTW, chỉ dùng cảnh báo từ đầu ra cuối, cấp độ và số
thập phân, cụm dài, quyền riêng tư nhật ký, hủy/tạm dừng và bằng chứng xóa hình.

`Run-Tests.ps1 -NoWindowsIntegration` đạt **48 nhóm**, parse **118 script**;
sáu nhóm tích hợp Windows được runner bỏ qua. Log cuối
`.tmp-marker-safety/suite-release.log`. Sau bổ sung guard không ghép số thập phân
thành số nguyên khác giá trị, chạy lại nhóm safety, caption DTW và auto acoustic
đều đạt. Điều kiện xóa hình không được nới; timing không đủ căn cứ vẫn yêu cầu nghe lại.

Harness dùng chính các hàm production của run-captions với FFmpeg/Whisper CPU
small trên năm vùng audio thật đã dựng ngoại tuyến từ project. Năm vùng lỗi cũ
không sinh lại câu quảng cáo/chào/lạc đề; phần ngữ cảnh thuộc SRT bên cạnh không
bị thêm lặp. Audio cảm ơn/hội viên thật vẫn giữ 28 từ nhận diện trong cửa sổ 8 giây.
Kiểm lại 23 khoảng nghỉ thật đều được bộ phân loại khoảng nghỉ mới nhận đúng.

Đây là kiểm ngoại tuyến trên các vùng hồi quy, không phải chạy lại toàn bộ
675 caption trong Premiere. Không áp lại hiệu ứng/mix Premiere, chưa xác nhận
số marker cuối của lần chạy mới; không đặt mục tiêu ép marker về 0. Thử bản mới
trên sequence sao chép và nghe lại các marker còn lại trước khi nghiệm thu.

Cài khi Premiere/helper thông báo đã đóng. Dữ liệu/cache/model/jobs/backups
được giữ khi cập nhật; cài đặt không tự sửa các caption/marker đã tạo trước đây.

## Đóng gói và cài đặt đã xác minh — 17/10/2026

Gói `dist/Premiere-Voice-Sync-2.20.57-Panel.zip`: **488.761.430 byte**
(466,12 MiB), SHA256:

`2B2B6C91358A74A8B1E3F0A18883311641FD810E121C1594D4B30B717EE63B31`

Đọc/đối chiếu đủ **71 entry ZIP** (70 payload và checksum manifest); runtime
khớp mã nguồn. **12 bộ VM** chạy bằng host/main/runtime của gói, **5 nhóm engine**
chạy bằng thư viện sao chép nguyên byte từ gói đều đạt. Fixture đóng gói/cài/gỡ/
rollback/registry đạt. Source hồi quy 48 nhóm/118 script, sáu nhóm Windows
integration bỏ qua theo runner; các kiểm DTW/numeric cuối cùng đạt riêng và
nhóm safety được kiểm lại bằng mã cuối trong gói.

`run-alignment.ps1`, host và diagnostic executor giữ nguyên hash so với gói
2.20.56. Các thư viện dùng chung thay phần bảo toàn/kiểm chất lượng timing và
bằng chứng định dạng số; không đổi điều kiện cho phép xóa hình. Helper/lock được
compiler dựng lại từ mã C# không đổi. Không thay runtime model hoặc các bộ cài.

Cài thật từ **2.20.56** khi Premiere/helper đã đóng: **62/62 file panel** khớp
gói; **2.035 file dữ liệu/24 thư mục** trong LocalAppData/PremiereVoiceSync giữ
nguyên hash/cấu trúc. Registry CEP giữ nguyên; cài với SkipRegistry và không
bỏ kiểm tra process. Shortcut thông báo và helper-lock được xác minh, không chạy helper.

Bằng chứng: `dist/_installation-2.20.57-20261017T041341Z/verified.json`.
Panel cũ đã sao lưu/kiểm hash tại `previous-panel` cùng thư mục. Gói ZIP không
thay đổi sau cài. Bằng chứng kiểm gói tại `.tmp-marker-safety/package-verified.json`,
`package-tests.log`, `package-engine-tests.log`, `installer-tests.log`;
audio hồi quy tại `real-media-final/verified.json`, `real-quiet-gaps.json`
trong cùng thư mục. Phần trạng thái cài đặt này được bổ sung vào tài liệu
repository sau khi đã đóng gói, không sửa ZIP.

Project gốc giữ nguyên SHA256 của lần kiểm tra; không mở/đóng Premiere, nhập
caption, sửa marker, Play, Undo hay Save. Nghiệm thu toàn bộ sequence trong
Premiere vẫn chờ người dùng; không suy số marker của lần chạy mới từ các kiểm ngoại tuyến.
