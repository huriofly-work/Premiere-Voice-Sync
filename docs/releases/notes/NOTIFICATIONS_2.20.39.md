# 2.20.39 — tạm dừng và tiếp tục

Hai chế độ có nút **Tạm dừng**, đổi thành **Tiếp tục** khi tool thực sự đã nghỉ. **Dừng tác vụ** vẫn dùng được khi đang yêu cầu nghỉ, đã nghỉ hoặc đang kiểm tra để tiếp tục. Các nút chạy mới giữ khóa đến khi lượt hiện tại kết thúc.

## Điểm nghỉ

- Phân tích/nhận diện: chờ script hiện tại chạy xong rồi mới nghỉ. Không đóng băng Whisper/FFmpeg hoặc mất kết quả đã xong; tiếp tục không nhận diện lại phần đó.
- Dựng timeline: chờ lượt native hiện tại trả về, nghỉ trước lượt tiếp theo. Giữ session/token/call-order và guard executor cũ.
- Xuất WAV: chờ toàn phiên xuất các vùng kết thúc và khôi phục mute/In/Out rồi mới nghỉ. Không giữ trạng thái cô lập voice hay In/Out tạm trong thời gian nghỉ.
- Import caption/hậu kiểm cuối: nếu không còn bước xử lý tiếp theo thì tác vụ hoàn tất tự nhiên. Không tạo trạng thái nghỉ giả sau khi đã xong.

Thời gian chờ điểm nghỉ có thể dài nếu script nhận diện hoặc lệnh Premiere đang bận. Không báo Đã tạm dừng khi các công việc này chưa xong.

## Tiếp tục và hủy

Không sửa timeline, đổi project/sequence hoặc mở lại panel trong lúc nghỉ. Có thể xem/nghe kiểm tra, nhưng dừng phát trước khi Tiếp tục. Tool chụp trạng thái chỉ đọc khi nghỉ và đọc lại khi tiếp tục: định danh project/sequence, các clip video/audio và nguồn, mép nguồn/thời gian/speed, mute, In/Out, các mục cấp gốc trong Project và số Caption Track khi API có. Khác biệt hoặc lỗi xác minh chặn tiếp tục và giữ khóa kiểm tra/khôi phục. Snapshot này không kiểm mọi hiệu ứng, nội dung chữ caption hoặc thay đổi sâu trong nested sequence; không dùng nó như bảo đảm cho phép chỉnh project khi đang nghỉ.

Playhead/selection không nằm trong snapshot; dữ liệu job/phạm vi audio đã chọn vẫn giữ nguyên. Executor/import tiếp tục chạy các kiểm snapshot vốn có trước khi sửa timeline. Không tự Play/Save/Undo hoặc tự tiếp tục sau reload; journal cũ yêu cầu kiểm tra phục hồi.

Bấm Dừng lúc đang nghỉ giải phóng luồng chờ và dùng cleanup/abort của 2.20.38. Các thay đổi đã dựng không tự hoàn tác. Lỗi giao diện trong khi nghỉ cũng giải phóng waiter để không để khóa Promise vô hạn. Thời gian nghỉ được ghi riêng và loại khỏi processingMilliseconds/thời gian xử lý stage; thời gian tổng hiển thị vẫn bao gồm lúc nghỉ.

## Kiểm thử và nghiệm thu

Test workflow mô phỏng kiểm hai chế độ tại nhiều điểm, không có work khi đã nghỉ, tiếp tục không chạy lại ASR, state guard, click lặp, dừng khi chờ/đã nghỉ/đang xác minh, lỗi đọc và lỗi giao diện. Test host chạy hàm thật qua VM để kiểm các trường snapshot và thiếu API caption. Test metrics kiểm cộng thời gian nghỉ đúng một lần. Test browser kiểm các trạng thái nút ở 320/385/560 px.

Cần thử trong Premiere thật: pause dài ở ASR và giữa stage dựng, preview khi nghỉ rồi dừng phát/tiếp tục, export nhiều vùng và mute ban đầu hỗn hợp, đổi timeline/sequence khi nghỉ phải bị chặn, hủy khi nghỉ, lỗi khôi phục, Play/Save sau hoàn tất. Không suy nghiệm thu native từ mô phỏng.

Kiểm ngày 15/10/2026: `Run-Tests.ps1 -NoWindowsIntegration` đạt 36 nhóm, parse 101 PowerShell; sáu nhóm tích hợp Windows được bỏ qua. JS syntax, generated-executor check và diff whitespace đạt. Edge headless dùng profile tạm riêng đạt hai chế độ 320/385/560 px với các trạng thái đang chạy/yêu cầu nghỉ/đã nghỉ/tiếp tục/yêu cầu dừng; đã xem ảnh subtitle đang nghỉ ở 385 px. Log: `dist/pause-2.20.39-tests.txt`; ảnh: `dist/_ui-preview-2.20.39`. Không gọi Premiere hoặc media thật trong các kiểm này.
