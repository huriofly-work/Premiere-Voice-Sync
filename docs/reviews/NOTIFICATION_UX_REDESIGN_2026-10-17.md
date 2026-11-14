# Tinh gọn thông báo và giao diện Premiere Voice Sync

Ngày rà soát: 17/10/2026. Mã nguồn hiện tại: 2.20.64.

Trạng thái: người dùng đã duyệt bằng “Tiếp tục”; triển khai ở 2.20.65. Nội dung bên dưới ghi lại phương án đã duyệt; kết quả triển khai và kiểm chứng nằm trong `NOTIFICATIONS_2.20.65.md`. Đây không phải nghiệm thu giao diện native trong Premiere.

## 1. Mục tiêu

Người dùng mở chương trình phải hiểu cần chọn gì, bấm gì và sau khi chạy cần làm gì. Chỉ đưa thông tin ra cảnh báo khi có việc cụ thể cần chú ý; chỉ yêu cầu phê duyệt khi có quyết định thực sự về thay đổi hoặc khôi phục dữ liệu.

Không chỉ rút ngắn câu chữ: phải sửa cả cách phân loại sự kiện, vị trí hiển thị và số lần làm gián đoạn.

## 2. Những vấn đề đã xác minh từ mã nguồn

| Hiện trạng | Bằng chứng | Hệ quả |
| --- | --- | --- |
| Mức nhật ký quyết định cảnh báo kết quả | `main.js`: `log()` tự gọi `runWarning()` với mọi dòng `warn`; `finishRunNotice()` coi bất kỳ cảnh báo nào là kết quả cần kiểm tra | Thông tin thuật toán và trường hợp đã tự xử lý có thể làm kết quả chuyển vàng dù không có việc người dùng cần làm |
| Nhiều phản hồi nhỏ dùng chung hệ thống thông báo | Khôi phục mặc định, xuất log, chẩn đoán thành công, kiểm tra đầu vào thành công đều gọi `showWorkflowNotice()` | Người dùng phải phân biệt quá nhiều thông báo ít giá trị |
| Kết quả chứa nhiều lớp thông tin | Chuỗi hoàn tất dựng chứa số câu, đoạn dựng, caption, speed, frame, DTW, gộp hình; kết quả phụ đề nối thêm phạm vi SRT, cue và nhận diện bổ sung | Khó tìm được hành động tiếp theo |
| Một renderer cho nhiều loại bề mặt | Policy trả `result-card`/`banner`, nhưng `displayNotice()` vẫn dùng khung `.workflow-notice` cố định phía dưới cho các loại ngoài lỗi tại trường | Có phân loại trong policy nhưng giao diện vẫn tạo cảm giác mọi thứ là thông báo nổi |
| Khung thông báo khai báo bảy loại nút | `index.html`: chọn SRT, cửa sổ riêng, kiểm tra đầu vào, xem log, xuất log, đóng, tiếp tục | Từng tình huống có ẩn bớt nút, nhưng vẫn dễ có nhiều lựa chọn cạnh tranh |
| Thông tin kỹ thuật xuất hiện trong luồng chính | Nội dung focus/toast/Windows, CPU/GPU, timestamp, DTW, cue và trạng thái helper | Người mới phải hiểu cơ chế triển khai trước khi dùng được |
| Hoàn tất chạy nền có thể gửi Windows dù không cần xử lý | Policy hiện cho phép toast khi thời gian chạy từ 30 giây | Tác vụ thành công bình thường vẫn có thể gây gián đoạn |
| Lỗi thô còn được đưa vào trạng thái chính | `reportRunFailure()` gọi `status(raw, "error")` ở lỗi không gắn với trường | Có thể hiện mã lỗi kỹ thuật dù thông báo chính đã có câu giải thích dễ hiểu |

Toast Windows hiện đã dùng câu ngắn cố định trong `NotificationHost.cs`; không coi toast đang chứa toàn bộ nhật ký. Phần cần tinh gọn thêm là điều kiện gửi và nội dung khung panel/cửa sổ xem riêng.

## 3. Quy tắc phân loại mới

