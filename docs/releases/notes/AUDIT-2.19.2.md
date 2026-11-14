# Rà soát 2.19.2

## Đã sửa trong bản ổn định

- Mặc định 110% tồn tại đồng thời trong HTML và JavaScript; dữ liệu localStorage cũ còn khiến giao diện tiếp tục hiện 110% sau nâng cấp. Đã thống nhất 130% và thêm migration một lần.
- Nút Đọc lại và lần quét đầu nuốt lỗi hoàn toàn. Đã ghi lỗi rõ vào nhật ký/trạng thái sequence.
- Tóm tắt sequence dùng gap cố định 2 giây dù người dùng có thể đổi gap nhóm voice. Đã hiển thị số clip A2 trung tính; Chẩn đoán tính chapter bằng đúng thiết lập hiện hành.
- Thư mục engine trộn test, công cụ thủ công và thuật toán clamp đã nghỉ hưu. Đã tách khỏi cây cài đặt và khỏi test ổn định.
- Hai script mang tên test phụ thuộc fixture/temp tùy ý nên làm bộ chạy toàn phần báo lỗi giả. Đã chuyển thành công cụ thủ công có tham số bắt buộc.
- Repository chưa có một lệnh test chuẩn hoặc GitHub check. Đã bổ sung cả hai.

## Cố ý không thay đổi

- Không đổi schema 8, planner revision 10, executor 25, công thức tốc độ, quy tắc silence, mapping A2, marker, caption hoặc tail shift.
- Không tách `host.jsx` trong nhánh ổn định vì thay đổi ranh giới nạp ExtendScript có rủi ro lớn hơn lợi ích ở Premiere 26.2.2.
- Không thêm dấu câu, mô hình nhận diện hoặc chiến lược retime mới vào production.

## Đề xuất cho nhánh thử nghiệm riêng

- Đánh giá dấu ba chấm `…` như dấu kết câu bằng bộ dữ liệu thật trước khi thay đổi grouping.
- Thử cache Whisper có xác thực/ghi atomic và đo chênh lệch thời gian trên nhiều video.
- Xây fixture Premiere dành riêng cho outro, adjustment layer và transition trước khi thay đổi quy tắc tail shift.
- Cân nhắc xuất gói chẩn đoán đã ẩn đường dẫn cá nhân khi cần hỗ trợ từ xa.
