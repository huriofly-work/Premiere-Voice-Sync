# Hướng dẫn Premiere Voice Sync 2.20.90

**2.20.90:** model nhận diện đổi sang Whisper large-v3-turbo (thay Small), chính xác hơn với tiếng Việt. ZIP khoảng 1,6 GB; chạy CPU chậm hơn khoảng 2 lần nên máy NVIDIA nên bật tải backend GPU. Xem [phạm vi và kiểm chứng](releases/notes/ASR_TURBO_2.20.90.md).

**2.20.77:** giữ đuôi primary DTW đủ căn cứ khi lượt bổ sung bị suy giảm về timing ước lượng; sửa cụt đầu outro Medium và lời sai Turbo trong phép dựng ngoại tuyến. Model mặc định vẫn Small. Xem [phạm vi và kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.77.md).

**2.20.76:** giữ đuôi ASR ban đầu đã qua kiểm timing/âm thanh khi lượt nhận diện bổ sung bị mất lời; giữ nguyên các câu SRT và model Small. Xem [nguyên nhân và kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.76.md).

**2.20.75:** tách adapter nhận diện để chuẩn bị nâng model tiếng Việt; giữ nguyên Small và kết quả caption baseline. Chưa sửa chính tả voice ngoài SRT. Xem [phạm vi và kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.75.md).

**2.20.74:** giữ chữ SRT qua số/đơn vị ASR viết gộp và nhận diện lại câu ngắn với ngữ cảnh đã xác minh; thêm sổ bộ nhớ hồi quy của project. Nghiệm thu Premiere còn chờ. Xem [chi tiết và kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.74.md).

**2.20.73:** sửa căn từ dấu/đơn vị và câu phân số khi giữ chữ SRT; bản dựng ngoại tuyến Nam Cực tăng từ 250 lên 253/255 câu. Hai câu còn mở, nghiệm thu Premiere còn chờ. Xem [chi tiết và kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.73.md).

**2.20.71:** thêm tùy chọn âm thanh mặc định bật cho thông báo Windows; phát một lần cùng thông báo hoàn tất hoặc cần xử lý, có thể tắt trong Thiết lập. Xem [chi tiết và kiểm chứng](releases/notes/NOTIFICATIONS_2.20.71.md).

Trong **Thiết lập**, dùng **Phát âm thanh khi hoàn tất hoặc cần xử lý** để bật/tắt riêng tiếng báo. Âm thanh mặc định bật, phát một lần cùng thông báo Windows ở nền; không phát riêng khi đang xem kết quả trong panel. Tắt nhắc Windows sẽ vô hiệu hóa mục âm thanh nhưng vẫn giữ lựa chọn đã lưu. **Hỗ trợ và nhật ký → Thử thông báo Windows** dùng thiết lập âm thanh hiện tại. Âm lượng, quyền phát tiếng và Không làm phiền vẫn theo Windows.

**2.20.70:** panel là nơi duy nhất xem và xử lý kết quả; Windows chỉ nhắc khi tác vụ hoàn tất hoặc cần xử lý ở nền. Bỏ cửa sổ xem riêng và tự giành focus. Xem [chi tiết và kiểm chứng](releases/notes/NOTIFICATIONS_2.20.70.md).

**2.20.68:** thông báo Windows khi dựng hoặc tạo phụ đề chạy nền đã hoàn tất, kể cả thành công bình thường. Bấm thông báo để quay lại panel xem kết quả. Xem [chi tiết và kiểm chứng](releases/notes/NOTIFICATIONS_2.20.68.md).

**2.20.67:** giữ nhãn một chữ như A., C. từ SRT khi nhận diện khớp chữ và hai câu lân cận xác định đúng vị trí; không báo nhầm là lời ngoài SRT. Xem [chi tiết và kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.67.md).

**2.20.66:** SRT đơn/nối nhiều file ở cùng một chỗ; chọn từng file Project, tìm theo tên và thu gọn danh sách. Audio mặc định ưu tiên clip đang chọn; mở **Đổi nguồn hoặc phạm vi audio** khi cần tự chọn. Xem [chi tiết](releases/notes/SRT_JOIN_2.20.66.md).

**2.20.63:** Dựng theo voice có **Ngôn ngữ voice**. Chọn tiếng nói thực tế, hoặc Tự nhận diện ngôn ngữ; SRT phải cùng ngôn ngữ với voice. Tool giữ chữ và căn thời gian, không dịch. Thiết lập lưu riêng với ngôn ngữ của Tạo phụ đề. Xem [chi tiết](releases/notes/SRT_JOIN_2.20.63.md).

**2.20.62:** nhận ra câu thì giữ nguyên chữ SRT, kể cả phần số. Không tạo marker “Cần đối chiếu số đọc” hoặc cảnh báo hoàn tất vì khác cách ghi số. Căn thời gian quanh số vẫn dùng từ đứng trước và đáy năng lượng âm thanh. Chạy lại workflow để áp dụng cho caption/marker mới. Xem [chi tiết](releases/notes/REVIEW_MARKERS_2.20.62.md).

**2.20.61:** Short dùng một phần SRT dài vẫn giữ câu cuối còn khớp; chỉ bổ sung phần lời tiếp theo không có trong SRT. Xem [chi tiết và bằng chứng](releases/notes/SUBTITLE_TIMING_2.20.61.md).

**2.20.60:** không còn marker “Chưa xác minh timing của số”. Từ nghe sai ở biên câu SRT đã nhận ra được loại khỏi phần bổ sung; marker bổ sung trích chữ và ghi số caption thực cần xem. Cài đặt không tự sửa caption/marker cũ; chạy lại tạo subtitle để áp dụng. Xem [chi tiết và bằng chứng](releases/notes/SUBTITLE_TIMING_2.20.60.md).

**Subtitle 2.20.59:** nhận ra câu thì giữ nguyên chữ SRT; không thay cả câu bằng ASR vì sai vài từ. Câu lặp có ngữ cảnh phân biệt vẫn giữ đúng vị trí. Timing được kiểm riêng; không báo marker giữ chữ SRT. Chạy lại workflow để áp dụng cho caption mới. Xem [chi tiết](releases/notes/SUBTITLE_TIMING_2.20.59.md).

