# Kênh thông báo thống nhất 2.20.70

Triển khai phương án `NOTIFICATION_CHANNEL_REDESIGN_2026-10-18.md`, người
dùng duyệt bằng “Tiếp tục”. Bản 2.20.69 chỉ là gói chờ của hướng trước,
không cài. Đợt này cài trực tiếp từ 2.20.68 sau kiểm tra.

## Hành vi sử dụng

- Panel là nơi duy nhất xem kết quả và quyết định. Bỏ nút/cửa sổ xem riêng,
  API review và lệnh IPC review. Không chỉ ẩn nút.
- Một vùng dưới nút chạy thay giữa tiến trình và kết quả/phê duyệt; khung
  phê duyệt trong luồng, không overlay che panel hoặc bẫy Tab. Escape vẫn
  hủy quyết định an toàn. Kết quả thường không có nút bắt xác nhận đã đọc.
- Chỉ giữ “Nhắc khi hoàn tất hoặc cần tôi xử lý”, mặc định bật; giữ quyền
  bật/tắt Windows đã lưu. Ngừng dùng lựa chọn focus cũ. Không tự chuyển focus,
  nháy taskbar, phát âm thanh hoặc mở cửa sổ để vượt quyền thông báo/DND.
- Hoàn tất, lỗi, chờ quyết định và dừng xong khi ở nền nhắc một lần. Hoàn tất
  kèm vấn đề là một thông báo. Lỗi trường/tiến độ/fallback đã xử lý không nhắc.
- Bấm toast mở đúng panel có kết quả hiện tại. Không phê duyệt, chạy lại,
  Save/Undo từ toast. Toast cũ không tác động tác vụ mới.
- Khi thẻ kết quả thật sự đang hiển thị, đánh dấu đã xem và dọn toast;
  không đóng kết quả hoặc gỡ khóa phục hồi. Mở Chi tiết/lịch sử không nhắc lại.
- Hỗ trợ có nút Thử thông báo Windows, chờ 5 giây để chuyển ứng dụng. Phép
  thử có nhãn riêng, bridge/phiên riêng, không thay kết quả hoặc project.

## Cách tránh trùng và thông báo muộn

JS kiểm visibility/viewport của đúng thẻ và focus thật của panel. Khi focus
ở timeline hoặc ứng dụng khác, helper đối chiếu foreground với đúng Premiere
ancestor của caller; không chỉ dùng document.hasFocus để suy ra đã rời app.
Helper không coi dialog modal của Premiere là bằng chứng panel đã được xem.
Nếu không xác minh được host, không tự coi kết quả là đã đọc.

Trước khi flush pipe sau handshake, bridge kiểm lại thẻ hiện tại/đã xem và
khả năng hiển thị mới nhất. Đọc/đóng/thay sự kiện trong lúc chờ không tạo
toast muộn. Thay run/sự kiện bỏ hàng đợi cũ; session/run/incident cũ bị chặn.
Khi quay lại, các sự kiện hiển thị/scroll/focus và kiểm host trong vòng đời
helper xác nhận thẻ đang xem rồi dọn thông báo tương ứng. Không gửi dữ liệu
chuyển động hay tên ứng dụng khác lên máy chủ.

Helper chỉ nhận kind/workflow/hasWarnings và cờ cần thiết theo whitelist,
không nhận bản sao title/message/impact, lời thoại hay đường dẫn panel.
`NotificationWindow.cs` kiểm ancestry/session/creation time và danh tính host;
chỉ gọi kích hoạt cửa sổ trong callback người dùng bấm toast. Quyền lấy focus
vẫn do Windows quyết định; nếu bị từ chối, kết quả vẫn giữ trong panel.

## Ràng buộc giữ nguyên

Không thay thuật toán nhận diện, căn thời gian, marker, engine hoặc host JSX.
Giữ kiểm dữ liệu đã đổi/chưa biết, khóa chạy đè/phục hồi, an toàn hủy/tạm dừng,
khôi phục audio/mute/In-Out và mọi phê duyệt có hệ quả. Đọc/đóng thông báo
không trở thành xác nhận timeline an toàn. Không tự đóng Premiere, Save/Undo
hoặc sửa project để kiểm thử/cài đặt.

## Bằng chứng và nghiệm thu

Các log/bản sao nguồn trước sửa nằm tại `.tmp-channels-2.20.70/`. Kiểm UI
trình duyệt ở 320/385/560 px, hai mode, chi tiết dài ở chiều cao 520 px,
thẻ kết quả/phê duyệt trong luồng và không còn nút/cài đặt thừa đã đạt.
Đã xem ảnh `preview/result-385.png`. Đây là dữ liệu mô phỏng, không gọi Premiere.

Kiểm bridge/policy/renderer bao phủ sự kiện đã xem, pending handshake, thay
run, callback cũ, tắt nhắc, DND, card ngoài viewport, phê duyệt nền và cập nhật
không đổi kết quả. Kiểm IPC thực dùng helper mới, parent binding, thay run,
EOF và clear cũ; không bật UI hoặc gọi Premiere. Protocol từ chối review,
approve/retry/Save/Undo và dữ liệu sai kiểu/giới hạn.

Lượt suite đầu phát hiện assertion cũ yêu cầu dừng xong ở nền im lặng; cập
nhật theo phương án mới, vẫn giữ toàn bộ kiểm cleanup/khóa phục hồi. Lượt
cuối và kết quả gói/cài đặt được ghi bổ sung khi hoàn tất.

Lượt cuối đạt 53 nhóm hồi quy, parse 123 script PowerShell; sáu nhóm tích hợp
Windows được runner bỏ qua. Policy đạt 1.541 kiểm tra, protocol 51 trường hợp.
Preview cuối bổ sung xác nhận một vùng trạng thái và không còn control thừa.

Sau cài cần nghiệm thu trong Premiere: cả hai workflow; panel đang xem,
focus timeline với panel hiện, panel đóng/ẩn, Premiere thu nhỏ và ứng dụng
khác; bấm toast mở đúng kết quả; đọc trước khi helper ready; Windows DND/tắt
quyền. Việc đã thấy toast kiểm thử69 không thay nghiệm thu cơ chế mới này.

## Gói và cài đặt đã xác minh

71 tệp payload/72 mục ZIP khớp checksum và nguồn. 20 bộ VM chạy mã trong gói
đạt; 48 tệp engine/host khớp 2.20.68. ZIP SHA256:
`68D6D5AA58296DED180C7EE91D759B5C08350F2278C8CE9332BBC4C3FD1CF453`.

Đã cài trực tiếp từ 2.20.68 lúc 09:00 ngày 18/10/2026 (UTC+7), khi Premiere
và helper đã đóng; không cần yêu cầu đóng thêm. 63/63 tệp panel khớp gói;
giữ nguyên hash 4.284 tệp dữ liệu/22 thư mục và registry CEP. Bộ cài không
mở helper hoặc thao tác project. Bản sao panel trước và bằng chứng:
`dist/_installation-2.20.70-20261018T020041Z/verified.json`.

Phần bằng chứng cài đặt bổ sung sau build; không thay ZIP đã kiểm. Kiểm
workflow/click/visibility thực trong Premiere vẫn chờ người dùng nghiệm thu.