| Tình huống | Hiển thị mặc định | Phê duyệt / gây gián đoạn |
| --- | --- | --- |
| Thiếu hoặc sai SRT, nguồn audio, phạm vi, tham số | Một câu ngay cạnh mục cần sửa; mở nhóm đang thu gọn và đưa đến mục đó | Không popup, không toast |
| Đang kiểm tra, nhận diện, dựng hoặc thêm phụ đề | Một vùng tiến trình trong panel: bước hiện tại và trạng thái | Không yêu cầu xác nhận |
| Đã khôi phục mặc định / xuất log / kiểm tra đầu vào | Phản hồi ngắn cạnh thao tác; đường dẫn log ở phần hỗ trợ | Không đưa vào lịch sử cảnh báo hay tăng số chưa xem |
| Hoàn tất bình thường | Thẻ kết quả ngay dưới nút chạy; thông tin chưa lưu đặt tại đây | Không popup; mặc định không toast dù chạy lâu |
| GPU lỗi nhưng CPU hoàn tất và kết quả qua kiểm tra | Cập nhật bộ xử lý trong thiết lập/nhật ký | Không mặc nhiên báo cần kiểm tra chất lượng |
| Thuật toán đã xử lý được và hậu kiểm đạt | Nhật ký; chi tiết kết quả khi chủ động mở | Không mặc nhiên coi là vấn đề người dùng phải xử lý |
| Có vùng phụ đề hoặc tốc độ hình cần xem lại | Một mục “Cần kiểm tra” trong kết quả: lý do chính, vị trí và hành động | Không bắt bấm “Đồng ý”; chạy nền có thể nhắc một lần vì có việc cần làm |
| Không tạo được marker tại vùng cần kiểm tra | Giữ vấn đề trong danh sách với timecode/phụ đề tương ứng, nói rõ thiếu marker | Không báo an toàn chỉ vì không có marker |
| Không dọn hết file tạm nhưng tác vụ thành công, không ảnh hưởng khôi phục | Nhật ký/hỗ trợ | Không đổi toàn bộ tác vụ thành “cần kiểm tra”; nếu thực sự cản lần chạy sau thì nâng thành lỗi cần xử lý |
| Lỗi khiến tác vụ không thể hoàn tất, chưa sửa dữ liệu | Thẻ lỗi tại khu vực tác vụ, nêu nguyên nhân và bước sửa | Không bắt xác nhận đã đọc; nhắc nền một lần nếu cần người dùng quay lại xử lý |
| Lỗi/dừng khi dữ liệu đã thay đổi hoặc chưa xác minh được | Cảnh báo nổi bật cố định trong panel; giữ khóa chạy lại và hướng kiểm tra/khôi phục | Đây là thông tin quan trọng; không được làm mất khi đóng cảnh báo |
| Chuẩn bị dựng trực tiếp timeline | Một xác nhận ngắn về sequence, phạm vi thay đổi và việc chưa tự lưu | Giữ một lần phê duyệt có ý nghĩa trước khi dựng |
| Chỉ tạo phụ đề theo nguồn/phạm vi đã chọn | Tóm tắt nguồn/phạm vi/SRT và việc thêm track mới ngay trước nút chạy | Bấm “Tạo phụ đề” đủ thể hiện ý định; không thêm hộp xác nhận bình thường |
| Xóa cache nhận diện | Xác nhận ngắn nêu dữ liệu bị xóa và lần sau phải nhận diện lại | Giữ xác nhận; không thêm thông báo thành công riêng |
| Tiếp tục sau lỗi nhưng không tự xác minh được trạng thái | Nêu cụ thể cần kiểm tra điều gì; xác nhận khi người dùng chủ động yêu cầu tiếp tục | Giữ xác nhận thủ công cần thiết; xác nhận không thay thế kiểm đầu vào còn thực hiện được |
| Chưa có phản hồi mới từ Premiere/engine | Cập nhật trong vùng tiến trình; giải thích tác vụ có thể còn chạy | Không suy ra đã treo; không báo lỗi liên tục hay cho chạy đè |

“Cần chú ý” và “cần phê duyệt” là hai điều kiện độc lập. Vùng cần nghe lại là công việc kiểm tra kết quả, không phải quyết định cho phép chương trình làm tiếp.

## 4. Bố cục giao diện

Giữ hai chế độ; thống nhất nhãn phụ đề thành “Tạo phụ đề” trong giao diện tiếng Việt. Giữ thuật ngữ voice ở nơi người dùng đã quen.

Thứ tự chính của mỗi chế độ:

