# Bảo mật và quyền riêng tư

Áp dụng cho bản 2.20.4 đang nghiệm thu, kế thừa bảo vệ của 2.20.0. Không phải chứng nhận bảo mật hoặc kiểm toán độc lập.

## Biện pháp đã triển khai

- ZIP build từ allowlist chính xác, không lấy `.git`, tài khoản GitHub, cấu hình runtime cục bộ, media, project, cache hoặc log của người phát hành. Config build trung tính, runtime/model theo SHA-256 cố định.
- Setup bắt buộc checksum cho tất cả file trong danh sách, từ chối file thừa/thiếu, traversal/ADS, hash sai, symlink/junction và liên kết trên đường dẫn cha. File staging được đối chiếu lại trước khi thay panel. Lỗi trong bước thay panel cố khôi phục bản cũ và trạng thái trước cập nhật.
- Gỡ chỉ exact extension ID đã kiểm manifest và vùng dữ liệu riêng có deployment marker. Không dò tên hiển thị hoặc wildcard TEMP. Khôi phục PlayerDebugMode có điều kiện để không ghi đè lựa chọn mới của ứng dụng/người dùng khác.
- CPU runtime, model và DLL được đối chiếu runtime-lock; GPU archive khóa version/URL/hash, tải HTTPS và kiểm từng DLL/CLI trước chạy. DLL thừa bị từ chối vì Whisper tự nạp backend. GPU hỏng không được thực thi, dùng CPU kèm lý do.
- GPU download mặc định tắt, người dùng bật rõ ràng. Mạng chỉ dùng tải tài nguyên, không tự upload media/project/log. Khởi chạy native bằng đường dẫn tuyệt đối, không tìm executable qua PATH, không dùng shell nối chuỗi tham số.
- Xóa cache nhận diện với xác nhận, giữ model/backend. Log xuất đã lọc dữ liệu riêng được biết; không tự upload và phải đọc lại trước chia sẻ.
- Không yêu cầu admin cho hoạt động/cài panel; không tắt Defender/SmartScreen, không thêm exclusion, không thay PATH hoặc ExecutionPolicy toàn hệ thống.
- CI permissions contents:read, checkout khóa commit; regression và negative tests bảo mật chạy trên fixture riêng. Thử nghiệm ký CEP không có trong payload production.

## Ranh giới bảo vệ

Checksum nội bộ chỉ phát hiện gói hỏng/thay đổi một phần, không chống người thay cả ZIP và script/checksum. Phải lấy ZIP từ nguồn đúng và đối chiếu whole-ZIP SHA-256 qua ghi chú Release/kênh tin cậy trước chạy Setup. Việc self-check sau khi chạy script không thay thế bước xác minh đó.

CEP hiện tại chưa ký, vẫn dùng PlayerDebugMode và Node filesystem/native-process access. CSP chặn connect/frame/object ngoài nhưng không tạo sandbox cho Node. Không bảo vệ trước malware/admin hoặc người có quyền sửa mã, manifest/lock và dữ liệu cùng tài khoản; path checks không phải biện pháp chống mọi cuộc đua filesystem (TOCTOU). Vì vậy không khẳng định an toàn 100%.

Whisper/FFmpeg là binary bên thứ ba. Hash khóa đúng bản đã dùng không chứng minh binary không có lỗ hổng. Với media không rõ nguồn, nên thử trong tài khoản Windows thường/VM và giữ antivirus bật. Nâng runtime cần nguồn chính thức, hash mới đã xác minh, rà soát notice/license và regression riêng, không tự thay latest.

Cache có lời nhận diện/timestamp; log lỗi có thể chứa nội dung riêng. Bộ lọc không phải DLP toàn diện và không tự che mọi câu nói/tên riêng. Dùng dữ liệu công khai khi báo lỗi; đọc log trước gửi. Chia sẻ ZIP build, không chia sẻ toàn thư mục làm việc hoặc thư mục AppData.

## Chữ ký CEP

Thử nghiệm fixture dùng cơ chế ký/xác minh của [Adobe](https://github.com/Adobe-CEP/Getting-Started-guides/tree/master/Package%20Distribute%20Install). Không cài chứng chỉ vào Windows Trusted Root, không phát hành private key và không tắt debug của production. Cần thử panel thật trên Premiere 26 với debug tắt, timestamp/hết hạn và máy sạch trước khi chuyển. Chữ ký không xác nhận mã an toàn; tự ký cũng không tự xác minh danh tính người phát hành.

## Trước khi chia sẻ rộng rãi

1. PASS regression/negative tests và nghiệm thu hai workflow trong Premiere thật.
2. Build exact ZIP, quét ZIP/thư mục giải nén; ghi kết quả scan, không bỏ cảnh báo hay thêm exclusion.
3. Nghiệm thu tài khoản/máy Windows sạch có file sentinel ngoài scope, offline CPU và GPU consent.
4. Công bố whole-ZIP SHA-256 qua kênh tin cậy. Không tự merge/release khi chưa được duyệt.
5. Chỉ chuyển sang signed CEP sau vòng nghiệm thu riêng. Giữ khóa phát hành ngoài Git và payload; có phương án mất/hết hạn khóa.

## Kiểm chứng cục bộ

Ngày 2026-10-04: 15 nhóm unit/regression PASS, trong đó kiểm bảo mật gồm 14 trường hợp PowerShell và 12 trường hợp Node. Fixture lỗi rename đã khôi phục panel cũ, giữ deployment-mode và không còn staging. Pipeline subtitle chạy thực trên CUDA và CPU bằng audio tổng hợp, cả tự nhận diện và SRT tham chiếu. Vùng dữ liệu mới không tự tải GPU; executable GPU giả sai hash bị từ chối trước khi chạy và có lý do dùng CPU. Chữ ký fixture ZXP/thư mục đã giải nén được xác minh; sửa HTML làm xác minh thất bại. Các kết quả này không phải nghiệm thu playback/timeline Premiere hoặc máy Windows sạch. Kết quả quét antivirus và lần build cuối được báo riêng khi hoàn tất.

Bản panel cục bộ đã cập nhật trong khi Premiere đóng; 40 file vận hành khớp gói build, 158 file cache/model/backend giữ nguyên hash, kích thước và thời điểm sửa. Không có mục Installed apps. Defender đang bật đã quét ZIP/thư mục payload với signature 1.459.540.0, không ghi nhận phát hiện mới; không phải chứng nhận an toàn. Thuật toán executor/planner/alignment/caption không đổi so với commit đầu lượt rà soát này. Nghiệm thu thao tác/playback thật trong Premiere và máy Windows sạch vẫn chưa thực hiện.