**Nối nhiều SRT:** bật **Nối nhiều file SRT** ngay trong khung **File SRT**. Chỉ giữ file đơn hiện tại làm file đầu, không tự thêm tất cả Project. **Chọn từ Project** mở danh sách có tìm tên và checkbox từng file; **Chọn từ máy** thêm file ngoài. **Danh sách đã chọn · N file** mặc định thu gọn; mở để xem thứ tự, dùng ↑/↓ để di chuyển và × để bỏ. Danh sách dài có thanh cuộn. Tắt nối khôi phục lựa chọn đơn trước đó; file gốc giữ nguyên. Xem [chi tiết](releases/notes/SRT_JOIN_2.20.66.md).

**Giữ timestamp gốc** dành cho các SRT cùng trục thời gian hình nguồn, không chồng/đảo thứ tự. **Nối tiếp thời gian từng file** cộng thời gian kết thúc file trước vào cue của file sau, giữ khoảng nghỉ đầu file. Ví dụ file trước kết thúc 00:40, file sau bắt đầu 00:01 thì cue sau bắt đầu 00:41. Khi Dựng theo voice, chỉ dùng nếu mốc sau nối tương ứng với hình nguồn; thời gian kết thúc subtitle có thể sớm hơn kết thúc video. Tạo phụ đề căn timestamp mới theo audio.

2.20.53 sửa lỗi nạp planner audio trước khi xuất WAV. Lưu công việc và đóng Premiere trước khi cài; sau cài mở lại, bấm Cập nhật đầu vào rồi chạy lại. Xem [bản sửa](releases/notes/NOTIFICATIONS_2.20.53.md).

Voice đã bỏ nhiều câu so với SRT: giữ SRT gốc có timestamp khớp hình và chọn voice hiện tại. Subtitle giữ chữ phần còn đọc; Auto edit kiểm tra lại vùng nối và bỏ hình/A1 của cue đã lược bỏ. Cắt giữa cue hoặc câu lặp chưa rõ vị trí có thể cần chỉnh SRT trước khi dựng. Xem [hướng dẫn và giới hạn](releases/notes/EDITED_VOICE_2.20.51.md). Chưa nghiệm thu bản mới trong Premiere.

Bản 2.20.50 bổ sung ba nguồn audio, chọn nhiều track và phạm vi thời gian riêng cho Tạo phụ đề; lựa chọn thủ công không bị thay khi trống. Tool ghi nhật ký trước khi cô lập nguồn và khôi phục mute/enable/In/Out sau xuất. Xem [phạm vi và kiểm chứng](releases/notes/NOTIFICATIONS_2.20.50.md).

Bản 2.20.49 ưu tiên SRT trong Project cho Tạo phụ đề khi có một ứng viên rõ ràng; giữ lựa chọn thủ công, kể cả không dùng SRT. Xem [phạm vi và kiểm chứng](releases/notes/SRT_PRIORITY_2.20.49.md).

Bản 2.20.48 sửa marker số trỏ vào đầu đoạn phân tích dài: marker nay trỏ caption đầu ra có chứa số, ghi số cần kiểm tra và trích nguyên caption. `Caption N` là số trong SRT đầu ra; `SRT N` khi có là cue nguồn tham chiếu. Các cảnh báo ở mức cả đoạn ghi `Đoạn phân tích N`, không phải số caption trên timeline. Chưa xác minh timing không có nghĩa là đã phát hiện đọc sai số. Marker cũ đã có trong project không tự đổi sau cập nhật. Xem [phạm vi và kiểm chứng](releases/notes/REVIEW_MARKERS_2.20.48.md).

Bản 2.20.43 sửa timing Tạo phụ đề: nhận diện lại riêng cửa sổ DTW lỗi, giữ mốc tốt của phần còn lại và tìm đáy sóng âm gần từ đứng trước ranh giới, kể cả trước số. Nhật ký báo rõ vùng phải dùng timing ước lượng cấp câu. Những phần thiếu/khác và lời ngoài SRT tiếp tục được bổ sung; nội suy cue chỉ dùng trong Auto edit. Xem [chi tiết kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.43.md).

Bản 2.20.40 sửa giới hạn SRT dài của **Tạo phụ đề**. Phần khớp giữ chữ SRT; phần thiếu hoặc không khớp, mở đầu/kết thúc và lời đăng ký kênh được nhận diện bổ sung trong vùng audio đang chọn rồi ghép vào cùng kết quả. SRT gốc giữ nguyên. Nếu không tìm được đoạn SRT khớp an toàn, dùng nhận diện cho vùng audio đó. Nghe lại phần chữ tự nhận diện; các vùng đã thử nhưng không tìm được lời được báo trong log. Xem [chi tiết 2.20.40](releases/notes/NOTIFICATIONS_2.20.40.md).

Bản 2.20.39 có **Tạm dừng / Tiếp tục** và **Dừng tác vụ** cho cả hai chế độ. Bấm Tạm dừng rồi chờ **Đã tạm dừng**; nhận diện cần xong script hiện tại, xuất WAV cần xong phiên xuất và khôi phục mute/In/Out, dựng timeline nghỉ giữa các lượt host. Không sửa timeline, đổi project/sequence hoặc mở lại panel trong lúc nghỉ. Có thể nghe/xem kiểm tra, nhưng dừng phát trước khi bấm Tiếp tục. Tool so sánh trạng thái rồi làm tiếp; nếu thay đổi/không đọc được thì chặn và báo kiểm tra. Các bước nhận diện đã xong không bị chạy lại. **Dừng tác vụ** vẫn dùng được khi đang nghỉ và không tự hoàn tác timeline. Xem [kiểm thử và giới hạn 2.20.39](releases/notes/NOTIFICATIONS_2.20.39.md). Cài khi Premiere đã đóng; cần nghiệm thu trên Premiere thật.

