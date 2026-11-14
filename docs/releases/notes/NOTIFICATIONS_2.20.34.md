# Bản sửa 2.20.34 — kiểm tra caption-only trên CEP

Lỗi được báo trên project “Ý thức đến từ đâu”: chỉ tạo subtitle có SRT sẵn dừng với thông báo không đọc được trạng thái caption/In/Out, trước khi xuất audio hoặc nhận diện.

Đoạn kiểm tra của 2.20.33 truy cập thẳng `sequence.captionTracks.numTracks`. Khi CEP Sequence không có collection này, biểu thức host ném lỗi và panel chặn tác vụ. Bản sửa phân biệt API không có (số caption chưa biết) với số track thực tế bằng 0; API có nhưng trả dữ liệu sai vẫn bị chặn. In/Out, sequence, snapshot video/audio và bin tạm vẫn được kiểm tra.

CEP không cung cấp số caption thì tool không thể tự xác minh caption cũ có bị sửa trong lúc nhận diện. Không tương tác timeline trong khi chạy. Nếu lỗi sau thao tác có thể đã sửa Project, nút kiểm tra đầu vào yêu cầu xác nhận đã kiểm tra caption/bin tạm và Undo hoặc mở bản đã lưu nếu cần; sau đó vẫn đối chiếu In/Out, bin và snapshot. Không tự Undo, Save hoặc chạy lại import.

Giữ engine, chữ SRT, căn timestamp và executor dựng. Thông báo nhiều kênh kế thừa 2.20.33; xem tài liệu của phiên bản đó trong repository. Chưa nghiệm thu bản sửa trong Premiere thật.

Hồi quy riêng chạy biểu thức ExtendScript được sinh thực tế trong VM, bao gồm thiếu `captionTracks`, count hợp lệ/sai, In/Out thiếu/sai, đổi sequence, chi tiết lỗi host, SRT có sẵn và phục hồi cần xác nhận. Đây là kiểm tự động, không phải nghiệm thu tạo caption, Play hoặc Save trong Premiere.