1. **Nguồn**: sequence đang dùng, nguồn audio/track/phạm vi hoặc điều kiện V1/A1/A2 của dựng; SRT đang chọn và ngôn ngữ. Chỉ giải thích ngắn điều ảnh hưởng lựa chọn hiện tại. Phải thấy SRT do chương trình chọn tự động để kiểm tra trước khi chạy.
2. **Tùy chọn**: thông số phổ biến; nối nhiều SRT và ngưỡng chuyên sâu mở khi cần. Khi bật nối SRT, danh sách/thứ tự file phải nhìn thấy, không giấu đầu vào đang có hiệu lực.
3. **Chạy**: một nút hành động chính cho chế độ hiện tại, một vùng tiến trình/kết quả. Khi đang chạy mới hiện Tạm dừng và Dừng tác vụ; chỉ hiện lời giải thích tương ứng trạng thái.
4. **Phần phụ thu gọn**: Thiết lập, Hướng dẫn, Hỗ trợ và nhật ký. Lịch sử cảnh báo đặt ở phần phụ, không đứng trên đầu luồng nhập liệu.

Chuyển giải thích CPU/GPU, toast, focus, helper và thông tin hỗ trợ vào phần phù hợp. Trên màn hình chính chỉ giữ trạng thái bộ xử lý nếu nó ngăn chạy hoặc cần người dùng xử lý.

Hướng dẫn đầu tiên ngắn, không mở modal: “Chọn nguồn → Kiểm tra SRT và phạm vi → Chạy”. Với dựng, vẫn phải thấy yêu cầu template và thay đổi trực tiếp timeline; với phụ đề, vẫn phải thấy việc thêm Caption Track mới. Không ẩn hệ quả quan trọng dưới phần kỹ thuật.

## 5. Quy chuẩn câu chữ và ví dụ

Mỗi thông báo chính có một tiêu đề nói kết quả/vấn đề, tối đa hai câu ngắn và tối đa hai nút hành động. Một liên kết “Chi tiết” mở riêng phần hỗ trợ; không đưa thêm hàng nút log vào hộp quyết định. Không cắt chuỗi tự động để đạt số ký tự vì có thể làm mất hệ quả quan trọng.

Không dùng DTW, schema, metadata, executor, cue nguồn hoặc đường dẫn đầy đủ trong nội dung mặc định. Giữ các dữ liệu đó trong báo cáo kỹ thuật. Nếu thực sự cần xác định file, dùng tên file; nếu cần xác định lỗi kết quả, dùng phụ đề đầu ra/timecode.

Ví dụ với dữ liệu minh họa, không phải kết quả của một lần chạy thật:

| Trường hợp | Nội dung đề xuất | Hành động |
| --- | --- | --- |
| Thiếu SRT | “Chọn file SRT dùng để tạo voice.” | Chọn ngay tại trường SRT |
| Xác nhận dựng | **Dựng sequence “Video mẫu”?** — “Chương trình sẽ dựng lại hình và audio theo voice, đồng thời thêm phụ đề. Hãy lưu bản hiện tại trước khi bắt đầu; chương trình không tự lưu.” | Hủy / Bắt đầu dựng |
| Phụ đề hoàn tất | **Đã tạo 120 phụ đề.** — “Project chưa được lưu.” | Chi tiết kết quả nếu cần; không nút xác nhận |
| Cần nghe lại | **Có 3 vị trí cần nghe lại.** — “Kiểm tra phần chữ tự nhận diện tại các vị trí được đánh dấu.” | Xem vị trí cần kiểm tra |
| Dựng hoàn tất | **Đã dựng xong.** — “Xem và nghe lại trước khi lưu project.” | Chi tiết kết quả nếu cần |
| Nhận diện lỗi, chưa sửa dữ liệu | **Chưa tạo được phụ đề.** — “Không đọc được file audio nguồn. Kiểm tra file nguồn rồi cập nhật đầu vào.” | Cập nhật đầu vào |
| Lỗi sau khi đã sửa timeline | **Timeline cần được kiểm tra.** — “Tác vụ dừng khi timeline đã thay đổi. Kiểm tra hoặc khôi phục bản đã lưu trước khi chạy lại.” | Xác minh sau khôi phục / Chi tiết |
| Chưa biết đã thêm caption hay chưa | **Chưa xác minh được kết quả tạo phụ đề.** — “Kiểm tra Caption Track và trạng thái audio trước khi chạy lại.” | Kiểm tra để tiếp tục / Chi tiết |
| Xóa cache | **Xóa cache nhận diện?** — “Các kết quả nhận diện đã lưu sẽ bị xóa. Lần chạy sau cần nhận diện lại.” | Hủy / Xóa cache |
| Windows khi cần xử lý | **Tạo phụ đề cần bạn kiểm tra.** — “Mở chương trình để xem phần cần xử lý.” | Mở panel |

