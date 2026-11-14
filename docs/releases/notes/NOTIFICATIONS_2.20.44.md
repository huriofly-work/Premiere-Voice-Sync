# 2.20.44 — đo từng phần của bước xuất audio

Người dùng xác nhận xuất WAV thủ công cùng vùng 33 phút 38 giây chạy ngay, nhưng tool đôi lúc dừng ở Encoding 0% rất lâu rồi mới xuất. Lượt 2.20.43 ngày 16/10/2026: audio-export bắt đầu 10:52:02.901, WAV được tạo 10:54:29.961, ghi xong 10:54:37.939, host trả về trước bước alignment lúc 10:54:38.794. Có khoảng 147 giây trước khi tạo WAV và khoảng 8 giây ghi file. Thời điểm tạo file chưa xác định được lệnh native đã bắt đầu từ lúc nào.

## Phép đo mới

Giữ preset, phạm vi, track voice và cách xuất sequence. Không thêm thời gian chờ, timeout, retry hay thay thuật toán subtitle của 2.20.43.

Log Workflow hiện có thêm các cặp `audio-export-start` / `audio-export-end`, gồm:

- `prepare`: tổng thời gian panel chờ begin; `hostMilliseconds` là phần bên trong ExtendScript chuẩn bị mute/In/Out.
- `yield`: thời gian thực tế của timer CEP đặt 100 ms. Nếu timer bị trì hoãn, giá trị thực sẽ thể hiện độ trễ đó.
- `render`: tổng thời gian panel chờ advance; `hostMilliseconds` là phần bên trong host; `nativeMilliseconds` là riêng lời gọi exportAsMediaDirect; `finalizeMilliseconds` là khôi phục mute/In/Out và hậu kiểm nếu thực hiện ở lượt này.
- `abort`: thời gian panel chờ khôi phục sau lỗi truyền thông/yêu cầu dừng.

Mỗi sự kiện có giờ UTC để đối chiếu với log Premiere/CEP; số vùng tính từ 0. Chỉ ghi các số hữu hạn không âm và các tên pha cố định. Không ghi lời nói, tên sequence/media, đường dẫn media hay nội dung lỗi native vào log tự động. Nếu ghi log lỗi, tác vụ vẫn tiếp tục. Native ném lỗi vẫn giữ phép đo trong finally. Hủy/tạm dừng và guard phiên/lượt/snapshot đang có được giữ.

## Cách đọc

- `nativeMilliseconds` lớn gần toàn bộ khoảng chậm: thời gian nằm bên trong API xuất của Premiere; vẫn có thể là tương tác với mute/In/Out, plugin hoặc trạng thái host, không đồng nghĩa PC yếu hay GPU hỏng.
- `hostMilliseconds` nhỏ nhưng thời gian panel chờ lớn: nghi phần xếp hàng/thực thi CEP, gọi bootstrap hoặc giao callback. Hiệu hai phép đo là thời gian ngoài thân API host, chưa tách riêng được từng nguyên nhân trong nhóm này.
- `yield` lớn hơn nhiều 100 ms: vòng lặp CEP/timer bị trì hoãn.
- Chuẩn bị hoặc finalize lớn: kiểm phần đọc snapshot, mute/In/Out hoặc khôi phục tương ứng.

Hai đồng hồ Date của panel/host chỉ là phép đo wall-clock, có độ phân giải và ảnh hưởng khi đồng hồ hệ thống thay đổi. Nếu native không trả về hoặc ứng dụng bị tắt, chỉ có sự kiện start của panel; chưa có nativeMilliseconds để kết luận vị trí bên trong host. Không gửi lệnh dò/timeout/export lặp vào Premiere đang kẹt.

## Kiểm chứng

Test host dùng đồng hồ giả kiểm native 8 giây, tổng host và finalize, kể cả native ném lỗi. Test panel kiểm đầy đủ thứ tự sự kiện, giữ begin/yield/advance/abort và không để logger lỗi làm hỏng workflow. Test logger kiểm bộ lọc số/pha, dữ liệu riêng tư và chỉ ghi khi stage audio-export đang hoạt động. Các phép mô phỏng không chứng minh đã hết kẹt Encoding 0%.

Sau khi cài và mở lại Premiere, chạy Chỉ tạo subtitle trên cùng vùng. Log lưu tự động trong `%LOCALAPPDATA%\PremiereVoiceSync\Logs\Workflow_*.jsonl`. Một lượt nhanh và một lượt chậm với cùng vùng/track/preset sẽ cho phép đối chiếu trực tiếp mà không cần đổi cache hoặc cấu hình GPU.

Kiểm tự động ngày 16/10/2026: `Run-Tests.ps1 -NoWindowsIntegration` đạt 41 nhóm, parse 110 script PowerShell; sáu nhóm tích hợp Windows theo runner được bỏ qua. TEMP/TMP dùng thư mục fixture trong workspace, lượt chạy ngoài sandbox phục vụ ca junction. JS syntax, generator parity, host/UI export timing và bộ lọc metrics đều đạt. Sau khi người dùng xác nhận lưu/đóng Premiere, đã cài bản đo; chưa có lượt native thu log 2.20.44.

Cài đặt đã xác minh: 60/60 file panel đúng manifest; 765 file/24 thư mục dữ liệu và 409 file/8 thư mục project giữ nguyên qua hash; registry CEP không đổi. ZIP đã kiểm 68 file payload, SHA256 910C17F8DBE2FE0C418F8C7EEFDCE0509E208FA96CCAC1F0DD9F02997389BFDA. Bằng chứng: `dist/_installation-2.20.44-20261016-110804/verified.json`. Không mở/đóng Premiere hoặc tự chạy thêm caption.
