# Thông báo và xử lý sự cố 2.20.30

Ngày: 2026-10-15. Nền mã nguồn: 2.20.27. Bản thử đã cài vào panel thật, xác minh 49/49 file; chưa nghiệm thu foreground/taskbar/Preview/Play/Save trong Premiere. Chi tiết cài đặt ở cuối tài liệu.

## Hành vi

| Trường hợp | Hiển thị | Hành động |
| --- | --- | --- |
| Thành công | Thẻ xanh, không chặn | Đóng hoặc tiếp tục làm việc |
| Có cue cần nghe lại, GPU chuyển CPU hoặc cleanup lỗi | Thẻ vàng, không lấy foreground | Xem chi tiết, nhật ký, xuất log |
| Không hoàn tất | Hộp đỏ ở giữa panel | Đọc ảnh hưởng, kiểm đầu vào/SRT, xem/xuất log |
| Xác nhận dựng/xóa cache | Hộp vàng giữa panel | Chọn hành động hoặc Hủy; không tự đồng ý |
| Quyết định giữa tác vụ | Hộp xác nhận và yêu cầu thu hút chú ý | Chờ lựa chọn; không bỏ các guard timeline |
| Thao tác chưa trả lời trên hai phút | Dòng trạng thái về bước đang chờ | Vẫn giữ khóa tác vụ, không tự retry hoặc coi thao tác đã hủy |

Lỗi chính giữ ưu tiên; lỗi trùng tăng số lần, thông báo sau xếp hàng theo mức độ. Cleanup lỗi bổ sung vào lỗi chính. Kết quả thành công được hiển thị sau cleanup, chuyển vàng nếu có cảnh báo. Đóng thông báo chỉ ghi nhận, không tự cho tiếp tục dựng. Tab giữ trong hộp quan trọng; Escape hủy xác nhận/đóng thông báo; focus đầu tiên là nút an toàn.

## Thu hút chú ý

Tùy chọn **Đưa Premiere lên trước khi tác vụ lỗi hoặc cần quyết định** mặc định bật trong **Thông báo gần đây**. Thành công, cảnh báo đã xử lý và xác nhận do người dùng vừa bấm không kích hoạt helper Windows.

CEP yêu cầu kích hoạt panel hiện có. Helper PowerShell chạy ẩn, tối đa bảy giây, chỉ tìm Premiere trong chuỗi tiến trình tổ tiên của tiến trình CEP hiện tại. Kiểm session, thời điểm tạo, executable và chủ sở hữu HWND trước thao tác; không chọn một Premiere bất kỳ theo tên. Nếu không xác định được đúng host thì bỏ qua, giữ thông báo trong panel. Nếu đã ở foreground thì không đổi cửa sổ. Khi cần, khôi phục cửa sổ thu nhỏ và gọi SetForegroundWindow một lần; Windows từ chối thì yêu cầu flash taskbar ba lần. Không dùng gửi phím, vòng lặp lấy focus hoặc always-on-top. Đóng sự cố sẽ dừng helper riêng nếu nó còn chạy.

