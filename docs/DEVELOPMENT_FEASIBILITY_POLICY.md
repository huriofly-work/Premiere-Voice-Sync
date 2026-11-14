# Khảo sát khả năng thực thi trước khi phát triển

Yêu cầu của user ngày23/10/2026: trước khi phát triển chức năng gì cũng phải
khảo sát khả năng thực thi trước; không phát triển mù quáng rồi cuối cùng mới
phát hiện không thực thi được. Áp dụng cho mọi chức năng của project.

1. Xác định hành vi cần có, platform/version thực tế, API/quyền truy cập và
   các điều kiện bắt buộc. Tách điều đã biết khỏi giả định.
2. Rà tài liệu/mã nguồn/lịch sử và bằng chứng thực thi còn phù hợp. Có API
   cùng tên, type declaration, plan ngoại tuyến hoặc synthetic test chưa đủ
   chứng minh hoạt động trên host. Dùng lại bằng chứng phù hợp, không lặp
   khảo sát vô ích cho một cơ chế đã xác minh cùng điều kiện.
3. Nếu một khả năng cốt lõi chưa được chứng minh, chỉ làm phép thử khả thi nhỏ
   nhất có thể kiểm được đường thực thi đầy đủ. Chưa mở rộng feature code,
   UI, kiến trúc phụ thuộc hoặc benchmark trước cổng này. Phép thử native vẫn
   phải đúng scope/giới hạn đã được cho phép và giữ dữ liệu nguồn.
4. Ghi rõ kết quả: đã xác minh trong điều kiện nào; chỉ là ứng viên/chưa kiểm;
   hoặc không khả dụng trong phạm vi đã khảo sát. Không suy “bất khả thi với
   mọi API/phiên bản” chỉ từ tài liệu thiếu hoặc một probe không thấy method.
5. Chỉ triển khai phần phụ thuộc khi cơ chế cần thiết đã được chứng minh.
   Nếu chưa có đường khả thi, dừng phần phụ thuộc, giải thích bằng chứng/giới
   hạn và thống nhất lại yêu cầu hoặc giải pháp trước khi tiếp tục. Không tự
   hạ yêu cầu, thay loại đầu ra hoặc bật fallback để làm kết quả có vẻ đạt.

Không tạo thêm bước duyệt cho thay đổi thường lệ đã được user cho phép. Cần
thống nhất lại khi phải đổi yêu cầu/đầu ra, hoặc khi phép thử cần quyền ngoài
scope hiện có. Code chuẩn bị hữu ích được giữ như nghiên cứu tạm hoãn; số
test đạt không tự biến nó thành chức năng thực thi được.

Với big update, Q17 hiện hành
do user yêu cầu quay lại chọn file SRT. W0 direct writer cũ
vẫn chưa qua nhưng không còn là điều kiện của đường chính đã đổi yêu cầu;
không sửa kết quả lịch sử thành PASS. File input/snapshot và SRT tự nhập,
style/scope, hình/voice/marker phải có proof riêng phù hợp trước phần phụ thuộc.