Bản 2.20.27 giữ giao diện 2.20.26 và sửa trường hợp hai ranh giới chọn trùng điểm nghỉ. Nếu điểm cắt làm một phía mất thời lượng trên lưới frame, tool giữ câu chung trong một đoạn thay vì tạo clip 1 frame. Nhận diện/caption, gộp hình và executor không đổi; guard bảo toàn voice vẫn giữ. Bản này chờ kiểm thử trong Premiere; main/Release đã nghiệm thu vẫn là 2.20.25.

Auto edit mặc định dựng liên tục theo nhóm, không đặt thời gian chờ giữa các đợt hoặc giới hạn số thao tác/thời lượng mỗi đợt. Vẫn giữ kiểm tra an toàn và không tự lưu project. Bấm nút dựng như trước; không còn hộp cảnh báo bản thử hoặc lựa chọn bật/tắt lịch chạy. Luôn giữ template đã lưu và không chỉnh timeline khi tool đang chạy. Sau hoàn tất kiểm kết quả, Preview/Play và Save. Tạo phụ đề không thay đổi. Có thể cài lại ZIP 2.20.20 để quay về lịch chạy cũ nếu cần, giữ cache/model.

## Cài đặt và mở panel

1. Đóng Premiere Pro trước khi cài.
2. Giải nén đầy đủ `Premiere-Voice-Sync-2.20.34-Panel.zip`, mở thư mục vừa giải nén và chạy **Setup-Panel.cmd** (Thiết lập panel). Không cần quyền Administrator.
3. Mở Premiere Pro 26.x trên Windows, vào **Window > Extensions (Legacy) > Premiere Voice Sync**.

Panel có hai chức năng. Chọn chức năng ở hai nút trên cùng.

Tiến trình, kết quả và lỗi thay nhau trong cùng vùng dưới nút chạy. Quyết định cần phê duyệt hiện tại đây: dựng trực tiếp timeline, xóa cache hoặc kiểm tra thủ công sau sự cố. Trước khi dựng, chọn **Bắt đầu dựng** hoặc **Hủy**; chương trình chưa nhận diện/dựng trước khi bạn đồng ý. Tạo phụ đề bình thường không có xác nhận bổ sung.

Khi đang xem kết quả trong panel, chương trình không nhắc ra ngoài. Nếu đang dùng ứng dụng khác, hoàn tất/lỗi/cần quyết định/dừng xong được nhắc một lần qua Windows khi bật **Nhắc khi hoàn tất hoặc cần tôi xử lý**. Bấm thông báo để mở đúng kết quả; không tự phê duyệt hoặc chạy lại. Đọc kết quả sẽ dọn toast, không đóng kết quả hay gỡ khóa phục hồi. Không có cửa sổ xem riêng hoặc tự đưa Premiere lên trước. Windows vẫn quyết định hiển thị theo quyền thông báo/Không làm phiền; có thể dùng **Hỗ trợ và nhật ký → Thử thông báo Windows** để kiểm độc lập.

Nếu có vấn đề chất lượng, bấm **Xem vị trí cần kiểm tra** để xem phụ đề/timecode và lý do. Số liệu thuật toán và lỗi gốc nằm trong **Chi tiết → Thông tin kỹ thuật**. Đóng lỗi không tự gỡ khóa chạy lại sau sự cố. Không cần đóng kết quả mới dọn file tạm; project không tự lưu.

Trong panel chỉ hiển thị hướng dẫn sử dụng từng chức năng: **Dựng theo voice** có mục **Hướng dẫn dựng và màu marker**, **Tạo phụ đề** có mục **Hướng dẫn tạo phụ đề**. Hướng dẫn cài đặt, xử lý lỗi và gỡ cài đặt nằm trong tài liệu này, được kèm bộ cài dưới tên `HUONG_DAN_SU_DUNG.md`.

Panel sắp theo **Chọn nguồn → Tùy chọn → Chạy và xem kết quả**. **Cập nhật đầu vào** đọc lại SRT và timeline của chế độ hiện tại, không thay đổi project; chương trình luôn kiểm đầu vào khi chạy. CPU/GPU và tùy chọn thông báo nằm trong **Thiết lập**. Lịch sử cảnh báo, hướng dẫn và **Hỗ trợ và nhật ký** ở phần phụ thu gọn.

Gói ZIP chứa sẵn Whisper CPU, FFmpeg, model và từ vựng offline; không cần cài riêng các tài nguyên đó. Panel được chép vào `%APPDATA%\Adobe\CEP\extensions\com.premierevoicesync.local`. Không tạo ứng dụng trong Windows Installed apps. Nếu máy có bản EXE cũ của chính tool, Setup-Panel.cmd chuyển sang bản ZIP và gỡ mục Installed apps cũ, giữ lại cache/model/backend. Nếu thông tin bản cũ không đúng với tool, tác vụ dừng thay vì xóa.

Giữ lại gói ZIP hoặc thư mục giải nén để dùng **Remove-Panel.cmd** (Gỡ panel) khi cần. Có thể chuyển thư mục giải nén sang ổ khác sau khi thiết lập vì Premiere dùng bản panel đã chép vào thư mục Adobe. Đây không phải portable hoàn toàn: tool vẫn ghi cấu hình CEP và dữ liệu trong AppData. Chỉ xóa thư mục ZIP không gỡ panel đã thiết lập.

## Tạo phụ đề

Dùng cho một sequence bất kỳ, kể cả video đã dựng xong; không cần template V1/A1/A2 hay voice dịch riêng.

