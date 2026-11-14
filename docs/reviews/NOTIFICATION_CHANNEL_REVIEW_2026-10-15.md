# Lựa chọn kênh thông báo cho Premiere Voice Sync

Ngày: 2026-10-15. Phạm vi: đánh giá lại toàn bộ các lựa chọn liên quan, thử độc lập Windows toast/modeless, chọn kiến trúc và kế hoạch tích hợp. Panel đang dùng 2.20.30 được giữ nguyên trong bước này.

## Tiêu chí quyết định

1. Người dùng nhận biết được sự cố trong ứng dụng và khi đang làm việc khác.
2. Thông báo đưa tới đúng tác vụ, nói rõ timeline đã đổi/chưa đổi/chưa xác định và hành động tiếp theo.
3. Người dùng vẫn kiểm tra được timeline, Undo thủ công hoặc mở bản đã lưu khi cần.
4. Chỉ tác vụ cần quyết định bị dừng; không làm gián đoạn mọi thao tác Premiere hoặc giành focus liên tục.
5. Một sự cố có một trạng thái dùng chung; không gửi mọi loại thông báo cùng lúc hoặc tiếp tục nhắc khi đã xử lý.
6. Không gắn quyết định dựng/Save/Undo trực tiếp vào callback thông báo ngoài ứng dụng.
7. Không đè thông báo render/progress do Premiere đang quản lý; không thêm daemon hay runtime lớn chỉ để báo lỗi.

Không dùng điểm số tổng tùy ý để tuyên bố một loại luôn tốt nhất. Tách tính khả thi nền tảng, kết quả API, hành vi đã quan sát và nghiệm thu người dùng.

## Đối chiếu lựa chọn

| Loại | Vai trò phù hợp | Hạn chế trong chương trình này | Quyết định |
| --- | --- | --- | --- |
| Lỗi cạnh trường nhập | Thiếu SRT, số không hợp lệ | Không thấy khi panel ẩn | Dùng cho lỗi người dùng vừa gây ra; dẫn tới đúng trường |
| Status/progress trong panel | Bước chạy, tác vụ chưa phản hồi | Cần nhìn panel | Giữ, không biến chờ lâu thành kết luận thất bại |
| Thẻ kết quả/banner cố định | Thành công, cảnh báo đã khắc phục, danh sách cần nghe lại | Chỉ ở trong ứng dụng | Dùng, không bắt đóng hộp cho reset thiết lập/xuất log thành công |
| Hộp chọn trong panel | Xác nhận bắt đầu, xóa cache, quyết định giữa tác vụ | Không giúp khi panel bị che | Giữ cho xét duyệt tại chỗ; dừng workflow, không khóa toàn Premiere |
| Windows toast + Notification Center | Lỗi/quyết định hoặc hoàn tất tác vụ dài khi người dùng ở ứng dụng khác | Có thể bị tắt/DND; phải định danh và xử lý click đúng | Bổ sung làm kênh ngoài ứng dụng chính; click Mở để xử lý |
| Cửa sổ không khóa (modeless) | Đọc lỗi trong khi kiểm timeline, panel quá hẹp/ẩn | Cần owner/lifetime/đồng bộ sự cố; có thể che vùng làm việc | Dùng có điều kiện sau nghiệm thu với Premiere; không bật thêm nếu hộp hiện tại đã đủ |
| CEP Modeless | Cửa sổ theo host, tái dùng HTML/CSS | Cần thêm extension ID, giao tiếp phiên và kiểm thực tế Premiere | Giữ là phương án triển khai so sánh; tài liệu hỗ trợ không phải nghiệm thu |
| MessageBox/TaskDialog hoặc CEP ModalDialog khóa host | Quyết định thực sự phải chặn toàn ứng dụng | Cản kiểm tra timeline/Undo; dễ gây chuỗi hộp thoại | Không chọn làm mặc định cho lỗi tác vụ |
| Nhấp nháy taskbar | Dấu chú ý khi focus bị từ chối | Không giải thích lỗi, dễ bỏ lỡ | Giữ làm hỗ trợ, giới hạn số lần |
| Taskbar overlay/progress | Trạng thái ngắn | Cửa sổ/taskbar thuộc Premiere; có nguy cơ đè trạng thái render của host | Chưa dùng trên cửa sổ Premiere |
| System tray/balloon cũ | Ứng dụng nền độc lập tồn tại thường trực | Thêm icon/process cho một extension; có thể bị ẩn và cần menu quản lý riêng | Không thêm daemon/tray chỉ vì thông báo |
| Âm báo | Người dùng không nhìn màn hình | Gây nhiễu khi nghe voice/caption, có thể bị ghi vào audio | Tùy chọn một lần cho lỗi/quyết định; mặc định tắt, tôn trọng DND |
| Lịch sử và log | Xem lại, chẩn đoán | Là nơi lưu, không phải kênh báo lỗi kịp thời | Giữ, không dùng để thay thế thông báo |

