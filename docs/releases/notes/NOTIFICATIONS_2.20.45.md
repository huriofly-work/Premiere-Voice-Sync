# 2.20.45 — timing âm học dùng chung trong Auto edit

Người dùng xác nhận Chỉ tạo subtitle chính xác hơn rất nhiều ở phần đã kiểm và yêu cầu áp dụng cơ chế đó cho các phần liên quan, bao gồm thay đổi điểm cắt dựng. Bản này dùng chung bước nhận diện theo cửa sổ DTW, nhận diện lại riêng vùng lỗi và tinh chỉnh đáy năng lượng RMS quanh từ đứng trước cho Auto edit, kể cả retry mép caption/quanh số.

Cue có mapping đầy đủ, đủ khớp chữ, neo hai mép và thời gian hợp lệ cập nhật Start/End/WordTimings trước planner. Điểm cắt và speed video được tính lại theo mốc mới. Chữ và timecode video trong SRT nguồn giữ nguyên. Vùng chỉ có timing ước lượng không được dùng làm chứng cứ DTW cắt dựng; xung đột với cue chưa xác minh chỉ giữ mốc dự phòng ở các cue liên quan. Giữ phạm vi voice ngoài cùng của chapter, thứ tự và kiểm frame liên tục. Phép đo RMS không thay điều kiện khoảng nghỉ an toàn để cắt voice.

## Kiểm chứng

Ngày 16/10/2026, `Run-Tests.ps1 -NoWindowsIntegration` đạt 42 nhóm, parse 111 script PowerShell; sáu nhóm tích hợp Windows bị bỏ qua theo runner. TEMP/TMP dùng fixture riêng trong workspace; ca junction được chạy ngoài sandbox. Kiểm syntax/generator, host/UI và các workflow hiện có đều đạt trong phạm vi bộ kiểm tự động.

- Kiểm hồi quy hai chapter, speed voice 50/90/100/125/150%, offset và frame rate 30/29,97; cue lỗi/ước lượng, xung đột cạnh cue chưa xác minh và lỗi native. Kiểm mốc mới tìm được khoảng nghỉ thực mà mốc cũ bỏ lỡ.
- A/B ngoại tuyến dùng audio ghép từ 79 clip A2 của project đã báo lỗi, 615 cue nguồn; dùng backend Whisper CUDA thật, cache thử nghiệm riêng. Toàn bộ pipeline alignment → sentence planner → DTW bổ sung → gộp speed chạy theo cùng thứ tự production. Có 465 cue cập nhật mốc dựng, 45 cue xung đột giữ dự phòng, không có vùng fallback ước lượng trong lượt này.
- Kết quả cuối: 224 → 237 nhóm hình, 1.159 → 1.164 caption; DTW bổ sung 3 điểm cắt, gộp speed 8 cặp. Chữ/timecode nguồn/chapter giữ nguyên, frame video liên tục, voice không mất/lặp frame, không thêm pause, tổng 59.932 frame tại 30 fps giữ nguyên. Đây là kết quả riêng bộ dữ liệu này, không phải yêu cầu mọi project phải giữ cùng thời lượng với bản cũ.
- Chỉ tạo subtitle A/B toàn bài: SRT đầu ra giống từng byte với 2.20.44; cơ chế được người dùng chấp nhận trước đó được giữ.

Nguồn audio thử nghiệm được tái tạo từ file gốc với speed unity, không tái hiện effect/mix của Premiere; có 15 đuôi MP3 rất ngắn được đệm dưới 100 ms khi ghép. Các phép kiểm trên không thay việc nghe lại Auto edit, kiểm Preview/Play/Save và import caption trong Premiere thật. Không ghi vào project hoặc tự điều khiển Premiere trong phép thử.

Bằng chứng cục bộ: `.tmp-shared-auto-timing/final-audit.log`, `final-conservation.json`, `subtitle-parity.log`, `final-tests.log`. Kế thừa đo Encoding, tạm dừng/tiếp tục và dừng tác vụ của 2.20.44.
