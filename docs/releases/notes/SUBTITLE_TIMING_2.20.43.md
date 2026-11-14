# 2.20.43 — sửa lệch ranh giới Chỉ tạo subtitle

## Lỗi tái hiện

Lượt chạy 09:15:21–09:22:10 ngày 16/10/2026, panel 2.20.42, CUDA, tạo 1.166 caption. Log ghi 14 lượt nhận diện mới, không có cache hit. Hai file `run-captions.ps1` và `CaptionTiming.ps1` đang cài khớp hash với checkout khi chẩn đoán.

Dùng JSON nhận diện còn trong cache tái hiện được `CAPTION_DTW_ANCHOR_SPAN_INVALID:word-1448`. Tại khoảng 06:24, ba từ có chung anchor 384,02 giây. Parser tạo các khoảng từ chồng nhau rồi bộ kiểm tra từ chối. Catch cũ bỏ DTW của cả nguồn audio 33 phút và nhận diện lại bằng đoạn câu; parser sau đó chia đều thời gian của câu cho các từ. Độ khớp chữ không xác nhận được độ chính xác ranh giới từ.

Bản project đã lưu chứa đúng 1.166 caption trên sequence Final. Các mốc được người dùng chỉ ra khớp với dữ liệu: trước `13,8` là 12,00 giây; các cue 13–15 bắt đầu 19,967 / 21,700 / 22,200 giây; cue 18 bắt đầu 29,000 giây. Đây là dữ liệu file đã lưu, không phải trạng thái timeline đang mở.

## Thay đổi

- Chỉ tạo subtitle kiểm token theo cửa sổ tối đa 26 giây, ưu tiên mép ở khoảng nghỉ. Cửa sổ lỗi được nhận diện DTW lại riêng; các cửa sổ tốt giữ timing theo từ. Lỗi native/IO không bị biến thành lỗi timing có thể bỏ qua.
- Chỉ cửa sổ vẫn không xác minh được DTW mới dùng timestamp cấp câu. Ghi vị trí `captionTimingEstimatedRanges`, không gắn timing đó thành DTW đã xác minh. UI và metrics báo rõ số vùng ước lượng.
- Tìm đáy năng lượng tương đối gần token cuối của từ đứng trước ranh giới. Envelope RMS 5 ms; khoảng tìm có giới hạn 120 ms quanh neo, có kiểm hai vai năng lượng và thứ tự từ. Có thể nhận đáy chưa xuống ngưỡng im lặng -35 dB. Không chọn tùy tiện một đáy xa trong số nhiều âm tiết; không áp dụng một độ dịch cố định cho toàn bài.
- Giữ mép lời nói độc lập ở khoảng thở đo được. Vùng hoàn toàn nằm trong khoảng im lặng không cần nhận diện lại để phục hồi từ giả của ASR.
- Áp dụng cùng bước timing cho nhận diện chính, phục hồi/bổ sung tham chiếu và retry mép subtitle. Không đổi recognition/planner/điểm cắt/host Auto edit.
- Metrics lưu mode, số vùng retry, số vùng ước lượng và số ranh giới âm học; không lưu chữ, đường dẫn media hoặc lý do chứa nội dung riêng.

## Kiểm chứng

`Run-Tests.ps1 -NoWindowsIntegration` đạt 41 nhóm, parse 110 script. Sáu nhóm Windows integration vẫn được bỏ qua theo runner. TEMP/TMP đặt trong workspace; ca junction chạy ngoài sandbox. Ca mới kiểm giữ vùng tốt khi vùng khác có anchor trùng, retry và fallback chỉ trong vùng, punctuation, không sửa JSON đầu vào, lỗi native phải dừng, neo trước số, hai đáy mơ hồ, đáy tương đối trên ngưỡng im lặng, âm phẳng và WAV lỗi. Kiểm Auto edit chung vẫn đối chiếu 100 fixture với baseline.