## Kiến trúc được chọn

Kết hợp **phản hồi tại chỗ + Windows toast + nơi xem/xử lý sự cố**, dùng taskbar và foreground có giới hạn để hỗ trợ. Panel tiếp tục giữ trạng thái và nhật ký; không còn là kênh truyền đạt duy nhất.

- Đang nhìn panel: lỗi nhập hiện cạnh trường; tiến trình/status, kết quả gọn và cảnh báo tổng hợp không mở modal. Chỉ yêu cầu quyết định mới dùng hộp chọn.
- Lỗi/quyết định khi ở ứng dụng khác: nếu người dùng bật đưa lên trước, thử một lần rồi xác minh kết quả. Đã đưa đúng Premiere/panel lên trước thì không phát thêm toast cạnh tranh. Nếu bị từ chối hoặc người dùng tắt lấy focus, gửi toast và dấu taskbar có giới hạn.
- Cửa sổ xem sự cố riêng được mở khi người dùng bấm Mở để xử lý, hoặc khi đã đưa ứng dụng lên trước và cần vừa đọc lỗi vừa xem timeline. Không tự bật modeless chồng lên ứng dụng khác chỉ vì đã tạo toast.
- Tác vụ dài hoàn tất ở nền: toast không lấy focus. Mốc 30 giây trong policy là giá trị ứng viên để phân biệt tác vụ với thao tác ngắn, cần hiệu chỉnh theo sử dụng, không phải kết quả nghiên cứu người dùng.
- GPU chuyển CPU, cleanup phụ hoặc cue cần nghe lại: banner tổng hợp; không đánh thức màn hình/giành focus/phát tiếng chỉ vì đã có fallback an toàn.
- DND/Windows tắt thông báo: không dùng loại alarm/reminder để vượt lựa chọn của người dùng; giữ trạng thái chờ xử lý trong app và tận dụng Notification Center khi hệ điều hành cho phép.

Mặc định đề xuất: thông báo Windows cho lỗi/quyết định và tác vụ dài chạy nền bật; đưa Premiere lên trước cho lỗi/quyết định bật theo yêu cầu người dùng; âm báo tắt. Không thêm hàng loạt tùy chọn phân loại kỹ thuật ra giao diện.

## Kết quả thực tế và giới hạn

Prototype ở `experiments/notification-channels`, binary/log/ảnh trong `dist/_notification-channels`. Các file này không được đưa vào ZIP hay panel đang cài.

| Phép kiểm | Kết quả có bằng chứng | Không được suy ra |
| --- | --- | --- |
| C# + WinRT trên máy này | Biên dịch bằng .NET Framework/WinMetadata sẵn có, không tải runtime | Mọi phiên bản Windows/máy đều tương thích |
| Toast API/history | Gửi thành công, tìm đúng tag/group trong Notification Center, xóa được | Banner chắc chắn đã hiện trên màn hình hoặc người dùng đã nhìn thấy |
| Modeless mẫu | Form hiện, owner Enabled, không TopMost; nhận event nút xem hướng xử lý qua Computer Use | Đã nghiệm thu owner là Premiere hoặc CEP Modeless |
| Gộp gửi lặp | Lần gửi thứ hai bị bỏ, có event xác minh | Đã kiểm hết race condition giữa panel và helper production |
| Đóng thông báo | Không phát sinh phê duyệt/workflow action; dọn shortcut/thông báo mẫu | Các callback toast sau cold start đã hoàn chỉnh |
| Policy chọn kênh | 384 tổ hợp môi trường cùng các ca sai/đúng định danh; toàn bộ assertion đạt | Chất lượng UX đã được đo trên người dùng hoặc native Premiere |

Quan sát ảnh thật của cửa sổ mẫu qua Computer Use đã thành công sau khi chọn/kích hoạt đúng cửa sổ; lần đọc ban đầu gặp lỗi foreground PID. Ảnh `modeless-render.png` riêng được tạo bằng DrawToBitmap chỉ là render bố cục, không phải screenshot nghiệm thu. Không tự chụp/điều khiển Premiere sau lần công cụ từ chối quyền ở lượt trước.

Toast click thật, cold activation, DND/banner, đa màn hình/DPI và thao tác trong Premiere vẫn cần kiểm. Prototype chỉ có callback khi tiến trình còn sống. Chưa có cơ sở gọi cấu hình này là tối ưu đã nghiệm thu; đây là kiến trúc phù hợp nhất theo các tiêu chí và bằng chứng hiện có.