1. Mở sequence cần tạo subtitle.
2. Chọn chế độ **Tạo phụ đề**. Mặc định **Tự động**: ưu tiên chính các clip audio đang chọn; nếu chỉ chọn video thì dùng khoảng thời gian đó với track gợi ý. Không có selection thì dùng toàn sequence, gợi ý A2 có audio hoặc track đầu có audio. Kiểm tra nguồn/phạm vi hiện trên tóm tắt; gợi ý track không phân biệt voice với nhạc.
3. Chọn **Phạm vi thời gian**: **Toàn sequence** bỏ qua selection và In/Out cũ; **Theo khoảng thời gian của clip đang chọn** lấy thời gian của các clip Video/Audio đã chọn nhưng nguồn vẫn theo chế độ nguồn; **Theo In/Out** yêu cầu In/Out hợp lệ. Nguồn clip audio tự dùng thời gian của chính các clip Audio, khóa phạm vi và danh sách track; video chọn kèm không mở rộng vùng. Vùng trùng được gộp, vùng rời nhau giữ đúng vị trí. Không có lựa chọn hợp lệ thì báo lỗi, không tự chuyển sang toàn sequence.
4. Kiểm tra tóm tắt trong **Timeline đang mở**. **Cập nhật đầu vào** đọc lại sau khi đổi lựa chọn. Khi chạy, nếu kế hoạch nguồn/phạm vi khác tóm tắt đang thấy, tool cập nhật tóm tắt và yêu cầu kiểm tra rồi bấm chạy lại. Chọn **Ngôn ngữ lời nói** phù hợp; subtitle giữ nguyên ngôn ngữ, không dịch.
5. **SRT có sẵn** tự ưu tiên file trong Project khi chỉ có một SRT hoặc có một file được xếp hạng cao hơn rõ ràng, như **Dựng theo voice**. Nếu nhiều file ngang nhau, hãy chọn từ danh sách hoặc **Chọn ngoài**. Kiểm tra SRT đúng ngôn ngữ và lời nói; chọn **Tự nhận diện · không dùng SRT** nếu muốn nhận diện toàn bộ. Lựa chọn thủ công, kể cả không dùng SRT, được giữ khi cập nhật đầu vào/chuyển chế độ trong phiên panel hiện tại. Có thể chọn SRT đầy đủ dù audio chỉ là một chapter: tool tự tìm phần khớp bằng lời nói, không dùng timestamp cũ để chọn phạm vi. Không dùng SRT dịch khác ngôn ngữ lời nói.
6. Giữ mặc định tối đa 42 ký tự hoặc chỉnh giới hạn theo bố cục video. Đây là giới hạn chữ, không phải phép đo chiều rộng font trên màn hình. Nếu dùng chữ Trung/Nhật/Hàn hoặc font lớn, giảm giới hạn để phù hợp khung hình.
7. Bấm **Tạo subtitle**. Tool xuất audio tạm của các vùng, nhận diện/căn lời rồi thêm một **Caption Track mới** đúng vị trí trên timeline.
8. Nghe lại, kiểm tra tên riêng, thuật ngữ và những đoạn có nhiều người nói hoặc nhạc lớn. Chỉnh style caption trong Premiere nếu cần, rồi tự lưu project.

Trong chế độ **Track do tôi chọn**, gợi ý ban đầu ưu tiên A2 có clip enabled giao phạm vi; nếu không, chọn track đầu tiên phù hợp. Ngay khi sửa checkbox, tập nguồn được giữ nguyên dù một track trống. Bỏ hết checkbox hoặc toàn tập nguồn rỗng thì báo lỗi; không tự chọn lại. Nếu track/thứ tự nguồn thay đổi và không còn xác minh được, hãy chọn lại. Gợi ý không phân biệt voice với nhạc. Cấu hình được giữ riêng theo project/sequence trong phiên panel, không áp chỉ số track của sequence trước sang sequence mới.

Nguồn track/clip chỉ định được mở tiếng tạm khi xuất, track khác được mute; clip đã disabled vẫn giữ disabled. Clip mode còn tạm disable clip không chọn trên cùng track. Tool lưu nhật ký trước khi thay đổi và khôi phục mute/enable/In/Out khi xong, lỗi hoặc hủy. Nếu không đọc/ghi/xác minh được cô lập thì dừng trước nhận diện/import. Nhiều nguồn được phối theo thời gian để nhận diện chung, chưa tách người nói hoặc tạo caption riêng cho từng track. Nhạc trộn sẵn trong nguồn vẫn còn. Cần nghiệm thu clip enable, nested, routing/effect/solo và nghe audio xuất trong Premiere thật; snapshot chưa bao phủ mọi tham số mixer/effect, không sửa timeline/effect trong lúc chạy.

Vùng không có clip audio enabled từ nguồn đã chọn được bỏ qua và báo trong tóm tắt; nếu tất cả vùng rỗng thì không chạy. Sau khi chốt job, đổi selection không thay nguồn/phạm vi job. Job còn nhật ký khôi phục được giữ lại, không bị tự dọn; sau lỗi/reload dùng **Đã kiểm tra/khôi phục — Xác minh đầu vào** để kiểm trạng thái. Nhật ký khác project/sequence hoặc cấu trúc timeline bị thay đổi không được tự áp dụng. Công cụ không tự Undo hoặc Save.

Video/audio không bị cắt, dịch chuyển hay đổi tốc độ. Caption cũ được giữ lại; chạy lại sẽ tạo thêm một track. File SRT và audio tạm được dọn sau tác vụ, không giữ SRT tạm trong Project. Project không tự lưu. Không sửa timeline trong lúc đang nhận diện; panel kiểm tra lại sequence trước khi thêm caption.

Tiếng Việt dùng cách chia caption theo dấu câu, khoảng nghỉ hơi và từ vựng offline. Dấu phẩy/chấm phẩy/hai chấm không buộc tách một cụm rất ngắn; giữ “Alien: Covenant” liền nhau khi còn đủ giới hạn ký tự. Hai chức năng dùng chung cách căn caption DTW theo token và khoảng nghỉ đo trên audio. Không dịch thời gian cố định để bù lỗi. Mép được nới tối đa 5 frame khi còn chỗ, chia phần trống và không chồng caption kề bên. Tiếng Trung/Nhật giữ cách chia theo ký tự. Nếu chưa xác minh được mốc mới, nhật ký báo vùng/cue cần nghe lại và giữ đường căn cũ. Chất lượng vẫn phụ thuộc lời nhận diện, giọng, tiếng ồn và cần nghe lại.

Với lời tiếng Việt, tool nhận diện lại cửa sổ ngắn quanh các cue có chữ số để hạn chế timestamp bị co ngắn khi một số được đọc thành nhiều âm tiết. Giữ nguyên chữ/số hiển thị, không đổi mốc dựng video/voice. Nhật ký báo cue đã căn riêng và cue chưa đủ căn cứ, cần nghe lại; kết quả nêu các vị trí cần kiểm tra khi còn mốc đọc số chưa xác minh. Cách viết số dễ hiểu nhầm hoặc tên mã được giữ nguyên trong gợi ý nhận diện. Không bảo đảm ASR đúng tuyệt đối với mọi cách đọc số, giọng hoặc nhạc nền.

