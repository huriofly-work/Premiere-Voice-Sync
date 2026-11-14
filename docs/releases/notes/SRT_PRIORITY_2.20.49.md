# 2.20.49 — ưu tiên SRT trong Project cho Chỉ tạo subtitle

Chỉ tạo subtitle tự chọn SRT khi Project chỉ có một file hoặc một ứng viên được xếp hạng cao hơn rõ ràng, cùng quy tắc với Dựng theo voice. Nhiều file ngang nhau thì hiển thị hướng dẫn chọn. Kiểm tra file đúng ngôn ngữ và nội dung lời nói trước khi chạy.

Lựa chọn thủ công được giữ qua cập nhật đầu vào và chuyển chế độ trong phiên panel, gồm cả chọn file ngoài và Tự nhận diện · không dùng SRT. Kết quả quét không ghi đè lựa chọn vừa thực hiện trong lúc chờ. SRT tự chọn đã rời Project được xét lại ở lượt quét sau.

Gói kế thừa payload 2.20.48 đã kiểm checksum rồi chỉ cập nhật lựa chọn SRT, hướng dẫn và phiên bản. Giữ bản sửa marker của 2.20.48. Phần nguồn audio/phạm vi đang phát triển trong working tree không được đưa vào gói này.

Kiểm hồi quy lựa chọn SRT chạy trên chính mã main.js của payload phát hành, gồm một file, điểm ưu tiên, tên voice, nhiều file ngang nhau, Project rỗng/import sau đó, chọn thủ công/file ngoài/không SRT, chuyển chế độ, chọn lúc đang quét, SRT tự chọn bị gỡ và giữ lựa chọn còn trong Project. Đây là kiểm mã/mô phỏng, chưa xác nhận thao tác thực trong Premiere.
