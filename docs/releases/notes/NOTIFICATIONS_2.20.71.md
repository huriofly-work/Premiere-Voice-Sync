# Âm thanh cùng thông báo Windows 2.20.71

Thêm lựa chọn **Phát âm thanh khi hoàn tất hoặc cần xử lý** theo yêu cầu
người dùng và xác nhận “Tiếp tục”. Không thêm kênh/cửa sổ thông báo khác.

## Sử dụng

- Tùy chọn âm thanh mặc định bật; giữ lựa chọn bật/tắt đã lưu bằng khóa riêng
  `pvs.notificationSound`. Tắt âm thanh vẫn có banner Windows.
- Tắt Nhắc khi hoàn tất hoặc cần tôi xử lý thì không gửi thông báo và không
  phát tiếng; mục âm thanh bị vô hiệu hóa nhưng không xóa lựa chọn riêng.
- Khi đang xem đúng kết quả trong panel, không có toast hoặc tiếng. Ở nền,
  chỉ các sự kiện vốn cần nhắc mới có thể phát tiếng: hoàn tất, lỗi, chờ phê
  duyệt và dừng xong. Tiến độ, lỗi trường, log/fallback đã xử lý không phát.
- Dùng âm mặc định Windows, một lần, cùng chính toast. Không phát bằng sound
  player riêng, không lặp, không ép âm lượng hay vượt Không làm phiền/quyền
  âm thanh của Windows. Không giành focus hoặc mở cửa sổ trùng.
- Hỗ trợ → Thử thông báo Windows dùng thiết lập âm thanh hiện tại. Phép thử
  có nhãn riêng và không thay kết quả, gọi workflow hoặc sửa project.

## Triển khai

Policy chỉ cho sound khi có banner hợp lệ, được bật và không DND. Bridge
đọc lại quyền âm thanh ở handshake, giữ chống trùng/sự kiện đã xem/sự kiện
cũ. Mute hoặc đổi lựa chọn không phát lại toast đang có. Thông báo chỉ vào
Notification Center hoặc không gửi toast không phát tiếng.

Protocol yêu cầu trường bool `playSound`; helper dùng `PvsNotificationAudio`
để dựng `<audio src="ms-winsoundevent:Notification.Default" loop="false"/>`
hoặc `<audio silent="true"/>`. Âm thanh thuộc cùng toast WinRT, Windows quản
lý việc phát. Không thay engine, host JSX, project, cache, model, jobs hoặc
các chốt dừng/tạm dừng/phê duyệt/phục hồi.

## Kiểm chứng

Log và bản sao trước sửa ở `.tmp-sound-2.20.71/`. Kiểm định tuyến đạt 1.973
trường hợp; protocol/markup thuần C# đạt 59 trường hợp. Kiểm bridge/renderer
bao phủ lựa chọn mặc định/đã lưu, master off, sound off, đổi lúc chờ helper,
không toast/đã xem/trùng/DND và âm thanh chỉ đi cùng banner.

Kiểm UI mô phỏng 320/385/560 px, checkbox bật/tắt/lưu lựa chọn và trạng thái
disabled theo master đã đạt. IPC helper thực đạt, không bật UI trong phép
thử đó. Phép thử live riêng dùng `--show-toast --sound` với chính helper sửa;
người dùng xác nhận **Có nghe âm thanh**. Đây là nghiệm thu tiếng toast thử
trên máy này, chưa thay kiểm hai workflow và trạng thái cửa sổ trong Premiere.

Kết quả suite/gói/cài được ghi bổ sung sau khi hoàn tất. Nguồn tham khảo:
[Microsoft Toast audio](https://learn.microsoft.com/en-us/uwp/schemas/tiles/toastschema/element-audio).

Suite cuối đạt 53 nhóm, parse 123 script PowerShell; runner bỏ qua sáu nhóm
tích hợp Windows. Preview cuối bổ sung ảnh tùy chọn âm thanh, đã xem ảnh
`preview-final/sound-settings-385.png`. Không thay bộ kiểm an toàn/engine.

## Gói và cài đặt đã xác minh

71 tệp payload/72 mục ZIP khớp checksum và nguồn; 20 bộ VM kiểm mã đóng gói
đạt. 48 tệp engine/host khớp 2.20.70. ZIP SHA256:
`AD485B0F9F3E3B852351726C3C8442EFF82EF52AE99B76EF9791DE3FC17EC717`.

Đã cài từ 2.20.70 lúc 10:04 ngày 18/10/2026 (UTC+7), khi Premiere/helper
đã đóng. 63/63 tệp panel khớp gói; giữ nguyên hash 4.522 tệp dữ liệu/22 thư
mục và registry CEP. Không thao tác project hoặc mở helper trong bộ cài.
Bản sao panel trước và xác minh tại
`dist/_installation-2.20.71-20261018T030439Z/verified.json`.

Bằng chứng này bổ sung sau build, không thay ZIP đã kiểm. Người dùng đã
xác nhận nghe âm thanh toast thử; nghiệm thu lượt chạy và click/visibility
thực trong Premiere vẫn là bước riêng.