Các ví dụ không được làm lời hứa “chưa thay đổi” khi dữ liệu thực tế chỉ cho biết chưa xác minh. Không dùng câu chung chung “Có cảnh báo” nếu đã có thể nêu việc cần làm.

## 6. Cách sửa mã

1. Tách dữ liệu nhật ký khỏi dữ liệu vấn đề cần hành động. `log(..., "warn")` không tự tạo vấn đề hiển thị. Rà soát toàn bộ nơi gọi, không chỉ bỏ dòng gom cảnh báo: mọi lỗi/chất lượng còn cần chú ý phải được chuyển rõ sang vấn đề có cấu trúc.
2. Mỗi vấn đề có mã, mức ảnh hưởng, việc cần làm, phạm vi đầu ra, khả năng chặn chạy lại và trạng thái xử lý. Quyết định hiển thị dựa vào các trường này, không dựa vào màu hoặc số dòng log.
3. Nhóm các vấn đề trùng phạm vi/lý do. Số vị trí cần kiểm tra lấy từ phạm vi đầu ra đã hợp nhất; không cộng cơ học số marker + số lỗi speed + số cue nguồn. Marker xanh dương thông tin gộp hình không tính vào mục cần xử lý. Phân biệt caption đầu ra, cue SRT và đoạn phân tích.
4. Policy phân biệt phản hồi tại trường, trạng thái, kết quả, vấn đề cần xử lý và quyết định. Renderer tạo đúng các vùng này; kết quả thông thường không còn là khung nổi che giao diện.
5. Mỗi sự cố chỉ có một mục chính. Nhật ký và kết quả bổ sung cập nhật mục đó; lỗi dọn file không đẩy lỗi chính xuống dưới hoặc mở hộp kế tiếp.
6. Xem/đóng thông báo chỉ đánh dấu đã đọc; không đồng nghĩa vấn đề đã khắc phục hoặc cho phép chạy lại. Đóng cảnh báo quan trọng vẫn giữ chỉ báo và khóa phục hồi. Mở lịch sử không gửi lại toast.
7. Windows chỉ nhắc khi tác vụ nền cần quyết định, không hoàn tất được hoặc có kết quả cần xem lại. Không nhắc hoàn tất bình thường mặc định. Mặc định mới không tự chuyển focus; giữ lựa chọn focus đã lưu của người đang dùng, nhưng chỉ áp dụng cho sự kiện quan trọng. Không chuyển focus và gửi nhiều kênh cùng lúc cho một sự cố.
8. Không lưu lời thoại/đường dẫn thô vào lịch sử mới. Giữ đọc được lịch sử cũ; thông báo lịch sử chung chung chỉ là mục lưu trữ, không tự trở thành việc đang chờ xử lý. Toast/callback cũ không được tái kích hoạt việc chạy.

Các tệp dự kiến: `extension/js/main.js`, `extension/js/notification-policy.js`, `extension/js/native-notifications.js`, `extension/index.html`, `extension/css/styles.css`; chỉ sửa `NotificationHost.cs` nếu cần đồng bộ nội dung/trạng thái. Cập nhật kiểm thử và hướng dẫn tương ứng. Không cần đổi thuật toán nhận diện/căn thời gian để làm đợt UX này.

## 7. Các ràng buộc phải giữ

- Chặn chạy đè khi thao tác cũ chưa kết thúc; giữ kiểm thay đổi sequence/timeline và phân biệt chưa sửa / đã sửa / chưa xác minh.
- Giữ phục hồi mute, clip enable và In/Out; không coi API `captionTracks` vắng mặt là không có caption.
- Không tự phê duyệt, dựng lại, Save, Undo, đóng Premiere hoặc sửa project để thử giao diện. Các nút xác minh phải tiếp tục kiểm điều kiện thật.
- Giữ nút Dừng/Tạm dừng và cơ chế chờ điểm an toàn. Không đưa checkpoint chẩn đoán vào luồng chạy thường.
- Không sửa dữ liệu project/cache/model/jobs/backups trong đợt thiết kế. Cài đặt sau khi duyệt phải theo quy trình bảo toàn dữ liệu hiện có.
- Lỗi chưa biết vẫn phải có thông báo dễ hiểu, trạng thái ảnh hưởng và cách mở chi tiết; không làm im mọi lỗi chưa nằm trong danh mục.

