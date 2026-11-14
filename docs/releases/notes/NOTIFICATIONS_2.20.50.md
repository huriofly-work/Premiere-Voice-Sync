# 2.20.50 — nguồn audio và phạm vi subtitle

Chỉ tạo subtitle tách rõ nguồn audio và phạm vi thời gian:

- **Tất cả track đang bật**: xuất bản phối theo trạng thái mute hiện tại.
- **Các track chỉ định**: checkbox chọn một hoặc nhiều track, mở tiếng tạm tập track này khi xuất. Chỉ gợi ý A2/track đầu tiên có clip enabled giao phạm vi khi chưa chọn thủ công; không tự thay nguồn thủ công khi trống.
- **Chỉ các clip audio đang chọn**: lấy đúng các clip Audio đã chọn trên nhiều track, loại clip không chọn giao phạm vi trên cùng track. Clip disabled giữ disabled; không tự đoán video/audio linked là voice.
- Phạm vi **Toàn sequence**, **Theo khoảng thời gian của clip đang chọn**, **Theo In/Out**. Clip mode dùng chính thời gian của clip audio và khóa các ô không áp dụng. Kế hoạch đổi trước khi chạy được trình bày lại; selection sau khi chốt job không thay nguồn/phạm vi job.

Nhiều nguồn phối theo tọa độ timeline cho một kết quả nhận diện chung. Vùng chắc chắn không có clip audio từ nguồn đã chọn được bỏ qua và báo rõ; toàn bộ nguồn/phạm vi rỗng thì không chạy. Tool không tự thêm nguồn để có kết quả.

Resolver ES3 dùng chung panel và host kiểm cùng kế hoạch trước xuất. Staged native export giữ thứ tự/yield, không dùng timeout giả như đã hủy Premiere. Khi cô lập clip không đọc/ghi/xác minh được enable, tác vụ dừng trước render/ASR.

Nhật ký `job.json.audio-recovery.json` lưu trước mutation. Hoàn tất/lỗi/hủy khôi phục độc lập clip/mute/In/Out và kiểm baseline; lỗi giữ journal/job và khóa chạy lại. Khi mất phiên trong bộ nhớ, thao tác kiểm tra đầu vào dùng journal có xác minh project/sequence/cấu trúc. Journal hỏng hoặc không khớp danh tính không được áp dụng. Không tự Save/Undo hoặc đóng Premiere.

Kế thừa ưu tiên SRT của 2.20.49, marker số của 2.20.48 và toàn bộ timing/engine đã có trong nguồn. Cập nhật không tự sửa caption/marker cũ trong project.

## Kiểm chứng và giới hạn

Nguồn trước đóng gói đã đạt 43 nhóm kiểm thử, parse 112 script PowerShell với `-NoWindowsIntegration` (sáu nhóm Windows integration bỏ qua theo runner). Resolver/host/UI/recovery có kiểm nguồn/phạm vi, track/clip trống, chồng thời gian, clip không chọn cùng track, setter không tác dụng, native lỗi, abort, mất session, journal hỏng và sai danh tính. Giao diện Edge headless đạt 320/385/560 px, chọn nhiều track/chuyển nguồn/khóa ô/pause/cancel không tràn ngang. Đây là fixture/mô phỏng, không phải nghiệm thu media thực.

Chưa nghe/so WAV xuất thật hoặc nghiệm thu Audio.disabled, nested, speed/effect, mixer/routing/solo, caption import, Preview/Play/Save trong Premiere. Snapshot chưa bao phủ mọi tham số effect/mixer; không sửa timeline/effect khi tác vụ đang chạy. Nhạc trộn sẵn trong nguồn vẫn còn. Lựa chọn nhiều track không có nghĩa là tách người nói hay tạo caption riêng cho từng track.
