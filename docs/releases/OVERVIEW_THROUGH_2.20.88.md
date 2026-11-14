# Premiere Voice Sync 2.20.88 — bản chờ kiểm thử

**Qwen thử nghiệm:** đã nối controller nhận job caption của panel và nhận diện lại cửa sổ audio qua phiên resident. File SRT cuối giữ đủ255/255main,27/27Short,13/13quiz; outro13caption, có hint timing cần rà. Chưa bật Qwen trong panel/bản cài. Xem phạm vi và kiểm chứng.

**2.20.88:** Giảm quét SRT lặp trong thuật toán kiểm chứng điểm cắt, tái sử dụng phép chuẩn hóa chữ và giảm các đợt đổi tốc độ không có việc. Giữ toàn bộ kiểm timing/cut/omission, tối đa4 cặp clip thực sự chỉnh/đợt và giới hạn thời gian. Chưa có số đo tốc độ bản88 trong Premiere. Xem [bằng chứng và giới hạn](notes/AUTO_EDIT_ACOUSTIC_2.20.88.md).

**2.20.83:** Lỗi nhận diện khó chuyển thành vùng cần sửa tay và tác vụ tiếp tục. Giữ đủ hình/voice thành khối, không cắt nhỏ vùng chưa chắc; nếu chưa ghép được hình/voice thì hoàn tất phân tích với cảnh báo và giữ nguyên timeline. Alien offline đã qua đủ bốn bước, ra 695 caption; native Premiere còn pending. Xem [phạm vi và kiểm chứng](notes/EDITED_VOICE_2.20.83.md).

**2.20.82:** Giới hạn timestamp ASR theo mép clip trước căn lời, giữ phục hồi từng câu và chia vùng sửa tay bằng neo nguyên câu. **Ở bản 2.20.82, Alien 02 vẫn pending:** vùng câu 35–44 chưa đủ neo trong giới hạn 30 giây, nên tiếp tục dừng trước sửa timeline. Xem [phạm vi và kiểm chứng](notes/EDITED_VOICE_2.20.82.md).

**2.20.81:** Khoảng không lời mặc định **0,5 giây** trên panel và các nhánh engine dự phòng; giữ giá trị tùy chỉnh đã lưu. Tiếp tục cơ chế giữ gap/cắt voice an toàn và rà tay của 80. Xem [phạm vi và kiểm chứng](notes/EDITED_VOICE_2.20.81.md).

**2.20.80:** Xét khoảng không lời nguồn theo ngưỡng bạn chỉnh trước bước gộp câu. Giữ riêng khi có điểm cắt voice an toàn; khoảng chưa tách có marker để rà tay. Log lưu các thông số engine thực sự dùng. Giữ cơ chế rà tay 79 và model Small. Xem [phạm vi và kiểm chứng](notes/EDITED_VOICE_2.20.80.md).

**2.20.76:** giữ đuôi ASR ban đầu đã qua kiểm timing/âm thanh khi lượt nhận diện bổ sung bị mất lời; giữ nguyên các câu SRT và model Small. Xem [nguyên nhân và kiểm chứng](notes/SUBTITLE_TIMING_2.20.76.md).

**2.20.75:** tách adapter nhận diện để chuẩn bị nâng model tiếng Việt; giữ nguyên Small và kết quả caption baseline. Chưa sửa chính tả voice ngoài SRT. Xem [phạm vi và kiểm chứng](notes/SUBTITLE_TIMING_2.20.75.md).

**2.20.74:** giữ chữ SRT qua số/đơn vị ASR viết gộp và nhận diện lại câu ngắn với ngữ cảnh đã xác minh; thêm sổ bộ nhớ hồi quy của project. Nghiệm thu Premiere còn chờ. Xem [chi tiết và kiểm chứng](notes/SUBTITLE_TIMING_2.20.74.md).

**2.20.73:** sửa căn từ dấu/đơn vị và câu phân số khi giữ chữ SRT; bản dựng ngoại tuyến Nam Cực tăng từ 250 lên 253/255 câu. Hai câu còn mở, nghiệm thu Premiere còn chờ. Xem [chi tiết và kiểm chứng](notes/SUBTITLE_TIMING_2.20.73.md).

