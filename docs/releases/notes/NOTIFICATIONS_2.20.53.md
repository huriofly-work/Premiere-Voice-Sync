# Premiere Voice Sync 2.20.53

Sửa phép so nguồn/phạm vi audio giữa CEP và ExtendScript. Trước đây host so nguyên chuỗi JSON của kế hoạch và so số giây bằng bằng tuyệt đối, nên cùng vùng frame có thể bị từ chối nếu hai runtime ghi số khác độ chính xác hoặc thứ tự thuộc tính khác nhau.

So dữ liệu đã parse: project, sequence, snapshot, nguồn, tập track/clip, mute/disabled và phần bỏ qua phải trùng; mốc thời gian suy ra được kiểm trên cùng lưới frame. Mốc không nằm trên lưới hoặc khác một frame vẫn bị từ chối. Không bỏ kiểm thay đổi nguồn và không tự đổi track/phạm vi.

Đã tái hiện thông báo người dùng bằng fixture có planner CEP riêng và serializer host ghi số với 15 chữ số có nghĩa. Kiểm 30/29,97/23,976 fps, nguồn mix/tracks/clips, JSON khác định dạng/thứ tự và các thay đổi thật phải bị chặn trước mutation. Đây là mô phỏng khác biệt runtime; chưa lấy được cặp key native của lần lỗi để xác nhận nguyên nhân tại project người dùng.

Kế thừa sửa bootstrap/UTF-8 2.20.52. Khi cài, lưu công việc và đóng Premiere/helper theo chốt bộ cài. Sau cài mở lại, xác nhận 2.20.53, Cập nhật đầu vào rồi thử lại. WAV/ASR/caption thực tế còn cần nghiệm thu.

Kiểm chứng 17/10/2026: 45 nhóm đạt, parse 114 script; sáu nhóm Windows integration được bỏ qua. Log .tmp-audio-key/suite.log. Syntax ES3 host/model và generated-source check đạt. Đã cài lúc 08:41 sau khi người dùng đóng ứng dụng; 61 tệp cài đúng checksum, giữ nguyên 925 tệp/24 thư mục dữ liệu và registry CEP. Sao lưu panel cũ và bằng chứng: dist/_installation-2.20.53-20261017-084104/verified.json. Gói ZIP SHA256: 1CFBFA876A69F822B1FFE0D3FDD01FC0F982772FBDC4430AA39FB2679C13FE7B. Chưa chạy native trong project.
