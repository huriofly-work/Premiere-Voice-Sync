# 2.20.92 — Sửa lỗi dừng ở bước lập kế hoạch, thêm số đo timeline

Prerelease. **Chưa nghiệm thu trên Premiere**; 2.20.91 vẫn là stable/Latest.

## Thay đổi người dùng thấy

- **Dựng theo voice không còn dừng ở bước "Lập kế hoạch theo câu"** (#43). Lỗi
  hiện trên panel là `ACOUSTIC_PARTITION_SOURCE_BOUNDARY_CHANGED`, gặp ở project có
  vùng sửa tay. Nguyên nhân: bước tự kiểm tính lại điểm cắt hình bằng kiểu số khác
  bộ lập kế hoạch, nên khi điểm giữa hai câu rơi đúng nửa frame thì hai bên làm tròn
  khác nhau 1 frame và tool tự dừng. Giờ bước tự kiểm tính giống hệt bộ lập kế
  hoạch. Điểm cắt, ngưỡng an toàn và các bước kiểm giữ nguyên; lỗi xảy ra trước khi
  tool sửa timeline nên project của lượt lỗi không bị đụng tới.
- **Log hiệu năng chi tiết hơn** (#45). `Performance_*.jsonl` trong
  `%LOCALAPPDATA%\PremiereVoiceSync\Logs` ghi thêm, cho từng bước dựng timeline
  chậm: số marker và số lần đọc/ghi marker, thời gian duyệt clip và sắp xếp ở các
  bước "Chuẩn bị…". Dùng để tìm vì sao timeline "làm một khúc lại nghỉ"; bản này
  chưa tăng tốc.

## Đã kiểm và còn chờ

- Bộ hồi quy `-NoWindowsIntegration` đạt 72 nhóm; 6 nhóm Windows integration không
  chạy. Test mới tái hiện lỗi #43 (đỏ trước sửa, xanh sau sửa).
- Job thật bị lỗi ngày 16/11/2026 chạy lại ngoại tuyến bước lập kế hoạch: ra kế
  hoạch đầy đủ (101 đoạn, 14 vùng sửa tay), điểm cắt giữ nguyên frame cũ.
- Phần đo #45: test mô phỏng so chuỗi lệnh gửi Premiere giữa bản có đo và bản không
  đo, giống nhau ở cả bốn chế độ chạy.
- **Chưa chạy trên Premiere thật**: cần chạy lại project bị lỗi và một lượt Auto
  edit nhiều đoạn cắt để lấy số đo.
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài.
