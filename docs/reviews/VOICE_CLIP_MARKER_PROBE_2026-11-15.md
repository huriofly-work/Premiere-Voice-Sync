# Probe native marker clip voice — 15/11/2026

Issue #34. **ĐÃ CHẠY NATIVE — kết luận: khả dụng.** Marker ghi lên ProjectItem
của voice hiện trên clip A2 ở timeline và đi theo clip khi kéo/trim, với điều kiện
quy đổi giờ đúng như mục "Công thức" bên dưới.

Probe: `tools/probes/Probe-VoiceClipMarkers.jsx`; quy trình/lệnh tại
[README](../../tools/probes/README.md). Không sửa feature host hay panel.

## Điều kiện

| Điều kiện / quan sát | Giá trị / bằng chứng |
| --- | --- |
| Ngày chạy, người thao tác | 15/11/2026; Claude chạy lệnh qua CEP remote debugging, user quan sát và thao tác UI |
| Premiere version | 26.2.2 (CEP 12, `PlayerDebugMode` đã bật sẵn) |
| Runner | Node 26, `tools/probes/run-probe.js`, port 8099 (`.debug` tạm, đã gỡ sau phép thử) |
| Sequence thử | Bản sao do user tự duplicate, 30 fps, 49 clip voice trên A2 |
| Voice ProjectItem | Một file WAV dùng chung cho cả 49 clip A2, tốc độ 110% (`getSpeed()` = 1,1) |
| Marker có sẵn trước phép thử | 0 trên ProjectItem voice |

## Lượt 1 — marker rơi vào khoảng trống (tưởng là không hiện)

Clip index 3 (start 6,400; inPoint 6,200; outPoint 8,167). `createMarker(6,7)`
trả marker, đọc lại 6,700 s. User không thấy trên timeline, chỉ thấy trong Source
Monitor ở 00;00;06;20. Nguyên nhân: công thức dự đoán dùng sai đơn vị (xem dưới);
theo công thức đúng marker ở 6,291 s, nằm trong khoảng trống 6,067–6,400 giữa
clip 2 và clip 3, nên không clip nào hiện nó.

## Lượt 2 — marker hiện và đi theo clip

Clip index 6 (start 12,567; inPoint 12,367; outPoint 21,200). `createMarker(16,367)`.

| Bước | Dự đoán (công thức đúng) | User quan sát |
| --- | --- | --- |
| Sau khi tạo | 12,567 + 16,367/1,1 − 12,367 = 15,079 s | 00:00:15:02 trên clip A2 |
| Sau khi user kéo clip sang phải và trim mép cuối (start 18,500; in 12,367; out 16,500) | 18,500 + 16,367/1,1 − 12,367 = 21,012 s (frame 630) | 00:00:21:00, marker đi theo clip |
| `remove` | attempted 1, remaining 0 | `list`: 0 marker trên ProjectItem |

User cũng xác nhận: marker thêm tay trong Source Monitor của file voice hiện đồng
thời trên clip timeline của sequence.

## Lượt 3 — marker có độ dài (kiểm cho issue #36)

Clip dài nhất trên A2 (start 100,067; inPoint 99,867; speed 1,1). Marker tạo ở giờ
nguồn `(100,567 − 100,067 + 99,867) × 1,1 = 110,403`, rồi gán `marker.end = 113,703`
(số giây, không cần đối tượng `Time`). Đọc lại: start 110,403, end 113,703. Dự đoán
trên timeline 100,567 → 103,567 s; user thấy một dải marker 00:01:40:16 → 00:01:43:16.
Lệch 1 frame vì 100,5666… × 30 = 3016,99 và Premiere hiển thị phần nguyên của frame.
Đã xóa, 0 marker còn lại.

## Công thức

Với Premiere 26.2.2, `TrackItem.inPoint`/`outPoint` của clip đã đổi speed được báo
theo đơn vị **đã chia cho speed** (độ dài in→out bằng độ dài trên timeline), còn
giờ marker của ProjectItem là **giờ thật trong file nguồn**:

- giờ nguồn thật của điểm timeline `t` trên clip: `(t − start + inPoint) × speed`
- vị trí timeline của marker nguồn `m`: `start + m / speed − inPoint`

Bằng chứng: hai lượt đo trên cùng clip 110% khớp đến frame. Chưa đo với speed khác,
reverse speed, time remapping hay clip nest.

## Bằng chứng API

TrackItem trên Premiere 26.2.2 không có `getMarkers`/`markers`; marker chỉ ghi qua
`ProjectItem.getMarkers()`. Marker này dùng chung cho mọi clip/sequence dùng cùng
media, hiện trên clip nào có vùng nguồn chứa nó. Marker có thời gian vào/ra
(`start`/`end`), nên có thể phủ đúng đoạn cần cảnh báo (ý của user).

## Kết luận và hệ quả

- Khả thi: gắn marker review lên voice qua ProjectItem, giờ nguồn tính theo công
  thức trên, `start`/`end` phủ đúng đoạn cần cảnh báo. Marker đi theo clip khi kéo/trim.
- Rủi ro đã biết: marker hiện ở mọi sequence dùng cùng file voice; đoạn nguồn bị
  dùng lại hai lần sẽ hiện marker ở cả hai nơi.
- Code hiện có đặt marker clip (V1 tốc độ, A2 "Kiem tra can voice") theo tỉ lệ
  của `inPoint`/`outPoint` rồi dùng như giờ nguồn thật; với speed khác 100% vị trí
  này lệch và có thể rơi ra ngoài clip. Phải sửa theo công thức trên.
- Không Save/Undo. `.debug` tạm đã gỡ khỏi thư mục panel đã cài; panel đang mở vẫn
  giữ cổng debug tới khi đóng/mở lại.
