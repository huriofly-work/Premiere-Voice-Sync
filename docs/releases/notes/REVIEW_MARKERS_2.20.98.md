# 2.20.98 — Bản vá: marker review ghi trước khi cắt không bị trả về vì làm tròn tick

Prerelease; 2.20.91 vẫn là stable/Latest. Bản vá cho 2.20.97: không dùng 2.20.97 cho Dựng theo voice. Chưa chạy bản này trên Premiere.

## Lỗi đã sửa

Lượt Dựng theo voice 2.20.97 trên project Sông Congo (19/11/2026) hỏng sau khi đã cắt timeline ([#82](https://github.com/huriofly-work/Premiere-Voice-Sync/issues/82)).
- Marker review đã được ghi trước khi cắt như thiết kế (21 marker, 751 ms).
- Sau khi cắt, tool so vị trí các đoạn voice dự đoán với vị trí thật, thấy "khác" nên trả marker về như cũ.
- Bước tự kiểm sau khi trả về báo `Original marker fields differ.` Báo cáo ghi `ok=false` và timeline đã bị sửa.

Phép đo trên Premiere 26.2.2 cho thấy nguyên nhân. Sequence đã dựng có 101 clip voice ở speed 110%:
- Vị trí đầu và cuối của mọi clip trên timeline nằm đúng mốc frame.
- Điểm vào trong file nguồn của 100/101 clip lệch mốc frame tới khoảng 80 tick, vì Premiere chia vị trí nguồn theo speed rồi làm tròn. Tick là đơn vị thời gian nhỏ nhất của Premiere, 254.016.000.000 tick mỗi giây.

Tool so hai giá trị này "bằng tuyệt đối" nên luôn báo lệch.

## Thay đổi

- Phép so vị trí đoạn voice có sai số cho phép (#83):
  - Vị trí đầu và cuối trên timeline: tối đa 1 tick.
  - Điểm vào nguồn: tối đa 1/1000 frame, khoảng 8.467 tick ở 30 fps, rộng gấp hơn 100 lần mức lệch đo được.
  - Speed, file nguồn và số đoạn vẫn phải khớp tuyệt đối.
  - Đoạn voice bị dời thật vẫn bị bắt và marker vẫn được trả về.
- Báo cáo có mục `voiceProjection`: số đoạn đã so, lần lệch đầu tiên vượt ngưỡng (`firstMismatch`) và độ lệch lớn nhất của từng trường (`maxAbsDeltaTicks`).
- Câu lỗi khi khôi phục marker giữ câu cũ ở đầu, rồi nêu tối đa ba trường lệch cùng giá trị. Với comments, câu lỗi chỉ ghi độ dài.
- Công cụ dev mới `tools/probes/Probe-MarkerRestore.jsx` (không nằm trong gói cài).

## Cần user làm

Sau khi cài, chạy **Dựng theo voice** một lần trên Sông Congo rồi báo lại. Kỳ vọng:
- Lượt chạy xong, không có lỗi khôi phục marker.
- Marker review được ghi ở bước ghi trước khi cắt, và bước hậu kiểm gần như không phải ghi lại chúng.
- Trong báo cáo, `voiceProjection.firstMismatch` là `null`.

## Đã kiểm và còn chờ

- Test tái hiện mô phỏng clip speed 110% làm tròn theo tick như Premiere: đỏ trên 2.20.97, xanh sau khi sửa. Hai test khác chứng minh độ lệch vượt ngưỡng vẫn đi vào nhánh khôi phục.
- Probe chạy trên project thật, không Save. Dọn xong vẫn đủ 59 marker trên file voice.
  - `restore-projection` đã đo được độ lệch nêu trên.
  - `restore-run` (bốn ca đơn lẻ) và `restore-journal` (hai lượt ghi trên cùng file, comments tiếng Việt nhiều dòng) đều khôi phục chính xác.
- Chưa tái hiện được vì sao bước khôi phục của 2.20.97 báo lệch trường. Sau bản sửa, lượt chạy bình thường không còn đi vào bước khôi phục. Nếu lỗi quay lại, câu lỗi sẽ nêu trường lệch.
- Chưa chạy bản này trên Premiere.
- Marker hình (tốc độ/gộp hình) vẫn bị dời và ghi lại ở mỗi lượt, khoảng 7,8 giây; theo dõi ở [#75](https://github.com/huriofly-work/Premiere-Voice-Sync/issues/75).
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài.
