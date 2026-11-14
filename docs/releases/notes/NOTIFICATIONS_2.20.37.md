# 2.20.37 — tách chuẩn bị audio khỏi lượt encoding

Người dùng xác nhận ngày 15/10/2026: xuất WAV thủ công chạy ngay, trong khi Chỉ tạo subtitle đứng Encoding 0% rất lâu. Kết quả này nghiêng về đường gọi export từ tool/scripting hơn là tốc độ PC hoặc nhận diện Whisper. Hai log trước đó dừng tại audio-export sau 112–128 giây. Chưa có bằng chứng native xác định chính xác cơ chế gây kẹt.

## Thay đổi

Luồng cũ đổi mute, bật voice, đặt In/Out và gọi exportAsMediaDirect trong cùng một lượt ExtendScript. Cách mới:

1. `beginCaptionAudioExport` kiểm đầu vào, lưu mute/In/Out, cô lập voice, đặt vùng đầu tiên rồi trả về. Không encoding trong bước này.
2. Panel nhường vòng lặp CEP 100 ms bên ngoài ExtendScript; không dùng `$.sleep` giữ luồng host.
3. `advanceCaptionAudioExport` kiểm project, sequence, snapshot, mute và In/Out trước khi xuất đúng một vùng. Nếu còn vùng kế tiếp thì chuẩn bị In/Out rồi trả về và nhường tiếp trước lần xuất sau.
4. Kết thúc/lỗi native: khôi phục từng track và In/Out độc lập, xác minh rồi mới cho engine nhận diện chạy. Lỗi truyền thông hoặc sai thứ tự: panel gọi abort đúng token sau khi host call trả lại. Không timeout hoặc gửi lại native export.

Mục tiêu là tránh gọi encoder ngay sau thay đổi audio graph/In/Out mà chưa trả quyền điều khiển về Premiere. Đây là giả thuyết kỹ thuật từ khác biệt giữa luồng thủ công và luồng tool; khoảng nhường 100 ms không phải phép đo chứng minh audio graph đã sẵn sàng và không phải bảo đảm hết kẹt trên mọi project.

Phiên host chặn lượt lặp, token khác và phiên mới khi phiên cũ chưa hoàn tất. Nếu mở lại panel giữa các lượt, thao tác **Kiểm tra đầu vào** phục hồi phiên host còn dang dở sau bước xác nhận phục hồi có sẵn. Nếu Premiere bị tắt đột ngột, không có bảo đảm finally chạy; vẫn cần kiểm tra trạng thái mute/In/Out khi mở lại project. Không sửa timeline trong lúc tác vụ đang chạy.

Giữ preset WAV 48 kHz 16-bit và luồng xuất sequence nên vẫn lấy speed, nested sequence, routing/hiệu ứng mà Premiere render; không thay bằng đọc trực tiếp media nguồn. Chưa đổi engine ASR/căn lời, điểm cắt, tốc độ dựng hay nội dung subtitle. Kế thừa guard lỗi native/WAV dở và log mã giai đoạn của [2.20.36](NOTIFICATIONS_2.20.36.md), thêm between-calls.

## Kiểm chứng

Test host kiểm không encoding khi begin; native chạy ở lượt host sau In/Out; một vùng mỗi lượt; nhiều vùng; lỗi ở vùng sau; token/lượt trùng; timeline/project/sequence/In/Out thay đổi; hủy/khôi phục và WAV dở. Test panel kiểm thứ tự begin → yield → advance, số lượt hữu hạn, không retry, abort sau lỗi truyền thông và giữ lỗi gốc khi khôi phục lỗi. Các test này là mô phỏng, không tái tạo audio graph nội bộ của Premiere.

Cần kiểm lại trên Premiere thật với cùng vùng đã xuất thủ công, rồi nhiều vùng, mute hỗn hợp, voice ban đầu mute, nested/routing/hiệu ứng/Solo, hủy Encoding, Caption/Play/Save. Chỉ sau lần chạy thật mới kết luận bản này giải quyết kẹt 0% trên project đang gặp lỗi.

Kiểm tự động ngày 15/10/2026: bộ `Run-Tests.ps1 -NoWindowsIntegration` đạt 35 nhóm, parse 99 script PowerShell; sáu nhóm tích hợp Windows được bỏ qua. Test host/UI phiên export mới, JS syntax, generator parity và repository/version đều đạt. Không gọi Premiere hoặc nhận diện media thật trong các kiểm thử này.

Đã cài 2.20.37 khi Premiere đóng bằng `dist/Install-Verified-2.20.37.ps1`: 56/56 file panel khớp manifest; 601 file và 22 thư mục dữ liệu giữ nguyên qua hash trước/sau; shortcut/helper đúng identity/checksum. ZIP đã kiểm 64 file payload, SHA256 E232F9EB4A029C768BE948D099A61F33B2CE3692542FE1575959177A785D5ED8. Bằng chứng: `dist/_installation-2.20.37-20261015-211645/verified.json`. Không mở/đóng Premiere hoặc sửa project; nghiệm thu encoding/Caption/Play/Save đang chờ người dùng.
