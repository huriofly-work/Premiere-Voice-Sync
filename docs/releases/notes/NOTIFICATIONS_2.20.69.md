# Thông báo hoàn tất 2.20.69

Lượt tạo phụ đề bản 2.20.68 ngày 18/10 kết thúc lúc 08:26:34 (UTC+7).
Windows PushNotification-Platform ghi sự kiện 3153 lúc 08:26:35, tracking
84741, gửi tới PremiereVoiceSync.Notifications; History có thông báo đúng
nội dung hoàn tất kèm cảnh báo. Quyền ToastNotifier.Setting là Enabled.
Không có bằng chứng banner đã hiện trên màn hình. Trạng thái Windows lúc
kiểm tra sau đó là accepts-notifications, profile Unrestricted; không dùng
trạng thái sau đó để kết luận Không làm phiền tại thời điểm tác vụ kết thúc.

Thiếu sót xác nhận trong 2.20.68: completed chỉ gửi toast im lặng và bỏ qua
lựa chọn focus; không yêu cầu nháy taskbar. 2.20.69 sửa như sau:

- Hoàn tất ở nền thử đưa Premiere lên một lần nếu người dùng bật lựa chọn.
  Xác minh panel có focus trước khi bỏ toast. Windows từ chối thì nháy taskbar
  qua helper hiện có và gửi toast; không ép topmost/gửi phím/lặp lấy focus.
- Tắt focus nhưng bật thông báo ngoài: nháy taskbar ba lần và gửi toast.
  Tắt cả hai thì kết quả giữ trong panel. Giữ lựa chọn đã lưu, mặc định không
  lấy focus. Không có phê duyệt, chạy lại, Save hoặc Undo từ toast.
- Toast dùng duration=long, không alarm/reminder và vẫn im lặng. Windows
  quyết định hiển thị theo quyền thông báo/Không làm phiền. Không đổi thiết
  lập Windows; nhãn focus trong panel nói rõ áp dụng cả khi hoàn tất.
- Log workflow ghi các trường cho phép cho định tuyến, kết quả focus và
  trạng thái native, kể cả callback sau khi workflow đã kết thúc. Không ghi
  nội dung lời nói, lỗi thô hoặc đường dẫn media vào dữ liệu này.

Không thay thuật toán engine/host; chỉ dùng helper chú ý đã có. Probe chỉ đọc
từ PID panel tìm đúng Premiere PID 6676; không kích hoạt cửa sổ hoặc thao tác
project trong chẩn đoán. Bằng chứng tại `.tmp-notification-debug-2.20.68/`
và `.tmp-notice-2.20.69/`. Hiển thị banner/click/focus native trong lượt dùng
thực tế vẫn phải phân biệt với kiểm mock hoặc API đã nhận thông báo.

Kiểm helper thực qua pipe đạt, không UI/Premiere. Hai phép thử toast độc lập
với helper69 được gửi lúc 08:35:20 và 08:36:39, trạng thái available/submitted.
Lần đầu người dùng chưa để ý; lần gửi lại người dùng xác nhận “Có banner nổi”.
Đây là bằng chứng banner Windows hiện được trên máy này với helper sửa đổi;
không thay thế nghiệm thu focus, click quay về panel và cả hai workflow thật.

53 nhóm hồi quy đạt, parse 123 script PowerShell; runner bỏ qua sáu nhóm tích
hợp Windows. Chính sách định tuyến đạt 1.818 kiểm tra. Kiểm riêng bao phủ
focus bật/tắt, Windows từ chối/timeout, foreground, gửi trùng/callback cũ,
quyền toast và log loại bỏ dữ liệu riêng. Lượt đầy đủ đầu phát hiện nhánh
dự phòng thiếu chốt completed khi panel đang xem; đã sửa và lượt đầy đủ
cuối đạt (`suite-final.log`). Kết quả gói/cài đặt được bổ sung sau build.

Gói có 70 tệp payload/71 mục ZIP khớp checksum/nguồn; 20 bộ VM chạy trên mã
trong gói đều đạt. 48 tệp engine/host khớp 2.20.68. ZIP SHA256:
`F0E5CE9A6BEA790108936B4D0877837159F7AFA1C834F8F8CC69305BF5A90C74`.
Chưa cài khi Premiere đang mở. Bản này không tự mở cửa sổ review riêng;
panel giữ kết quả tĩnh, kênh thu hút chú ý dùng chính sách focus/Windows
ở trên, tránh thêm cửa sổ trùng lặp. Bằng chứng gói đã build được giữ nguyên.