**2.20.71:** thêm tùy chọn âm thanh mặc định bật cho thông báo Windows; phát một lần cùng thông báo hoàn tất hoặc cần xử lý, có thể tắt trong Thiết lập. Xem [chi tiết và kiểm chứng](notes/NOTIFICATIONS_2.20.71.md).

**2.20.70:** panel là nơi duy nhất xem và xử lý kết quả; Windows chỉ nhắc khi tác vụ hoàn tất hoặc cần xử lý ở nền. Bỏ cửa sổ xem riêng và tự giành focus. Xem [chi tiết và kiểm chứng](notes/NOTIFICATIONS_2.20.70.md).

**2.20.68:** thông báo Windows khi dựng hoặc tạo phụ đề chạy nền đã hoàn tất, kể cả thành công bình thường. Bấm thông báo để quay lại panel xem kết quả. Xem [chi tiết và kiểm chứng](notes/NOTIFICATIONS_2.20.68.md).

**2.20.67:** giữ nhãn một chữ như A., C. từ SRT khi nhận diện khớp chữ và hai câu lân cận xác định đúng vị trí; không báo nhầm là lời ngoài SRT. Xem [chi tiết và kiểm chứng](notes/SUBTITLE_TIMING_2.20.67.md).

2.20.66 đặt nối SRT cạnh chọn SRT, thêm bộ chọn từng file Project có tìm kiếm và danh sách thu gọn; audio mặc định ưu tiên clip đang chọn. Xem [cách dùng và kiểm chứng](notes/SRT_JOIN_2.20.66.md).

2.20.62 bỏ marker “Cần đối chiếu số đọc”. Nhận ra câu thì giữ chữ SRT; khác cách ghi số chỉ là thông tin chẩn đoán. Cơ chế căn thời gian bằng từ đứng trước số và đáy năng lượng âm thanh được giữ nguyên. Xem [chi tiết](notes/REVIEW_MARKERS_2.20.62.md).

2.20.61 giữ câu SRT khi phần số khác nhận diện và phục hồi câu cuối còn khớp khi Short dùng một phần SRT dài. Xem [hai lỗi trên sequence Final vertical và kiểm chứng](notes/SUBTITLE_TIMING_2.20.61.md).

2.20.60 bỏ marker timing số, chặn chữ nghe sai ở đuôi câu SRT bị thêm lại và làm rõ marker của phần nhận diện bổ sung. Xem [lỗi “tật.” và kiểm chứng](notes/SUBTITLE_TIMING_2.20.60.md).

2.20.59 giữ nguyên chữ SRT khi nhận ra câu tương ứng trong voice, kể cả ASR sai/thiếu/thừa vài từ hoặc khác cách phát âm. Chỉ dùng chữ ASR cho đoạn không xác định được câu SRT tương ứng. Không tạo marker giữ chữ SRT khớp phần lớn. Xem [hành vi và kiểm chứng](notes/SUBTITLE_TIMING_2.20.59.md).

2.20.54 bổ sung nối nhiều SRT thành một để nhận diện chung: chọn file, sắp thứ tự, giữ timestamp gốc hoặc nối tiếp thời gian. Xem [cách dùng và kiểm chứng](notes/SRT_JOIN_2.20.54.md).

2.20.51 hỗ trợ voice lược bỏ nhiều cụm cue: subtitle giữ chữ SRT của phần còn đọc; Auto edit bỏ hình/A1 theo timestamp các cue đã xác minh bị bỏ. Kiểm tra lại vùng nối để phân biệt ASR sót; không tự suy ra mốc hình cho phần cắt giữa cue. Xem [hành vi, giới hạn và kiểm chứng](notes/EDITED_VOICE_2.20.51.md). Chưa nghiệm thu trong Premiere.