Với SRT tiếng Việt tham chiếu, cue ngắn có biến thể nhận diện như "Be"/"b" hoặc khác dấu có thể được giữ đúng chữ SRT khi đã có timestamp đầy đủ và mốc căn mạnh hai phía. Tool không tạo timestamp bằng timecode SRT cũ; các cue này được liệt kê kèm thời gian trong Nhật ký kỹ thuật và kết quả có danh sách vị trí cần nghe lại. Nếu nội dung thật sự không khớp, mất timestamp, không có mốc neo đủ mạnh hoặc vượt vùng chọn, tool vẫn dừng trước khi thêm Caption Track.

Phần chi tiết kết quả và nhật ký báo phạm vi cue SRT đã dùng cho từng vùng audio, tổng cue và số cue ngoài vùng không được thêm. Mỗi vùng phải chứa lời liên tục tương ứng với một phần SRT; các vùng rời nhau phải theo thứ tự nội dung SRT. Nếu audio cắt giữa cue, nội dung lặp khiến không xác định được duy nhất phạm vi, hoặc mất lời bên trong phạm vi, tool dừng thay vì tự bỏ cue. Hãy chọn trọn câu/clip hoặc dùng SRT riêng cho vùng đó.

Nếu Whisper đẩy token ra ngoài mép audio hoặc bỏ sót phần cuối có tín hiệu âm thanh, tool có thể nhận diện lại tối đa một cửa sổ cuối không quá 30 giây, bắt đầu từ khoảng nghỉ đo được. Nếu vẫn không xác minh được phần cuối khi dùng SRT, tool dừng trước khi thêm caption; nhạc nền kéo dài sau lời nói cũng có thể cần chọn vùng audio chính xác hơn. Caption nằm trên frame hợp lệ bên trong vùng chọn, kể cả khi mép clip audio nằm giữa hai frame.

## Dựng theo voice

### Thuật toán mặc định từ 2.20.13

Nút **Phân tích và dựng tự động** dùng DTW để tìm thêm điểm cắt câu an toàn, gộp hình ngoài ngưỡng tốc độ một lần với đoạn liền kề và dựng chia đợt nhanh. Không cần bật lựa chọn DTW/gộp, chạy thử hay xác nhận thêm sau phân tích. Nếu không tìm được điểm cắt hoặc cặp gộp phù hợp, tool vẫn dựng theo kế hoạch đã kiểm bảo toàn.

Có thể chỉnh tốc độ voice trước khi chạy, kể cả mỗi chapter một tốc độ khác; tool giữ speed đó và quy đổi word timing/khoảng lặng theo chapter. Hiện yêu cầu speed dương từ 1% trở lên, không reverse/0%; chưa hỗ trợ voice đã trim đầu media (media In phải bằng 0). Kiểm đầu vào trước nhận diện. Dùng template sạch, không chạy chồng lên timeline đã xử lý.

Planner tính điểm cắt từ mốc âm học mới; điểm cắt có thể khác phiên bản trước. Bước DTW bổ sung chỉ thêm điểm cắt khi timestamp đầy đủ và có khoảng lặng đo được đủ biên an toàn, đồng thời giữ các điểm cắt của kế hoạch vừa tính, hình nguồn, voice, nội dung caption, tổng thời lượng và khoảng không lời. Mốc nới caption 5 frame không dùng làm mốc cắt voice; chưa an toàn thì giữ nhiều câu trong một đoạn.

Gộp hình tính tốc độ chung bằng tổng frame nguồn / tổng frame đầu ra, thử hàng xóm trước và sau rồi chọn một đoạn liền kề giúp tốc độ gần dải ngưỡng hơn. Mỗi cặp gộp một lần rồi khóa, không gộp tiếp hoặc bị nhóm khác hấp thụ. Hòa thì ưu tiên hàng xóm ngắn hơn, rồi bên trước. Đây là lựa chọn cục bộ, không bảo đảm tối ưu toàn cục. Cho phép qua chapter khi source, timeline và voice liền nhau chính xác theo frame; không vượt gap/đoạn không lời hay phạm vi video chính.

Chỉ V1 và audio gốc A1 dùng tốc độ chung; A2 giữ các clip/speed/điểm cắt an toàn trước gộp. Caption không gộp theo hình. Mọi đoạn hình đã gộp có marker trên V1, kể cả speed đã vào ngưỡng; nếu vẫn ngoài ngưỡng, marker ghi thêm cảnh báo. Các đoạn không gộp nhưng vượt ngưỡng vẫn có marker cảnh báo. Không ép speed vào ngưỡng hoặc thêm khoảng nghỉ.

Màu marker giúp phân biệt: **đỏ** = speed quá nhanh; **cam** = speed quá chậm; **vàng** = căn voice cần nghe lại; **xanh dương** = hình đã gộp và speed trong ngưỡng (thông tin, không phải lỗi). Nếu nhóm gộp còn vượt ngưỡng, dùng đỏ/cam và ghi chú vẫn nêu việc gộp. Tool kiểm lại màu khi API cho phép; lỗi đặt màu được báo riêng, không coi timeline dựng đúng là lỗi chỉ vì màu. Tên và ghi chú luôn là cách phân biệt bổ sung.

### Nhận diện và dọn marker của tool

Marker cần kiểm tra trên thước timeline có tên `VOICE SYNC - Can kiem tra`; ghi chú chứa cue, lý do và vùng thời gian. Auto edit và Tạo phụ đề quản lý riêng các marker này, chỉ cập nhật/dọn marker đúng dấu sở hữu trong phạm vi đang làm. Giữ marker người dùng, marker của chức năng khác và ngoài vùng. Nếu không gắn được marker, tool báo lỗi; caption có thể đã được thêm, cần kiểm tra trước khi chạy lại. Lỗi riêng màu vẫn giữ vị trí/ghi chú và được báo riêng.

