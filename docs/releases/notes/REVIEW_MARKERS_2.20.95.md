# 2.20.95 — Bản vá: sửa lỗi dời marker của 2.20.94

Prerelease. **Chưa nghiệm thu trên Premiere**; 2.20.91 vẫn là stable/Latest.
**Không dùng 2.20.94 và 2.20.93 cho Dựng theo voice**; cập nhật lên bản này.

## Lỗi của 2.20.94

Lượt chạy thật ngày 18/11/2026 trên project có marker cũ dạng đoạn: bước dựng timeline đã
cắt và đổi tốc độ xong, nhưng bước cập nhật marker báo lỗi. Mọi marker phải dời (19 marker
trên clip hình, 21 marker review trên voice) đều kiểm tra lại sai, và tool không trả được
marker về đúng như cũ. Panel báo 43 cảnh báo chưa gắn được marker.

Nguyên nhân: trong Premiere, đổi điểm bắt đầu của marker sẽ dời cả marker và giữ nguyên độ
dài; đổi điểm cuối chỉ đổi điểm cuối. Khi dời marker về sau, tool ghi điểm cuối trước rồi
mới dời điểm bắt đầu, nên điểm cuối bị văng ra sau. Bước trả marker về cũng dùng cùng cách
ghi. 2.20.93 có cùng đoạn mã dời marker; lượt chạy 2.20.93 trước đó không phải dời marker
nào nên không lộ lỗi.

## Thay đổi

- **Ghi điểm bắt đầu trước, đọc lại rồi mới ghi điểm cuối** khi dời marker và ở mọi bước trả
  marker về như cũ (#67). Marker mới tạo đã là dạng điểm nên không ghi thêm điểm cuối.
- Kế thừa toàn bộ thay đổi marker của 2.20.94: không chồng qua các lần chạy, dạng điểm ở giữa
  đoạn, gộp theo loại, không còn marker dự phòng trên thước timeline.

## Nếu đã chạy 2.20.94 và gặp lỗi

Timeline và marker có thể đã bị sửa một phần. Không lưu project; đóng và mở lại bản đã lưu
trước lượt chạy đó, rồi chạy lại bằng 2.20.95.

## Đã kiểm và còn chờ

- Phép thử trên Premiere 26.2.2 (18/11/2026, chỉ marker thử có tag, dọn sạch: 59 trước,
  59 sau) xác nhận cách Premiere ghi điểm đầu/cuối marker; xem
  [hướng dẫn probe](../../../tools/probes/README.md).
- Mock marker trong test giờ giữ độ dài khi đổi điểm bắt đầu như Premiere. Với mock này, test
  dời marker chạy đỏ trên code 2.20.94 và xanh sau khi sửa.
- Bộ hồi quy `-NoWindowsIntegration` đạt 73 nhóm; 6 nhóm Windows integration không chạy.
- **Chưa chạy lại Dựng theo voice trên Premiere** với bản này.
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài.
