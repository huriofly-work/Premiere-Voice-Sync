# 2.20.48 — marker số trỏ đúng caption chứa số

Người dùng báo marker `Cue 2` tại 5.090–25.348 giây nhưng gần đầu marker không có số. Mã 2.20.47 nhận danh sách cảnh báo theo số đoạn phân tích; với Chỉ tạo subtitle, nó đặt marker tại Start của toàn đoạn này. Một đoạn dài có thể tách thành nhiều caption ngắn và số nằm tận cuối đoạn. Ngoài ra, `Cue` nội bộ bị trình bày như số caption đầu ra và thông báo gợi ý đọc số sai dù engine mới chỉ thất bại khi xác minh timing.

Sửa trong 2.20.48:

- Giữ `SourceCueIndex` trên caption đầu ra sau chia nhỏ, cả Chỉ tạo subtitle và Auto edit.
- Cảnh báo số chỉ chọn các caption đầu ra có chữ số thuộc đúng đoạn cần kiểm tra. Vị trí/vùng marker dùng mép caption đó, không dùng đầu cả đoạn dài hoặc nội suy vị trí từ.
- Ghi số cần kiểm tra, nguyên văn caption và `Caption N` tương ứng SRT đầu ra; thêm `SRT N` khi có cue tham chiếu. Các cảnh báo toàn đoạn được ghi `Đoạn phân tích N`.
- Ghi rõ chưa xác minh được timing, cần nghe lại; không kết luận voice đọc sai số. Nếu không tìm được caption chứa số thì chặn trước khi thêm caption/marker, thay vì trỏ đoán vào đầu đoạn.
- Không đổi chữ, timing subtitle, cách nhận diện, retime hoặc logic sở hữu marker. Cập nhật không tự sửa marker đã ghi trong project; không tự thao tác lên project đang mở.

Gói phát hành dựng từ payload 2.20.47 đã kiểm checksum, chỉ cập nhật builder marker trong panel, ghi chú marker trong host, metadata mapping trong CaptionOnly/run-captions và số phiên bản/tài liệu. Executor chia đợt được sinh lại từ chính host của gói. Các thay đổi chưa phát hành về nguồn audio/phạm vi/tự chọn SRT trong working tree không được đưa vào gói.

## Kiểm chứng

Ca hồi quy dùng đúng khoảng ví dụ 5.090–25.348 giây, đặt số ở caption cuối: chỉ caption chứa số nhận marker; các caption đầu không có số không nhận cảnh báo số. Kiểm Auto edit, nhiều số ở các caption khác nhau, số caption/SRT nguồn và chặn dữ liệu không ánh xạ được.

Tái dựng ngoại tuyến từ 265 đoạn đã lưu cho 507 caption: SRT giống từng byte so với kết quả cũ; hai đoạn cần kiểm tra số được chuyển thành ba marker gắn caption chứa 1875, 30 và 95. Đây là kiểm dữ liệu/mã, chưa phải nghe lại voice hoặc xác nhận hiển thị marker trong Premiere.

Ngày 16/10/2026: bộ nguồn `Run-Tests.ps1 -NoWindowsIntegration` đạt 43 nhóm, parse 112 script PowerShell (sáu nhóm Windows integration bỏ qua theo runner). Log `.tmp-marker-fix/source-suite.log`. Bộ kiểm marker, executor trực tiếp/chia đợt ba profile và host subtitle cũng chạy lại trên đúng payload của gói 2.20.48, tách biệt với các thay đổi working tree chưa phát hành. Payload kế thừa 2.20.47, chỉ bảy file runtime thay đổi (gồm phiên bản và executor sinh lại); kiểm đầy đủ allowlist/checksum của chính gói.
