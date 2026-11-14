# Premiere Voice Sync 2.20.58 — bỏ marker giữ chữ SRT khớp phần lớn

Theo yêu cầu người dùng, không tạo marker “Giữ chữ SRT khớp phần lớn”. Thông tin
đối chiếu vẫn có trong dữ liệu báo cáo và thống kê/vị trí trong workflow log.
Giữ nguyên cảnh báo độc lập về timing, số, ASR bổ sung và chữ SRT khác nhận diện.

Kiểm tra toàn bộ lần chạy 2.20.57: 137 marker/671 caption. Bỏ riêng 72 lý do
giữ chữ SRT sẽ còn 65 marker/69 lý do trên dữ liệu đã lưu; chưa phải số đo
của một lượt chạy native mới. Chi tiết lỗi còn lại và hướng sửa nằm trong
`docs/releases/notes/MARKER_AUDIT_2.20.57.md` của repository.

Bản này chỉ thay quy tắc tạo marker; không sửa lỗi lặp/mất chữ tại biên
ngữ cảnh hoặc chính sách thay SRT bằng ASR. Kiểm hồi quy marker, log và đối
soát marker phải đạt trước khi đóng gói. Cài đặt không sửa project đã lưu;
marker cũ được đối soát ở lần chạy sau trong phạm vi tương ứng.

## Kết quả kiểm chứng và cài đặt

Gói đã kiểm 71 entry ZIP (70 payload + manifest), khớp nguồn; 12 bộ kiểm VM
chạy với runtime lấy từ gói đạt. Kiểm marker/log/repository và phát lại 141 lý
do từ project thật đạt: 65 marker/69 lý do, không lỗi đối soát trong mock.
Không chạy lại engine nhận diện vì không thay thư viện/engine.

Đã cài từ 2.20.57 sau khi người dùng xác nhận đóng Premiere/helper:
62/62 file panel đúng hash; giữ nguyên 2.401 file dữ liệu/22 thư mục,
registry CEP không đổi, có bản sao panel cũ. Không chạy helper, điều khiển
Premiere hay sửa project. Hash project sau cài vẫn bằng lúc bắt đầu kiểm tra.

ZIP SHA256: `20B76CA436639F4E9BC2FC30CDC08D6BDC800E306B821EE991B9BBA8789A0E96`.
Bằng chứng cài: `dist/_installation-2.20.58-20261017T043409Z/verified.json`.
Bằng chứng gói/phát lại: `.tmp-marker-audit-2.20.57/package-verified.json`,
`package-tests.log`, `saved-marker-replay.json`. Mục kết quả này được bổ sung
vào tài liệu repository sau khi đóng gói, không sửa ZIP đã cài.