Tool đọc marker cũ trước khi cắt/retime và giữ chúng trong lúc dựng. Sau khi xác định vị trí cuối, tool đối chiếu theo từng nguồn V1/A1/A2: giữ marker còn đúng, cập nhật hoặc tạo marker cần thiết, kiểm tra rồi mới dọn marker thừa. Marker kiểm tra trên thước timeline dùng cùng nguyên tắc. Không dọn marker toàn timeline, CTA ngoài nhóm hoặc marker nằm ngoài vùng nguồn xử lý.

Nếu cập nhật marker bị lỗi, tool thử phục hồi dữ liệu marker của riêng nhóm đó và báo rõ nếu chưa phục hồi đầy đủ. Đây không phải khôi phục timeline; cần kiểm tra kết quả trước khi chạy lại. Tạm dừng/hủy chỉ thực hiện ngoài bước cập nhật một nhóm nguồn: nhóm đã hoàn tất được giữ, nhóm chưa cập nhật còn marker cũ. Nếu sửa marker nguồn trong lúc tạm dừng, tool phát hiện khác biệt trước khi ghi nhóm đó. Không tự Undo hoặc lưu project.

Marker mới có tiền tố tên `VOICE SYNC -` và dấu `[PremiereVoiceSync:owned-marker:v1]` trong ghi chú. Marker cũ chưa có dấu này chỉ được nhận khi cả tên và mẫu ghi chú trùng mẫu cảnh báo tốc độ/căn voice của tool. Chỉ có tiền tố tên chưa đủ để xóa; marker thủ công hoặc không đủ dấu hiệu được giữ. Đây là dấu nhận dạng, không phải chữ ký bảo mật: nếu sao chép nguyên tên/ghi chú của tool vào marker thủ công thì không thể phân biệt tuyệt đối.

Premiere lưu clip marker trên ProjectItem nguồn, không phải bản sao riêng của mỗi TrackItem. Nếu cùng nguồn và cùng vùng source xuất hiện ở sequence khác, dọn/tạo marker có thể hiện ở các bản dùng chung đó. Không thay nội dung, vị trí hay speed của các clip ngoài phạm vi.

### Chuẩn bị đầu vào

Lưu project trước khi chạy, để có bản có thể mở lại nếu cần. Dùng sequence template chưa bị tool cắt/retime:

- **V1:** một nested video chính còn nguyên, không phải nhiều clip đã cắt sẵn.
- **A1:** audio của nested video, đã linked với V1. Tool cắt và chỉnh V1/A1 theo cặp. Tool không tự tách giọng gốc khỏi nhạc/ambient; bạn tự xử lý lời gốc nếu cần.
- **A2:** các file voice tiếng Việt theo chapter, đặt liên tiếp đúng thứ tự, không chồng nhau. Một file voice dài cũng được. Các clip sau khoảng cách tách nhóm, như CTA, không thuộc nhóm voice chính.
- **Ngôn ngữ voice và SRT:** chọn tiếng nói thực tế; SRT cùng ngôn ngữ, đúng nội dung đã dùng tạo voice. Timestamp vẫn cần tương ứng với các vùng hình của video nguồn; tool sẽ nhận diện voice để xác định thời gian mới. Không dùng SRT chỉ có timestamp của bản voice mới nhưng không còn liên hệ với hình nguồn.

Các element khác trong template không cần xóa. Nếu hình sau dựng dài hơn và chạm cụm outro, tool có thể dời cụm outro để nối sau đuôi mới; nội dung và khoảng cách tương đối của cụm được giữ. Tool không tự xuất H.264 hay thay thế bước duyệt.

### Các bước chạy

1. Mở sequence template đã chuẩn bị. Chọn **Dựng theo voice**.
2. Xem **Timeline đang mở**. Nếu vừa đổi sequence/import SRT, bấm **Cập nhật đầu vào**.
3. Chọn SRT trong danh sách được lấy từ Project, hoặc bấm **Chọn ngoài** để chọn file trên ổ đĩa. Nếu có nhiều SRT, bật **Nối nhiều file SRT**, thêm file và sắp theo thứ tự nội dung voice trước khi chạy.
4. Không cần chạy thử/chẩn đoán trước. Khi cần tìm nguyên nhân lỗi đầu vào, mở **Hỗ trợ và nhật ký → Chẩn đoán đầu vào**; tác vụ chỉ đọc, không thay đổi timeline.
5. Chỉnh **Tùy chỉnh theo video** nếu cần theo giải thích bên dưới; nếu chưa chắc, giữ mặc định.
6. Bấm **Phân tích và dựng tự động**, đọc xác nhận rồi chạy. Không sửa timeline hoặc đổi sequence trong lúc chạy.
7. Chờ kết quả dưới nút chạy. Tool căn voice, dựng theo câu hoàn chỉnh, tạo Caption Track và hậu kiểm. File SRT caption tạm không được giữ trong Project.
8. Phát lại để kiểm tra hình, điểm cắt voice, caption và clip marker theo bảng màu ở trên. Bật **Timeline Settings > Show Clip Markers** nếu không thấy marker. Marker tốc độ/gộp nằm trên đoạn V1 liên quan, không phải marker toàn timeline.
9. Chỉ lưu project khi đã duyệt. Nếu tác vụ báo timeline đã thay đổi rồi lỗi, Undo; nếu Undo không khôi phục đầy đủ, đóng project không lưu rồi mở bản đã lưu. Không chạy dựng lại trên timeline đã xử lý; trở về template sạch trước khi thử lại.

### Ý nghĩa thông số

