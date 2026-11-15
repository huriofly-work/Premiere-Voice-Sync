# 2.20.91 — Sửa lỗi sau lượt chạy thật ngày 15/11/2026

Bản public đầu tiên của repo mới (prerelease). Gom các bản sửa sau khi user chạy
Dựng theo voice 2.20.90 trên một project thật và báo 21 lỗi về chữ caption, timing
và marker. **Chưa nghiệm thu trên Premiere**; user cần chạy lại project đó.

## Thay đổi người dùng thấy

- **Chữ caption giữ đúng SRT, không đảo từ đầu câu** (#23). Whisper thường trả
  2–3 từ đầu câu cùng một mốc giờ; bước sắp xếp cũ đảo thứ tự các từ đó, làm câu
  không khớp SRT và hiện chữ máy nghe. Mốc kết thúc caption
  giờ lấy theo từ kết thúc muộn nhất.
- **Lấy lại chữ SRT khi máy nghe lệch đúng một từ gần giống** (#27): cùng số từ
  (ít nhất 4), khác một từ không phải số, chỉ khác dấu hoặc 1–2 chữ cái. Cue lấy
  lại theo luật này không có marker. Lệch số từ, có số, lệch từ 2 từ trở lên vẫn
  giữ chữ máy nghe kèm marker. [Luật đầy đủ](../../ASR_ACCEPTANCE_POLICY.md).
- **Caption nới lại tối đa 5 frame mỗi mép** khi còn chỗ, như 2.20.88 (#25).
- **Marker một dòng ngắn** dạng `Cue 4: chữ khác SRT – nghe lại` (#29).
- **Marker cho đoạn hình vượt ngưỡng tốc độ** (70–130% mặc định) khi dựng hình
  theo cue SRT, kéo dài hết đoạn đổi tốc độ (#31, #37).
- **Marker kiểm tra gắn vào clip voice A2** và đi theo clip khi kéo/cắt; marker
  phủ đúng đoạn cần cảnh báo (#37). Marker hiện ở mọi sequence dùng cùng file
  voice. Chỗ không gắn được (khoảng trống giữa hai clip, nhiều nguồn chồng nhau,
  không đọc được tốc độ) vẫn đặt trên thước timeline và log ghi rõ.
- **Giữ dữ liệu lượt chạy gần nhất** của mỗi nút trong
  `%LOCALAPPDATA%\PremiereVoiceSync\Jobs` để báo lỗi; file âm thanh tạm được bỏ (#33).

## Đã kiểm và còn chờ

- Bộ hồi quy `-NoWindowsIntegration` đạt 72 nhóm; 6 nhóm Windows integration không
  chạy. Replay ngoại tuyến project thật: câu SRT giữ nguyên văn 37/65 → 57/65,
  marker kiểm tra 17 → 6.
- Phép thử native trên Premiere 26.2.2 (#35, #37): marker ghi lên file voice hiện
  trên clip A2, đi theo khi kéo/trim, đặt được điểm kết thúc. Cách quy đổi giờ:
  in/out của clip đổi tốc độ được Premiere báo theo đơn vị đã chia tốc độ.
- **Chưa kiểm trên Premiere thật toàn bộ quy trình**; chưa đo marker trên clip nest
  V1, tốc độ khác 110%, reverse hoặc time remap.
- Mã nguồn FFmpeg 8.1.2 không đính kèm Release; xem link trong
  [THIRD_PARTY_NOTICES](../../../THIRD_PARTY_NOTICES.md).
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài.