Nguồn nền tảng: [Microsoft SetForegroundWindow](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow), [FlashWindowEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-flashwindowex), [Adobe CEP 12 CSInterface](https://raw.githubusercontent.com/Adobe-CEP/CEP-Resources/master/CEP_12.x/CSInterface.js), [W3C alert dialog](https://www.w3.org/WAI/ARIA/apg/patterns/alertdialog/).

## Trạng thái và phục hồi

- Trước thao tác ghi: ảnh hưởng `unchanged`; không yêu cầu Undo chỉ vì thiếu đầu vào/nhận diện lỗi.
- Trước gọi dựng/export/import: chuyển sang trạng thái chưa xác định cho đến khi nhận được bằng chứng. Dùng `timelineMutated` của executor khi có. Lỗi import có thể đã đổi Project nên giữ thận trọng.
- Sau lỗi đã ghi/chưa xác định: giữ khóa hai nút chạy, kể cả khi đóng thông báo. **Đã kiểm tra/khôi phục — Xác minh đầu vào** chỉ đọc dữ liệu; không tự Undo, Save, sửa caption hoặc dựng lại.
- Auto edit đối chiếu template với dữ liệu trước tác vụ. Subtitle đối chiếu sequence, snapshot video/audio, số Caption Track, số bin PVS_TEMP_SUBTITLE ở root Project và In/Out. Bin tạm do chức năng subtitle tạo ở root; người dùng vẫn cần kiểm tra thủ công nếu đã di chuyển/đổi tên bin.
- Mở lại panel sau lượt gián đoạn: dấu phiên chỉ lưu loại tác vụ/thời gian, không giữ baseline riêng tư. Cần xác nhận đã chờ/kiểm tra/khôi phục thủ công rồi đọc đầu vào; không tuyên bố tự phục hồi nguyên trạng và không tiếp tục job cũ.
- Lỗi JavaScript/Promise trong tác vụ đánh dấu `fatal`, chặn bước kế tiếp, không biến thành kết quả xanh. Abort phiên dựng chỉ kết thúc phiên executor, không hoàn tác timeline.

Không bỏ qua lỗi bảo toàn nguồn/voice, mốc nhận diện chưa xác minh hoặc hậu kiểm chỉ vì người dùng muốn tiếp tục. Không bổ sung lại luồng duyệt caption thử nghiệm đã gỡ trước đây. Host hoặc CEP crash/treo hoàn toàn vẫn có thể làm thông báo không được vẽ.

## Dữ liệu và phạm vi thay đổi

Lịch sử lưu tối đa 30 bản ghi trong 30 ngày, chỉ gồm mã cố định/mức độ/bước/ảnh hưởng/thời gian/số lần/đã xem. Không lưu tiêu đề tùy ý, error.message, đường dẫn media hoặc transcript vào lịch sử. Chi tiết chỉ giữ trong bộ nhớ phiên; xuất log đã che nếu muốn giữ. Không tự gửi mạng. Dấu phiên và lựa chọn foreground dùng localStorage của panel.

Không đổi thuật toán ASR/DTW/planner, lịch dựng, executor, cache hoặc model. Helper mới được bổ sung vào exact package allowlist/checksum. Gói khôi phục 2.20.27 được giữ nguyên. Bộ cài thật đã chạy sau khi người dùng đồng ý; đối chiếu dữ liệu trước/sau ở cuối tài liệu.

## Kiểm chứng cục bộ

- Toàn bộ 36 nhóm hồi quy đạt; 91 script PowerShell parse đạt. Bộ cài/gỡ/rollback/registry chạy trên fixture riêng, không cập nhật panel thật.
- Kiểm mới: hàng đợi/ưu tiên, chống thông báo trùng, không lưu lỗi riêng tư, foreground một lần/tắt tùy chọn/helper timeout/callback cũ, xét duyệt, khóa host còn chờ, phục hồi đúng/sai template, caption còn tồn tại, lỗi giao diện không thành công giả.
- Helper: ancestry hợp lệ, vòng lặp, thiếu cha, session khác, PID tái sử dụng, executable sai, Premiere không cùng ancestry. Khai báo P/Invoke biên dịch được; probe chỉ đọc, không gọi activation/flash trên cửa sổ thật.
- Edge headless: hai chế độ, 320/385/560 px, chiều cao 520 px với chi tiết dài, focus nút đóng, Escape hủy xác nhận, cảnh báo không modal, không tràn ngang. Ảnh nằm trong `dist/_ui-preview-2.20.30`. Đây là browser fixture, không phải nghiệm thu CEP/native.
- Lần chạy sandbox ban đầu bị giới hạn rename temp/registry và khởi động Edge; chạy lại fixture với temp trong workspace và quyền riêng cho kiểm thử đã đạt. Không thay quyền hệ thống hoặc quy tắc bảo vệ của chương trình.

## Nghiệm thu Premiere còn cần

1. Dùng bản project sao lưu/template sạch. Thử thiếu SRT, thiếu A2 và nhận diện lỗi trước ghi: hộp rõ, không yêu cầu Undo sai.
2. Thử thành công có/không cảnh báo; cảnh báo cleanup không che nguyên nhân chính, không tạo lại caption chỉ vì cleanup lỗi.
3. Khi Premiere ở sau ứng dụng khác hoặc thu nhỏ: gây lỗi từ job mẫu, kiểm đúng cửa sổ và panel. Thử quyền focus bị Windows từ chối, taskbar và tùy chọn tắt. Thử nhiều tiến trình Premiere; không kích hoạt tiến trình khác.
4. Thử panel dock/ẩn và hộp native Premiere đang mở. Không ép lấy focus liên tục hoặc vượt hộp native.
5. Dùng fixture native riêng gây lỗi sau một phần thao tác; đóng thông báo vẫn khóa chạy. Undo/mở lại bản lưu rồi xác minh; timeline/caption chưa khôi phục phải giữ khóa.
6. Tải lại panel sau lượt gián đoạn, đọc yêu cầu kiểm tra thủ công; không có tiếp tục job cũ hoặc bỏ guard.
7. Kiểm Preview, Play, Save, caption/voice và điểm cắt của cả hai workflow. Chỉ nghiệm thu sau kết quả nhìn/nghe thật.

## Gói thử và đối chiếu sau đóng gói

- ZIP: `dist/Premiere-Voice-Sync-2.20.30-Panel.zip`, 466,03 MiB. Exact allowlist và toàn bộ 57 file trong archive khớp checksum của staging, không có file thừa/thiếu/trùng.
- SHA-256: `7DFB5BFC6AEACF1E213DDF47C4EE028CD306AA2D1075F2A55B04A512817AC8B4`.
- Microsoft Defender đang bật, signature `1.461.31.0`; lệnh quét ZIP và thư mục gói đã hoàn tất, không ghi nhận phát hiện mới. Đây không phải chứng nhận an toàn.
- Trước cài: panel 2.20.27 có 48/48 file khớp gói nền. ZIP khôi phục 2.20.27 vẫn có SHA-256 `F19642C0FECD169EB61932EE1E9F7A68C6E7908CA51D61EEF75FC99C1787303A`.
- Diff của các file engine/executor hiện hữu rỗng; helper thông báo là file mới. Giai đoạn kiểm thử/đóng gói không cập nhật panel thật hoặc thao tác timeline.

## Cài thử thực tế sau khi được đồng ý

- Người dùng yêu cầu tiếp tục bước cài/kiểm tra; kiểm tra Premiere đã đóng trước khi chạy bộ cài thật. Không tự đóng Premiere.
- Kiểm lại whole-ZIP SHA-256, exact package allowlist và panel cũ trước khi cài. Bộ cài vẫn bật kiểm process, checksum, staging và rollback.
- Đường dẫn được truyền rõ ràng: `%USERPROFILE%/AppData/Roaming` và `%USERPROFILE%/AppData/Local`, tránh LOCALAPPDATA bị chuyển sang vùng sandbox của tiến trình kiểm thử.
- Kết quả: `INSTALLATION_VERIFIED:version=2.20.30;installed-files=49;preserved-files=619;preserved-directories=24`.
- Toàn bộ 619 file trong vùng dữ liệu PremiereVoiceSync (cache/model/backend/jobs/backups/logs và các file quản lý hiện hữu) giữ nguyên hash/kích thước; 24 thư mục giữ nguyên. Panel mới khớp 49/49 file dự kiến, không có file thừa.
- Bằng chứng cục bộ: `dist/_installation-2.20.30-20261015-130935/before.json` và `verified.json`. Snapshot chứa đường dẫn riêng, chỉ lưu trong dist bị Git bỏ qua, không nằm trong ZIP phát hành.
- Đã dùng Computer Use để tìm ứng dụng có sẵn. Yêu cầu mở Premiere bị từ chối với thông báo `Computer Use was not approved to use Adobe Premiere Pro 2026`. Không dùng cách điều khiển khác để vượt quyền này.
- Chưa có chứng cứ kiểm giao diện/foreground/taskbar/Preview/Play/Save trong Premiere ở lần cài này. Các bước nghiệm thu trên vẫn còn cần thực hiện trong app thật.