2.20.49 tự ưu tiên SRT trong Project cho Chỉ tạo subtitle, giữ lựa chọn thủ công và bản sửa marker 2.20.48. Xem [phạm vi và kiểm chứng](notes/SRT_PRIORITY_2.20.49.md).

2.20.50: **Chỉ tạo subtitle** có ba nguồn audio (tất cả track đang bật / các track chỉ định, cho chọn nhiều / đúng các clip audio đang chọn) và phạm vi thời gian tường minh. Track thủ công không bị tự thay khi trống; A2 chỉ là gợi ý khi chưa chọn nguồn. Có nhật ký khôi phục mute/enable/In/Out trước khi xuất. Xem [phạm vi và kiểm chứng](notes/NOTIFICATIONS_2.20.50.md). Chưa nghiệm thu audio xuất thực trong Premiere.

2.20.48 sửa marker cảnh báo số: chọn đúng caption đầu ra có chứa số, ghi số và nội dung caption cần kiểm tra, phân biệt số caption với đoạn phân tích nội bộ. Cảnh báo chưa xác minh timing không được coi là kết luận đọc sai số. Gói cập nhật chỉ gồm sửa marker trên nền 2.20.47; các thay đổi chưa phát hành ở trên không nằm trong gói. Xem [phạm vi và kiểm chứng](notes/REVIEW_MARKERS_2.20.48.md).

2.20.43 sửa lệch timing của luồng Chỉ tạo subtitle: một vùng DTW lỗi chỉ được nhận diện lại trong cửa sổ ngắn, giữ mốc theo từ ở phần còn lại. Ranh giới được tinh chỉnh theo đáy năng lượng sóng âm gần từ đứng trước, gồm ranh giới trước số. Vùng chỉ có timestamp cấp câu được báo là ước lượng. Xem [chẩn đoán và kiểm chứng](notes/SUBTITLE_TIMING_2.20.43.md). Nội suy cue vẫn chỉ ở Auto edit.

2.20.40 sửa lỗi **SRT quá dài để căn an toàn** trong chế độ chỉ tạo subtitle bằng SRT có sẵn. Phần khớp giữ chữ SRT; phần thiếu hoặc khác SRT và lời nói ngoài SRT (gồm lời đăng ký kênh) được nhận diện bổ sung rồi ghép vào cùng kết quả. Nếu timestamp DTW lỗi, nhận diện lại bằng đoạn câu. Cần nghe lại chữ tự nhận diện. Xem [kiểm thử và giới hạn](notes/NOTIFICATIONS_2.20.40.md).

Tính năng **Tạm dừng / Tiếp tục** và **Dừng tác vụ** tiếp tục dùng cho cả hai chế độ. Tool chờ bước hiện tại kết thúc, kiểm tra lại trạng thái khi tiếp tục và không chạy lại phần nhận diện đã xong. Dừng phát trước khi tiếp tục; không sửa timeline, đổi project/sequence hoặc mở lại panel trong lúc nghỉ. Xem [cách dùng và giới hạn](notes/NOTIFICATIONS_2.20.39.md). Bản này chờ nghiệm thu trong Premiere thật.

2.20.35 thêm **Track voice cần nhận diện** cho Chỉ tạo subtitle: mặc định A2 (A1 nếu chỉ một track audio), chỉ xuất audio của track đã chọn. Tool tạm mute các track khác rồi khôi phục đúng trạng thái mute và In/Out, kể cả khi xuất lỗi. Không tách nhạc đã trộn trong cùng file/track voice. Đây là bản chờ kiểm thử trong Premiere thật.

2.20.34 sửa lỗi “Không đọc được trạng thái caption/In/Out” khi chỉ tạo subtitle trên Premiere không cung cấp `captionTracks` qua CEP. Giữ kiểm tra video/audio, In/Out và bin tạm; không coi thiếu API là không có caption. Sau lỗi có thể đã sửa Project, trường hợp này cần người dùng kiểm tra caption trước khi xác minh cho chạy lại. Kế thừa thông báo nhiều kênh và nền dựng 2.20.27; chưa nghiệm thu bản sửa trong Premiere thật.