## 8. Trình tự và tiêu chí nghiệm thu

1. Duyệt phạm vi/chính sách trong tài liệu này.
2. Lập bảng các sự kiện tại từng chỗ gọi; triển khai phân loại và nội dung trước, rồi bố cục. Cập nhật hồi quy để kiểm hành vi có ý nghĩa thay vì buộc giữ câu chữ cũ.
3. Kiểm các tình huống: thành công thường; GPU tự khắc phục; thiếu SRT; nguồn rỗng; chất lượng cần xem lại; marker tạo thất bại; lỗi trước/sau mutation; trạng thái chưa xác minh; hủy trước/sau mutation; tạm dừng; cleanup lỗi; mở lại panel và callback cũ.
4. Kiểm bố cục mô phỏng ở rộng 320/385/560 px và DPI tương ứng: không tràn ngang/che nút chạy, keyboard/focus hợp lý, màu có nhãn chữ, công bố trạng thái cho trình đọc màn hình không lặp liên tục. Ví dụ “120 phụ đề / 3 vị trí” phải được sinh từ fixture thật và liên kết tới đúng danh sách.
5. Kiểm toàn bộ hồi quy liên quan và suite dự án; phân biệt rõ kiểm Windows bị bỏ qua. Build/kiểm payload, encoding, manifest và cài theo quy trình đã xác minh sau khi phần triển khai được duyệt và điều kiện cài đáp ứng.
6. Nghiệm thu trong Premiere bằng project sao lưu: dựng và phụ đề, panel hiện/ẩn, Windows DND/tắt thông báo, không tự phê duyệt khi bấm toast, Play/Preview và Save do người dùng chủ động thực hiện. Bằng chứng mô phỏng không thay thế nghiệm thu này.

Tiêu chí đo cụ thể:

- Khôi phục mặc định, xuất log, quét/chẩn đoán thành công: **0 popup, 0 toast, 0 lần tăng số cảnh báo chưa xem**.
- Hoàn tất bình thường hoặc CPU xử lý thay GPU rồi đạt kiểm tra: **0 cảnh báo cần xử lý**, một thẻ kết quả; không toast mặc định.
- Dựng bình thường: **1 phê duyệt trước thay đổi**, không thêm hộp “đã hiểu” sau thành công. Tạo phụ đề bình thường: **0 hộp phê duyệt thêm**.
- Sai đầu vào: chỉ rõ đúng mục cần sửa; không đẩy raw exception vào thanh trạng thái hay lặp thành cảnh báo nổi.
- Mỗi sự cố nền chưa xử lý: **tối đa 1 lần nhắc**; cập nhật chi tiết không gửi lại. Sự cố mới có ảnh hưởng cao hơn phải được xử lý theo danh tính riêng.
- Kết quả cần xem lại: một tóm tắt việc cần làm; danh sách chỉ đúng caption/timecode, không mất cảnh báo khi tạo marker thất bại.
- Lỗi đã sửa/chưa xác minh: không thể vượt khóa bằng Đóng, Escape, xem lịch sử hoặc bấm toast; xác nhận còn chờ không bị thông báo khác ghi đè.
- Thông báo mặc định: tối đa hai câu ngắn và hai nút; raw error, số liệu kỹ thuật và đường dẫn hỗ trợ chỉ hiện khi mở chi tiết.

Không gọi thiết kế “tối ưu đã nghiệm thu” cho tới khi hoàn tất kiểm thực tế. Rà soát hiện tại chưa chạy test chương trình vì chưa sửa mã.

## 9. Cơ sở thiết kế

Các quy tắc áp dụng ở trên là lựa chọn cho Premiere Voice Sync từ yêu cầu người dùng và đánh giá mã nguồn; không coi giới hạn hai câu/hai nút là tiêu chuẩn bắt buộc của Windows.

- [Microsoft: Notifications design basics](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-ux-guidance): thông báo có mục đích rõ, giảm nhiễu, mở đúng ngữ cảnh và dọn thông báo cũ.
- [Microsoft: Dialog controls](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs): dùng hộp thoại cho thông tin/quyết định quan trọng; câu chữ đơn giản, nút nêu hành động cụ thể, lỗi trường đặt tại trường.
- [Microsoft: InfoBar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar): phản hồi trạng thái quan trọng có thể nằm trong bố cục mà không che nội dung; không dùng cho thông tin không thiết yếu.