| Thông số | Mặc định | Tác dụng |
| --- | --- | --- |
| Ngưỡng chậm | 70% | Thử gộp hình một lần nếu chậm hơn ngưỡng; marker nếu vẫn vượt. Không giới hạn tốc độ dựng. |
| Ngưỡng nhanh | 130% | Thử gộp hình một lần nếu nhanh hơn ngưỡng; marker nếu vẫn vượt. Không giới hạn tốc độ dựng. |
| Khoảng không lời | 0,5 giây | Ngưỡng tùy chỉnh. Khoảng trống SRT đạt ngưỡng được xét trước gộp câu; giữ riêng khi có điểm cắt voice an toàn. Chưa đủ bằng chứng thì giữ voice và đặt marker khoảng cần rà tay. Khoảng dưới ngưỡng được gộp vào lời liền kề. Thiết lập người dùng đã lưu được giữ nguyên. |
| Khoảng tách nhóm voice | 2 giây | Khoảng cách giữa clip A2 lớn hơn ngưỡng kết thúc nhóm voice chính; nhóm sau như CTA được giữ riêng. |
| Ký tự tối đa mỗi caption | 42 | Chia caption theo dấu câu, nghỉ hơi và ranh giới từ/cụm từ. Có thể giảm nếu font lớn. Không phải phép đo độ rộng chữ trên màn hình. |

Ví dụ: speed cần 145% trong khi ngưỡng là 130% thì tool thử một cặp hình liền kề giúp cải thiện tốc độ. Nếu không có cặp tốt hơn hoặc speed sau gộp vẫn ngoài ngưỡng, giữ tốc độ cần thiết và đặt marker, không ép xuống 130%. Nút **Khôi phục mặc định** chỉ đặt lại các tùy chỉnh, không khôi phục timeline.

Từ 2.20.80, workflow log lưu các thông số thực sự có trong kế hoạch: ngưỡng không lời, hai ngưỡng tốc độ, khoảng tách nhóm voice và giới hạn ký tự caption. Vì vậy vẫn kiểm tra được thiết lập sau khi job tạm đã dọn. Khoảng không lời chưa tách có marker theo vị trí hình sau dựng, khác với marker cần rà chữ/timing của caption.

Không cần SRT gốc, xuất XML hay chạy thử bắt buộc. **Chẩn đoán** giúp kiểm tra đầu vào mà không thay đổi timeline. Xem thêm giải thích thuật toán trong [README](../README.md).

## Kiểm tra sau Auto edit

Nút **Chẩn đoán đầu vào** trong **Hỗ trợ và nhật ký** chỉ kiểm đầu vào, không sửa timeline. DTW, gộp đoạn và dựng chia đợt nhanh đã nằm trong nút chính; không còn bước dựng thử hoặc dừng từng nhóm trên giao diện.

Sau hoàn tất, nghe/xem lại kết quả và kiểm Preview/Play trước khi tự lưu project. Nếu lỗi giữa chừng, khôi phục bằng Undo hoặc mở bản đã lưu; không chạy lại trên timeline đã dựng một phần. Log `Performance_*.jsonl` vẫn được giữ cục bộ, chỉ chứa tên bước/thời gian/trạng thái, không có transcript hay đường dẫn media, không tự gửi dữ liệu. File job/audio/plan tạm được dọn.

## Xử lý tình huống thường gặp

- **Không thấy panel:** kiểm tra đúng Premiere 26.x trên Windows, đã đóng Premiere khi cài và mở lại sau cài; vào menu Extensions (Legacy).
- **Sequence chưa được đọc hoặc vừa đổi lựa chọn:** mở sequence cần làm, bấm **Cập nhật đầu vào** ở bất kỳ chế độ nào.
- **Không thấy SRT trong danh sách:** dùng Chọn ngoài; không kéo thả SRT từ panel Project.
- **Caption tự xuống nhiều dòng:** giảm giới hạn ký tự hoặc chỉnh font/kích thước/vùng hiển thị trong Premiere. Giới hạn ký tự không bảo đảm độ rộng pixel với mọi font.
- **Có hai lớp caption sau khi tạo subtitle lại:** chế độ độc lập giữ track cũ; tự ẩn hoặc xóa track không dùng sau khi kiểm tra.
- **Lỗi nhận diện/căn lời:** xem Nhật ký kỹ thuật, kiểm tra SRT đúng nội dung và ngôn ngữ, media không offline. Không tự lưu timeline lỗi.

Khi báo lỗi, gửi thông báo đầy đủ, phiên bản tool, chế độ đang chạy và cấu trúc timeline. Dùng **Xuất log đã che thông tin** trong **Hỗ trợ và nhật ký** để lưu log panel tại thư mục bạn chọn. Bộ lọc che đường dẫn, tên sequence/media được biết, email và mẫu token GitHub; không bảo đảm nhận diện mọi nội dung riêng tư, nên luôn đọc lại trước khi chia sẻ. Không tự gửi log lên mạng.

Từ 2.20.20, cả Dựng theo voice và Tạo phụ đề tự lưu số liệu hiệu năng trong `%LOCALAPPDATA%\PremiereVoiceSync\Logs\Workflow_*.jsonl`. Không cần xuất thủ công: đóng Premiere vẫn giữ file. File chỉ có phiên bản/chế độ, thời gian bắt đầu/kết thúc từng bước, backend CPU/CUDA, số lượt dùng lại/xử lý mới cache và một số số lượng caption/đoạn. Không lưu lời nói, tên sequence/media, đường dẫn media hoặc nội dung lỗi. Auto edit liên kết bằng tên file `Performance_*.jsonl` để đối chiếu phần dựng timeline. Đây là log cục bộ, không tự gửi đi.

Nếu bị treo hoặc đóng app giữa chừng, log có bước bắt đầu nhưng chưa kết thúc, không có dòng `finish`; đây là lượt bị gián đoạn, không phải lượt thành công. Tổng `processingMilliseconds` bắt đầu sau xác nhận (Auto edit) hoặc sau kiểm tra đầu vào (Tạo phụ đề), kết thúc sau dọn file tạm; không phải thời gian chờ bạn trả lời hộp xác nhận. Thông báo tổng thời gian trong panel có thể dài hơn vì tính cả chờ/kiểm tra đầu vào. Chỉ các file `Workflow_*.jsonl` đúng định dạng của tool được tự dọn sau 30 ngày; giữ khoảng 100 file mới nhất và không xóa file trong 24 giờ gần nhất. Lỗi ghi log không làm dừng việc dựng. Nhật ký kỹ thuật trong panel vẫn chỉ tồn tại trong phiên mở panel, cần xuất nếu muốn giữ thông báo lỗi chi tiết.