Đối chiếu cuối: 49/49 file panel đang cài khớp gói 2.20.30, không có file thừa; tiến trình mẫu đã thoát và shortcut tạm không còn. Kết quả ở `dist/_notification-channels/evaluation-verified.json`.

Đối chiếu thêm với snapshot trước lần cài 2.20.30: 598 file còn khớp hash; 20 file thuộc Jobs không còn và backend-state.json đã thay đổi. Cache/model/backups không có khác biệt được ghi nhận. Snapshot này được tạo ở lượt cài trước, không phải đầu lượt đánh giá, nên không gán các chênh lệch này cho phép thử và không tuyên bố toàn bộ 619 file vẫn nguyên vẹn đến hiện tại. Không tự khôi phục/xóa thêm dữ liệu; bản tổng hợp chỉ lưu nhóm/số lượng ở `dist/_notification-channels/prior-data-snapshot-comparison.json`. Code prototype không truy cập cây dữ liệu PremiereVoiceSync.

## Kế hoạch tích hợp ứng viên tiếp theo

1. Tách model sự cố/chính sách chọn kênh khỏi renderer hiện tại. Một ID sự cố, ID tác vụ và ID phiên dùng cho mọi kênh; raw lỗi không đưa lên toast.
2. Thay thông báo chung của thao tác ngắn bằng thông báo cạnh trường/banner. Phân biệt người dùng vừa bấm với sự cố phát sinh trong tác vụ chạy nền.
3. Xây adapter Windows từ prototype: định danh riêng của Premiere Voice Sync do bộ cài quản lý; build/pin checksum helper và shortcut; không phụ thuộc danh tính PowerShell hay giả danh Premiere.
4. Hoàn thiện giao tiếp bất đồng bộ và lifetime: click chỉ yêu cầu mở sự cố đúng phiên đang sống; bỏ qua request cũ/hết hạn/đã xử lý. Không cho OS notification gọi dựng, retry, Save hoặc Undo.
5. Xử lý nhận biết foreground/khả năng nhìn panel theo dữ liệu thực tế, không chỉ document.hasFocus. Kết quả helper trả về không được hiểu là người dùng đã đọc. Khi sự cố được xử lý, dọn cả toast và cửa sổ liên quan.
6. Chọn adapter cửa sổ riêng bằng thử A/B kỹ thuật: native helper đã có để gửi toast so với CEP Modeless. So sánh khả năng thao tác timeline, owner đúng tiến trình, dock/ẩn, DPI, đóng/mở lại panel và phát sinh lỗi trong callback. Chỉ bật loại đã qua nghiệm thu; không tự thêm cả hai vào sản phẩm.
7. Mở rộng allowlist/checksum, setup rollback/uninstall và fixture cho đúng identity/shortcut/helper mới. Không thay thiết lập thông báo/DND/security toàn Windows; giữ cache/model/jobs/backups và các gói khôi phục.
8. Kiểm policy, callback cũ, gửi trùng, disable channel, helper chết, registry/shortcut không ghi được. Sau đó chạy toàn bộ hồi quy và test browser.
9. Đóng gói bản ứng viên mới; nghiệm thu toast banner/click và thao tác thật trong Premiere trên project sao lưu. Chỉ sau kết quả này mới cập nhật bản dùng chính. Không lấy kết quả popup độc lập để bỏ bước nghiệm thu host.

## Nguồn nền tảng

Cập nhật sau đánh giá: các kênh đã được tích hợp vào [ứng viên 2.20.31](../releases/notes/NOTIFICATIONS_2.20.31.md). Bản này chưa thay panel đang cài; bằng chứng cửa sổ mẫu không được dùng thay nghiệm thu toast/cửa sổ trong Premiere.

- [Microsoft: Notifications design basics](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-ux-guidance): chọn kênh theo mục đích, tránh quá nhiều gián đoạn, mở đúng ngữ cảnh và dọn thông báo cũ.
- [Microsoft: Desktop toast quickstart](https://learn.microsoft.com/en-us/windows/win32/shell/quickstart-sending-desktop-toast) và [AUMID shortcut](https://learn.microsoft.com/en-us/windows/win32/shell/enable-desktop-toast-with-appusermodelid): định danh desktop và callback.
- [Microsoft: Notifications and Do Not Disturb](https://support.microsoft.com/en-us/windows/experience/notifications-and-do-not-disturb-in-windows): quyền bật/tắt và cách hệ điều hành xử lý banner/Notification Center.
- [Adobe CEP 12 Cookbook](https://github.com/Adobe-CEP/CEP-Resources/blob/master/CEP_12.x/Documentation/CEP%2012%20HTML%20Extension%20Cookbook.md): Panel, ModalDialog và Modeless có hành vi khác nhau.
