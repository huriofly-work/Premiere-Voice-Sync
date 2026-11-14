# Premiere Voice Sync 2.20.66 — nguồn SRT và audio gọn hơn

## SRT đơn và nối nhiều file

Hai chế độ dùng chung vị trí **File SRT**. Nút bật **Nối nhiều file SRT** đặt ngay cạnh phần chọn một SRT. Khi bật, chỉ giữ SRT đơn hiện tại nếu có; không tự thêm tất cả file trong Project.

- **Chọn từ Project** mở danh sách có tìm tên và checkbox cho từng file. Tick để thêm, bỏ tick để bỏ; các file trùng đường dẫn được gộp. File cùng tên ở các thư mục khác nhau được phân biệt bằng thư mục.
- **Chọn từ máy** thêm nhiều file ngoài Project.
- **Danh sách đã chọn · N file** mặc định thu gọn. Mở để xem thứ tự, dùng ↑/↓ để đổi và × để bỏ. Danh sách Project, danh sách đã chọn và danh sách track đều có chiều cao giới hạn, cuộn bên trong.
- Quét lại/nhập thêm file không tự thêm hoặc khôi phục file người dùng đã bỏ. Tắt nối khôi phục lựa chọn đơn; lựa chọn nối của hai chế độ độc lập. Cách nối thời gian nằm trong phần mở rộng riêng; giữ kiểm chồng/đảo thời gian và snapshot SRT tạm như trước.

## Audio mặc định

Ở chế độ tạo phụ đề, mặc định **Tự động**. Chương trình đọc selection khi cập nhật đầu vào và khi bấm chạy:

1. Có clip audio được chọn: dùng chính các clip đó, theo khoảng thời gian của chúng; không lấy toàn track.
2. Chỉ có clip video được chọn: dùng khoảng selection với track gợi ý; tóm tắt hiển thị rõ track thực sự được dùng.
3. Không có selection: dùng toàn sequence, ưu tiên A2 có audio trong phạm vi rồi track đầu có audio. Đây là gợi ý theo cấu trúc, không phải phân loại voice/nhạc.

Clip chỉ bị disabled hoặc không xác minh được danh tính không khiến chương trình tự chuyển sang audio khác. Nguồn/phạm vi thực tế được hiển thị trong tóm tắt.

Muốn tự chọn, mở **Đổi nguồn hoặc phạm vi audio**. Các lựa chọn chi tiết và danh sách track mặc định thu gọn. Nguồn tự chọn không bị selection mới ghi đè; chọn lại **Tự động** để bám selection. Job gửi host vẫn dùng hợp đồng clips/tracks/mix và phạm vi rõ ràng hiện có; sau khi tạo job, đổi selection không đổi nguồn job. Giữ kiểm mute/disabled/topology/identity, khôi phục mute/enable/In/Out và khóa phục hồi sau lỗi.

## Kết quả rà soát ưu tiên SRT

Cả **Dựng theo voice** và **Tạo phụ đề** đều quét SRT trong Project độc lập với việc timeline có đủ điều kiện dựng hay không. Một file duy nhất hoặc một ứng viên có điểm ưu tiên rõ hơn được tự chọn; nhiều ứng viên ngang điểm thì hiện hướng dẫn chọn, không đoán file bất kỳ. Điểm ưu tiên dùng dấu hiệu ngôn ngữ và tên voice khi có dữ liệu đó, không phải kiểm nội dung SRT đã khớp âm thanh.

Giữ lựa chọn SRT thủ công và lựa chọn tự nhận diện không SRT trong luồng phụ đề. Đợt này bổ sung giữ SRT thủ công ở luồng dựng trong phiên hiện tại: quét lại không ghi đè file ngoài vừa chọn bằng file Project. Việc kiểm SRT đúng nội dung/ngôn ngữ và phạm vi vẫn thực hiện khi chạy.

## Kiểm chứng và giới hạn

Kiểm hồi quy bao phủ chọn từng Project SRT, tìm tên, danh sách thu gọn, không tự thêm hàng loạt, thứ tự và snapshot job, ưu tiên SRT ở hai luồng, chọn ngoài/ASR-only, mặc định selection audio/video, đổi selection, giữ nguồn thủ công, disabled và ID không xác minh. Kiểm trình duyệt riêng có dữ liệu mô phỏng ở 320/385/560 px, thêm 40 SRT/30 track để kiểm cuộn và tràn ngang.

52 nhóm hồi quy đạt và parse 122 script PowerShell; sáu nhóm tích hợp Windows được bỏ qua. Bố cục ở ba độ rộng, tìm tên/checkbox/reorder, danh sách dài 40 SRT/30 track và giới hạn chiều cao/không tràn ngang đều đạt trong trình duyệt mô phỏng. Bằng chứng nằm trong `.tmp-input-2.20.66/suite.log`, `preview-final.log` và `preview-final/`. Không sửa thuật toán engine/host, không tự chạy Premiere, Save hoặc Undo. Kết quả kiểm gói/cài đặt được ghi sau khi hoàn tất; nghiệm thu selection/export/import/Play/Save thực tế trong Premiere còn chờ người dùng.

## Gói phát hành

70 tệp payload/71 mục ZIP khớp checksum và mã nguồn. 20 bộ kiểm trên mã đóng gói đạt; 48 tệp engine/host khớp 2.20.65. Bằng chứng: `.tmp-input-2.20.66/package-verified.json` và `package-tests.log`.

ZIP SHA256: `2769509DCF684A5F8DE5C087E2C5F081CC93839F131A4F27E78ED0F2415D9A93`.

Đã cài từ 2.20.65 lúc 18:18 ngày 17/10/2026 (UTC+7), sau khi người dùng lưu và thoát hẳn Premiere. 62/62 tệp panel khớp gói; giữ nguyên hash 3.640 tệp dữ liệu/22 thư mục và registry CEP. Bản sao panel cũ cùng bằng chứng nằm tại `dist/_installation-2.20.66-20261017T111816Z/previous-panel` và `verified.json`. Không mở helper hoặc thao tác project. Gói ZIP đã kiểm được giữ nguyên; phần bằng chứng cài đặt này được bổ sung sau build. Nghiệm thu native vẫn chờ người dùng.
