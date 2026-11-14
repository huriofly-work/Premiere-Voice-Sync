# Premiere Voice Sync 2.20.54 — nối nhiều SRT

Theo yêu cầu ngày 17/10/2026, các SRT được nối thành một SRT để nhận diện chung qua engine hiện có.

## Cách dùng

1. Bật **Nối nhiều SRT thành một**. SRT đang chọn được thêm làm file đầu nếu danh sách còn trống.
2. **Chọn nhiều file ngoài**, hoặc chọn từng SRT trong Project phía trên rồi bấm **Thêm SRT đang chọn**.
3. Kiểm tra thứ tự từ trên xuống; dùng **Lên**, **Xuống**, **Bỏ**.
4. Chọn cách nối timestamp rồi chạy nút hiện có. Cue được đánh số lại liên tục; giữ nội dung nhiều dòng, dấu tiếng Việt. Đường dẫn trùng không được thêm lần nữa.

**Giữ timestamp gốc:** giữ nguyên thời gian, yêu cầu cue/file đúng thứ tự và không chồng nhau. Mặc định của Dựng theo voice vì mốc SRT phải khớp hình nguồn.

**Nối tiếp thời gian từng file:** file đầu giữ nguyên mốc; từng file sau được cộng thời gian kết thúc phần đã nối, giữ khoảng nghỉ đầu file. Ví dụ phần trước kết thúc 40 giây, cue đầu file sau tại 1 giây thì thành 41 giây. Mặc định của Chỉ tạo subtitle; timestamp đầu ra vẫn căn theo audio. Khi dựng hình, chỉ dùng nếu mốc sau nối thực sự khớp hình nguồn: thời gian kết thúc subtitle không xác định được độ dài video.

## Xử lý

Kiểm và đọc toàn bộ file thành bản chốt trước khi xuất audio/dựng. Thiếu file, cue lỗi, thiếu chữ, thời lượng không dương hoặc mốc chồng/đảo được báo tại ô nối SRT. Một `reference-joined.srt` UTF-8 được ghi trong job và truyền qua `targetSrtPath`; thuật toán nhận diện, planner, pause/stop và bước áp dụng timeline giữ nguyên. Bản chốt không phụ thuộc việc sửa SRT gốc trong lúc chạy. File tạm được dọn bằng cơ chế hiện có; file gốc giữ nguyên.

Lựa chọn nối và thứ tự file tách riêng giữa hai chế độ trong phiên panel. Tắt ô nối để trở về một SRT hoặc nhận diện không SRT như trước. Marker/log dùng số cue của SRT đã nối.

## Kiểm chứng

Kiểm tự động gồm nối hai/ba file, thứ tự và số cue, tiếng Việt/nhiều dòng, BOM/CRLF, mốc toàn cục/cục bộ, lỗi từng file, sắp/bỏ file, đường dẫn trùng, khóa khi bận và cả hai luồng main.js đến trước thao tác native. Bộ hồi quy đạt 46 nhóm, parse 115 script PowerShell; sáu nhóm Windows integration được bỏ qua theo runner. Log: `.tmp-srt-join/suite-verified.log`. Phép thử giao tiếp Node → file UTF-8 → bộ đọc SRT PowerShell hiện có cũng đạt.

Bố cục browser fixture đạt ở 320/385/560 px, cả hai chế độ, danh sách ba SRT/tên dài, đổi thứ tự và không tràn ngang. Ảnh tại `.tmp-srt-join/ui`. Gói `dist/Premiere-Voice-Sync-2.20.54-Panel.zip`: 466,11 MiB, SHA256 `5328B3F15B0EE1E4E97AA546CCA087B9B18C3F196201EBAEB64343787FED1DCF`. Payload đã kiểm allowlist/checksum; chưa nghiệm thu native.

Chưa nghiệm thu audio, caption hoặc dựng thật trong Premiere. Khi thử thực tế, dùng SRT/voice đúng thứ tự; kiểm chữ và timestamp quanh điểm nối, rồi kiểm Preview/Play và Save.

Đã cài 2.20.54 lúc 09:21 ngày 17/10/2026 (UTC+7), từ 2.20.53. 62/62 file panel đúng checksum; 1.127 file dữ liệu/24 thư mục giữ nguyên theo hash/cấu trúc; registry CEP giữ nguyên. Panel cũ được sao lưu; bằng chứng tại `dist/_installation-2.20.54-20261017-092145/verified.json`. Premiere/helper đã đóng khi cài; không mở/đóng hoặc thao tác project.