2.20.27 sửa lỗi hai ranh giới câu chọn trùng một điểm nghỉ, tạo đoạn voice 0 frame rồi bị nâng giả lên 1 frame. Điểm cắt làm một phía mất thời lượng bị loại; giữ các câu chung trong một đoạn khi chưa có điểm cắt an toàn. Không nới dung sai DTW, không bỏ kiểm bảo toàn voice. Xem [báo cáo lỗi điểm cắt](../reviews/VOICE_BOUNDARY_FIX_2026-10-11.md).

2.20.26 sắp lại panel: đầu vào → tùy chỉnh → chạy; dùng chung nút **Cập nhật đầu vào**, thu gọn CPU/GPU, hướng dẫn và **Hỗ trợ và nhật ký**. Chẩn đoán đầu vào vẫn có nhưng không phải bước bắt buộc. Đã kiểm thử tự động và bố cục trình duyệt; chưa nghiệm thu trong Premiere. Bản ổn định đã nghiệm thu vẫn là **2.20.25**. Không đổi engine, DTW/caption, điểm cắt, tốc độ hoặc native executor. Xem [rà soát giao diện](../reviews/UI_REVIEW_2026-10-10.md).

Bản ổn định 2.20.25 đã được người dùng kiểm thử trên Premiere Pro 26.2.2: quét SRT hoạt động, không còn lỗi được báo, Preview không đơ và Save bình thường. Kết quả này không bảo đảm mọi máy/project. Baseline sửa lỗi được ghi trong [báo cáo rà soát](../reviews/AUDIT_2026-10-08.md) và tăng tốc bước căn chữ SRT–ASR bằng cùng edit-distance/tie rules, dùng rolling rows và lõi compiled. Cửa sổ nhỏ hoặc máy không chạy được lõi tối ưu giữ đường PowerShell tham chiếu. Không thay nhận diện Whisper/DTW, điểm cắt đã có, native executor hoặc lịch chạy. Kết quả căn cue nhận diện thật giống hệt; timestamp caption đầu ra có các thay đổi có chủ đích được ghi bên dưới. Chưa có benchmark đối chứng tổng thời gian native để kết luận tỷ lệ tăng tốc toàn tool.

2.20.24 sửa quét SRT theo nhóm đọc nhỏ, không kiểm tra ổ đĩa đồng bộ khi lập danh sách và có timeout riêng cho quét. Caption Auto edit ánh xạ mốc âm học qua các lát A2 thực tế thay vì ép vào nhóm câu legacy; không đổi cắt/speed/di chuyển hình và voice. Xung đột với caption bên cạnh giữ mốc cũ và báo cue cần nghe lại, không tự đè hoặc chia đôi sai số lớn. Danh sách SRT phản ánh đường dẫn đã import; file không còn sẵn được kiểm tra khi bắt đầu tác vụ.

2.20.25 sửa khởi động/Đọc lại: quét SRT độc lập với việc sequence có phải template sạch hay không. Sequence đã dựng, không có sequence hoặc thiếu A2 vẫn được quét SRT trong Project. Điều kiện Auto edit vẫn kiểm khi dựng; không đổi thuật toán/caption/native executor. Ô chọn không còn báo đang tìm trước khi thực sự quét.

Auto edit mặc định dựng không delay sau ba phép thử native: dùng cache, đổi thông số và video/voice mới chưa cache; hậu kiểm đạt, người dùng xác nhận Preview/Play/Save bình thường. Không đặt timer chờ hoặc giới hạn 100 thao tác/600 ms mỗi đợt; vẫn gọi các nhóm dựng lần lượt qua CEP, giữ guard/hậu kiểm, DTW/gộp hình/caption và không tự lưu project. Chỉ tạo subtitle giữ nguyên. Kết quả nghiệm thu trên máy người dùng không bảo đảm mọi máy/project; luôn dùng template đã lưu và không sửa timeline khi chạy. ZIP 2.20.20 được giữ để quay lại lịch dựng cũ nếu cần, không phải xóa cache/model.
