# 2.20.97 — Marker review được ghi trước khi cắt

Prerelease; 2.20.91 vẫn là stable/Latest. Chưa chạy bản này trên Premiere.

## Lỗi đã sửa

Từ 2.20.93, Dựng theo voice có bước ghi trước marker review khi file voice còn một clip, vì lúc đó mỗi lần ghi
nhanh hơn khoảng ba lần. Trên Premiere, bước này chưa bao giờ ghi gì: mọi marker review vẫn được ghi sau khi cắt,
khi file voice đã có khoảng 100 clip ([#72](https://github.com/huriofly-work/Premiere-Voice-Sync/issues/72)).

Số đo của 2.20.96 chỉ ra nguyên nhân. Tool nhận diện file voice bằng một khoá, nhưng phần marker review tính ra
khoá khác với phần ghi trước, nên không tìm thấy file. Gốc lỗi nằm ở ExtendScript, ngôn ngữ script cũ trong
Premiere: nó tính biểu thức điều kiện lồng nhau không có ngoặc theo cách khác JavaScript thông thường. Phép thử
trên Premiere ngày 18/11/2026 đã xác nhận điều này. Test tự động chạy bằng JavaScript thông thường nên không thấy
lỗi.

## Thay đổi

- Mọi nhóm marker dùng chung một cách tính khoá file nguồn. Marker review được ghi trước khi cắt như thiết kế (#76).
- Cảnh báo không gắn được vì nhiều clip cùng khớp nay báo đúng lý do "Nhiều clip cùng phù hợp.".
- Test mới chặn kiểu viết biểu thức gây lỗi này trong mọi file chạy trong Premiere.
- Giữ số đo chẩn đoán của 2.20.96 để kiểm lại trên lượt chạy thật.

## Cần user làm

Sau khi cài, chạy **Dựng theo voice** một lần trên project có cảnh báo review (ví dụ Sông Congo), rồi báo lại.
Kỳ vọng: marker review được ghi ở bước "Ghi trước marker review", và bước hậu kiểm gần như không phải ghi lại
marker review.

## Đã kiểm và còn chờ

- Test mới đỏ trên 2.20.96 ở 7 vị trí và xanh sau sửa. Bộ hồi quy `-NoWindowsIntegration` đạt 75 nhóm; 6 nhóm
  Windows integration không chạy.
- Executor có đo và không đo vẫn gọi Premiere giống hệt nhau trên 42 fixture × 4 chế độ.
- Chưa chạy bản này trên Premiere; thời gian tiết kiệm được chưa đo.
- Marker hình (tốc độ/gộp hình) vẫn được ghi sau dựng theo thiết kế. Chúng còn bị dời và ghi lại ở mỗi lượt chạy,
  khoảng 7,8 giây; việc này theo dõi ở [#75](https://github.com/huriofly-work/Premiere-Voice-Sync/issues/75).
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài.