Thử trên dữ liệu nhận diện của lượt người dùng và audio dựng ngoại tuyến từ 79 clip A2 của bản project đã lưu, 29 file media, tốc độ đều 100%. Phạm vi 2.017,733 giây. Không áp dụng effect Premiere; 15 đuôi MP3 thiếu dưới 100 ms được đệm im lặng đến OutPoint của clip. Không sửa project, không điều khiển Premiere.

Thử chuyển timing toàn bài giữ được 26 cửa sổ cần DTW retry, không có vùng phải fallback cấp câu và đo được 6.589 ranh giới năng lượng. Kết quả tham chiếu riêng trước bước phục hồi/bổ sung có 1.160 caption; còn 5 cue tham chiếu không đủ khớp và 3 cue thiếu mép cần retry. Đây là bước chẩn đoán trung gian, không dùng làm SRT giao cho người dùng.

Ở đoạn đầu, cùng ranh giới chữ trước `13,8` được đo lại khoảng 11,265 giây, sớm hơn mốc cũ 0,735 giây. Cue có thể được chia chữ lại khi ranh giới khoảng thở chính xác hơn, nên phải so theo nội dung thay vì dựa vào số thứ tự cue mới.

Sau đó chạy nhận diện CUDA mới toàn bộ audio dựng ngoại tuyến, đi hết engine thật gồm recovery, bổ sung, retry mép và xuất SRT. Harness chỉ chọn trực tiếp backend CUDA đã có và đặt vùng dữ liệu/cache vào workspace; không mock nhận diện, mapping hoặc timing. Kết quả 1.174 caption; không có lỗi cấu trúc, thời gian chồng/đảo, vượt phạm vi, dòng dài hơn 42 ký tự hoặc đánh số thiếu. Đo được 6.710 ranh giới; 30 cửa sổ retry, gồm cả cửa sổ recovery/supplement. Có 2 vùng vẫn dùng timing cấp câu và được báo rõ: 126,325–127,907 giây và 1002,675–1003,558 giây. Không coi hai vùng này là đã căn chính xác theo từ. Các cue 13/14/15/18 của đầu ra này bắt đầu ở 20,533 / 22,333 / 23,433 / 29,700 giây. Đây là kiểm thực thi ngoại tuyến, chưa phải nghiệm thu trong Premiere.

## Giới hạn và trạng thái

RMS/DTW và kiểm cấu trúc không chứng minh đúng từng từ trên toàn bộ media. Đáy sóng âm cũng có thể nằm trong một âm tiết; neo và cửa sổ giới hạn làm giảm rủi ro, không tạo bảo đảm tuyệt đối. Kết quả audio dựng ngoại tuyến không thay thế WAV xuất từ Premiere với đầy đủ effect. Chưa nghiệm thu import, Play hoặc Save trong project thật.

Sau khi người dùng yêu cầu tiếp tục, đã cài 2.20.43 ngày 16/10/2026 khi Premiere đóng. Bộ duyệt tự động từ chối đường cài chuẩn vì có bước ghi PlayerDebugMode; kiểm tra trực tiếp xác nhận giá trị đã là `1`, nên dùng tùy chọn có sẵn `-SkipRegistry`. Không ghi registry trong lượt cập nhật; snapshot toàn bộ key CEP trước/sau khớp nhau.

60 file panel đã cài khớp manifest/checksum. 624 file/22 thư mục dữ liệu công cụ và 408 file/8 thư mục project giữ nguyên; mọi hash và độ dài file trước/sau khớp nhau. Helper/shortcut đúng identity/checksum. ZIP SHA256 `87AAB63BD66BE93C063C91150286AD35F779CD4B3F34C3D180F58ED16AED7544`. Bằng chứng: `dist/_installation-2.20.43-20261016-104923/verified.json` và `before.json`. Không mở/đóng Premiere, không lưu hoặc sửa project, không xóa cache/model/jobs/backups. Caption cũ không tự được thay thế; bản sửa áp dụng cho lượt Chỉ tạo subtitle mới. Nghiệm thu Play/import/Save trong Premiere còn chờ người dùng.
