# 2.20.93 — Giảm các lần "nghỉ" khi dựng timeline

Prerelease. **Chưa nghiệm thu trên Premiere**; 2.20.91 vẫn là stable/Latest.

Ở 2.20.92, Dựng theo voice trên project thật (Sông Congo, 101 đoạn voice) mất 85 giây
cho bước dựng timeline. Khoảng 27 giây là chi phí chuyển giữa các đợt nhỏ, 25 giây là
một lần gắn marker lên clip voice, 5 giây gắn marker review và 4 giây sắp xếp clip.
Bản này sửa cả bốn chỗ.

## Thay đổi người dùng thấy

- **Bỏ chia đợt trong từng bước dựng** (#48). Mỗi bước chạy hết một lần thay vì nhiều đợt
  nhỏ có tự kiểm và vẽ lại xen giữa. Đổi lại, **Dừng/Tạm dừng có hiệu lực khi bước đang
  chạy kết thúc**, và timeline không vẽ lại trong một bước dài.
- **Sắp xếp clip đọc vị trí mỗi clip một lần** (#52). Trước đây một lần sắp xếp 260 clip
  đọc vị trí từ Premiere hơn 34.000 lần.
- **Marker được dời thay vì xóa rồi tạo lại** (#54). Marker cũ của tool được chuyển sang vị
  trí mới, chỉ ghi lại phần khác đi.
- **Marker voice và marker review được ghi trước khi cắt** (#56), lúc mỗi file mới có một
  clip dùng nó, nên mỗi lệnh ghi nhanh hơn. Bước gắn marker sau khi dựng vẫn quyết định
  kết quả; marker cuối cùng giống bản trước. Nếu dựng lỗi hoặc bấm Dừng, tool trả marker
  của mình về như trước khi chạy và không đụng marker bạn tự đặt; nếu không trả về được,
  panel báo để bạn kiểm tra tay.
- **Log hiệu năng chi tiết hơn** (#50): thời gian từng loại lệnh marker; có thêm script
  thử đo marker trên Premiere cho người phát triển.

## Đã kiểm và còn chờ

- Bộ hồi quy `-NoWindowsIntegration` đạt 73 nhóm; 6 nhóm Windows integration không chạy.
- Test mô phỏng: lệnh sửa timeline không đổi; marker cuối cùng giống bản trước trên 42
  fixture ở cả bốn chế độ chạy; fixture 65 đoạn ghi toàn bộ marker voice trước khi cắt và
  không phải ghi lại sau khi dựng; các tình huống lỗi/Dừng trả marker về đúng trạng thái cũ.
- Script thử trên Premiere 26.2.2 (17/11/2026, project thật, file voice có 37 marker): mỗi
  lệnh marker 7–25 ms khi file có 1 clip, 23–47 ms khi có 101 clip; dời marker bằng số giây
  được Premiere chấp nhận. Hai lượt thử dọn sạch, 37 marker trước và sau.
- **Chưa chạy trên Premiere thật** cho cả quy trình: chưa đo được thời gian tiết kiệm thực
  tế, chưa quan sát marker ghi trước có nằm đúng đoạn clip sau khi cắt/đổi tốc độ/dời.
- Bấm Dừng khi bước cuối đang chạy sẽ trả marker về như cũ dù bước đó dựng xong; timeline
  vẫn phải Undo như mọi lần Dừng.
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài.
