# 2.20.38 — dừng tác vụ đang chạy

Nút **Dừng tác vụ** xuất hiện khi Dựng theo voice hoặc Chỉ tạo subtitle đang chạy, kể cả kiểm đầu vào. Bấm một lần để yêu cầu dừng. Nút chuyển thành **Đang yêu cầu dừng…**, giữ khóa tác vụ đến khi các thao tác đang chờ đã trả về và file tạm được dọn. Không dùng đóng panel làm cách hủy.

- Phân tích/Whisper/FFmpeg: kết thúc nhóm tiến trình của lượt hiện tại, chờ mọi thành viên thoát rồi dọn file tạm. Cache/model/backend được giữ.
- Dựng timeline: chờ lượt native hiện tại trả về, kết thúc phiên executor và chặn lượt tiếp theo. Giữ các thay đổi đã thực hiện, không tự Undo/Save. Cần kiểm tra/khôi phục rồi xác minh đầu vào trước lần chạy mới.
- Xuất audio: chờ native export trả về, không xuất vùng kế tiếp, khôi phục mute/In/Out bằng phiên host có token. Nếu bảng Encoding còn đáp ứng, có thể hủy trong bảng đó. Panel không thể cưỡng bức ngắt một lệnh Premiere đang kẹt.
- Thêm caption: nếu import đã bắt đầu thì chờ trả về, báo timeline đã thay đổi/chưa xác minh và giữ khóa phục hồi. Không tự xóa caption vừa thêm.

Log ghi outcome `cancelled`, không hiển thị thành công giả. Lỗi xử lý hoặc lỗi khôi phục vẫn được báo lỗi; hủy không làm mất lỗi gốc. Hủy không đưa Premiere lên trước hoặc gửi thông báo Windows. Nút dừng khóa khi đã yêu cầu dừng hoặc đang dọn file tạm.

## Cơ chế tiến trình

`run-workflow.ps1` chỉ chạy năm script engine được cho phép. Worker chờ stdin; wrapper gán nó vào Windows Job Object riêng có KILL_ON_JOB_CLOSE rồi mới gửi lệnh bắt đầu. Mọi tiến trình con nằm trong nhóm. Hủy kết thúc nhóm, chờ active process về 0 rồi mới trả callback. Không kill theo tên tiến trình, không đụng Premiere hoặc tác vụ khác. Nếu không tạo/gán được nhóm thì báo lỗi, không chạy engine ngoài nhóm. Giữ nguyên script engine và thuật toán căn lời/dựng.

## Kiểm chứng

UI/VM kiểm cả hai workflow tại preflight, từng engine, đầu/giữa/cuối phiên export/dựng, import, yêu cầu dừng lặp, khóa pending và phục hồi sau mutation; lỗi restore/engine vẫn ưu tiên. Test Windows thật dùng worker/grandchild giả trong thư mục riêng để kiểm hủy và xác nhận tiến trình không liên quan còn sống. Đây là kiểm tiến trình thật với nội dung giả, chưa phải nghiệm thu trên Premiere.

Cần thử Premiere: dừng nhận diện dài; dừng giữa các stage dựng; dừng xuất WAV nhiều vùng; dừng trong khi Encoding/import đang bận; kiểm mute/In/Out, caption/bin tạm, Undo, chạy lại sau xác minh, Preview/Play/Save. Bản sửa export 2.20.37 vẫn cần kiểm riêng trên project từng kẹt Encoding 0%.