## CPU/GPU và dữ liệu

Panel hiển thị backend đang dùng. Máy NVIDIA chỉ báo CUDA khi file backend đúng hash đã khóa và vượt phép thử thực tế; lỗi GPU sẽ chuyển sang CPU và ghi lý do. Bản hiện tại dùng CPU cho máy AMD/Intel. **Cho phép tải backend GPU từ GitHub** mặc định tắt trên máy mới; bật nếu bạn muốn tải CUDA (khoảng 678 MB). Bỏ chọn không xóa hoặc ngừng sử dụng GPU đã cài hợp lệ, chỉ ngăn tải mới. Lựa chọn được nhớ trên máy đó. Chạy CPU và GPU đã có không cần Internet.

Audio/SRT được xử lý cục bộ bằng FFmpeg và Whisper. Tool không có chức năng tải video, audio, SRT hoặc nội dung project lên máy chủ. Kết nối mạng của runtime dùng để tải CUDA từ GitHub; file tải được đối chiếu SHA-256 đã khóa. Nhà cung cấp tải xuống vẫn nhận thông tin kết nối thông thường như địa chỉ IP.

Vùng làm việc và dữ liệu nằm trong `%LOCALAPPDATA%\PremiereVoiceSync`. File tạm của tác vụ được dọn tự động. Cache và backend được giữ để dùng lại. Cache Whisper chứa nội dung/timestamp nhận diện; muốn xóa thì dùng **Xóa cache nhận diện**, model/backend vẫn được giữ. Nhật ký có thể chứa tên file, đường dẫn và nội dung lỗi; hãy kiểm tra trước khi chia sẻ. Log cũ của bản trước nếu còn nằm trong thư mục dữ liệu cũng được xóa khi gỡ sạch.

## Dùng lại kết quả xử lý audio

Cache audio (2.20.19) tự áp dụng cho cả hai chế độ, gồm nhận diện thô, DTW, nhận diện bổ sung và tìm khoảng nghỉ khi nội dung audio/cấu hình tương ứng giống nhau. Không cần bật thêm ô chọn. Nhật ký báo số lượt dùng lại và xử lý mới. Đổi SRT, giới hạn ký tự, speed hoặc vị trí timeline vẫn được căn/tính lại; chỉ kết quả nhận diện nguồn giống hệt mới dùng chung. Audio xuất từ sequence được kiểm theo nội dung file audio, không theo tên sequence. Không lưu nguyên kế hoạch dựng hay WAV lâu dài.

Cache mới nằm trong `Cache\Whisper\Audio-v1`, tự dọn các mục quá 30 ngày hoặc vượt ngân sách khoảng 512 MB ở đầu tác vụ. Các mục hỏng được xử lý mới. Lần đầu dùng bản này cần tạo cache mới; cache nhận diện cũ chưa có khóa theo nội dung không được dùng nhầm. Lần đầu chạy voice mới vẫn phải nhận diện. Cache được lưu cục bộ, không có trong ZIP chia sẻ; có thể chứa nội dung lời nói/đường dẫn log, nên không gửi thư mục cache cho người khác. Nút **Xóa cache nhận diện** xóa cả cache cũ/mới, giữ model/backend.

## Khi đưa bộ cài cho người khác

Bộ cài gồm mã nguồn vận hành và runtime; người nhận có thể đọc mã nguồn. Nó không đóng gói `.git`, thông tin đăng nhập GitHub, dữ liệu project hay log của người phát hành. Gói chỉ lấy những thư mục/file cần thiết trong danh sách đóng gói.

Gói ZIP và script chưa có chữ ký số. Panel CEP chưa ký chạy nhờ `PlayerDebugMode`, cũng cho phép các extension CEP chưa ký khác được nạp. Hãy lấy gói từ đúng người phát hành/Release và không chạy script hoặc cài extension không rõ nguồn gốc. SHA-256 giúp kiểm tính toàn vẹn khi đối chiếu với nguồn tin cậy, không thay thế chữ ký số. Các kiểm tra tự động của dự án không phải chứng nhận bảo mật hoặc kiểm toán độc lập.

Trước khi chạy Setup, đối chiếu SHA-256 toàn ZIP với giá trị công bố trong ghi chú Release hoặc do người phát hành gửi qua kênh tin cậy riêng. Windows PowerShell có sẵn lệnh `Get-FileHash -Algorithm SHA256 -LiteralPath <đường-dẫn-ZIP>`. Không chỉ tin file checksum nằm bên trong chính ZIP. Không cần copy thêm file checksum sang máy mới. Không tắt antivirus/SmartScreen hay thêm thư mục vào exclusion để cài tool.

Setup bắt buộc gói đầy đủ checksum và danh sách file chính xác; thiếu checksum, file thừa/hash sai hoặc junction/symlink sẽ bị từ chối. Không thêm file cá nhân vào thư mục gói trước khi Setup. Nếu cập nhật lỗi trong bước thay panel, script cố khôi phục panel cũ và báo lỗi; đây không phải backup project. Script không đổi PATH hoặc ExecutionPolicy toàn hệ thống; Bypass chỉ áp dụng cho tiến trình PowerShell của tác vụ.

## Gỡ cài đặt

Đóng Premiere, mở thư mục gói ZIP đã giải nén và chạy **Remove-Panel.cmd** (Gỡ panel). Đọc xác nhận rồi chọn **Y** để gỡ sạch. Script chỉ xóa đúng panel ID và thư mục dữ liệu của tool, gồm cache/backend/log/job, không xóa extension trùng tên hoặc thư mục TEMP bên ngoài theo tên. `PlayerDebugMode` được khôi phục nếu chưa bị thay đổi kể từ Setup. Whisper/FFmpeg của chương trình khác được giữ nguyên. Thư mục ZIP giải nén không bị xóa; có thể tự xóa sau khi gỡ xong.

Nếu đã xóa gói ZIP, giải nén lại gói để lấy Remove-Panel.cmd. Nếu chưa chuyển từ bản EXE cũ, chạy Setup-Panel.cmd trước rồi mới gỡ; script gỡ mới không tự xóa một bản chưa được nhận diện là panel ZIP.
