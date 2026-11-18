# 2.20.96 — Số đo để tìm vì sao marker review không được ghi trước khi cắt

Prerelease; 2.20.91 vẫn là stable/Latest. **Không đổi cách dựng hay cách ghi marker so với 2.20.95.**
Bản này chỉ thêm số đo vào nhật ký Dựng theo voice, để lượt chạy thật kế tiếp chỉ ra lý do của một
lỗi còn mở ([#72](https://github.com/huriofly-work/Premiere-Voice-Sync/issues/72)).

## Lỗi đang tìm

Từ 2.20.93, Dựng theo voice có bước ghi trước marker voice và marker review khi file voice còn một
clip, vì lúc đó mỗi lần ghi nhanh hơn khoảng ba lần. Ở ba lượt chạy thật ngày 18/11/2026 (2.20.93,
2.20.94, 2.20.95), bước này không ghi gì. Mọi marker review vẫn được ghi sau khi cắt, khi file voice đã
có khoảng 100 clip, tốn khoảng 8,7 giây. Kết quả dựng vẫn đúng; chỉ chậm hơn dự kiến.

Hai giả thuyết đã được loại:

- **Clip giữ từ lần gọi trước bị mất định danh nguồn.** Đã loại bằng phép thử chỉ đọc trên Premiere: 0/100
  clip lệch.
- **Premiere trả đối tượng mới ở mỗi lần đọc clip.** Mock mô phỏng đúng hành vi này vẫn ghi trước bình
  thường, nên đây không phải nguyên nhân.

## Thay đổi

- Nhật ký `Performance_*.jsonl` ghi thêm ở các bước "Ghi trước marker voice/review" và bước hậu kiểm:
  - khoá nguồn của từng nhóm marker, có đủ điều kiện ghi trước không, số marker cần ghi;
  - số nhóm review đã chuẩn bị, lý do cảnh báo chưa gắn được;
  - bước tra nguồn có tìm thấy nhóm không.
- Số đo chỉ dùng dữ liệu đã có trong lượt dựng, không đọc thêm từ Premiere.
- Khoá theo đường dẫn được rút thành `path`, nên nhật ký không chứa tên file hay đường dẫn.

## Cần user làm

Sau khi cài, chạy **Dựng theo voice** một lần trên một project có cảnh báo review (ví dụ Sông Congo), rồi
báo lại. Nhật ký nằm trong `%LOCALAPPDATA%\PremiereVoiceSync\Logs`. Không cần thao tác gì thêm.

## Đã kiểm và còn chờ

- Bản executor không đo giống hệt 2.20.95 (so từng byte).
- Executor có đo và không đo gọi Premiere giống hệt nhau trên 42 fixture × 4 chế độ.
- Bộ hồi quy `-NoWindowsIntegration` đạt 74 nhóm; 6 nhóm Windows integration không chạy.
- Phép thử chỉ đọc `tools/probes/Probe-StaleTrackItem.jsx` đã chạy trên Premiere ngày 18/11/2026.
- Chưa chạy bản này trên Premiere; số đo mới chưa được đọc từ lượt chạy thật nào.
- Cài đặt: đóng Premiere và helper thông báo bằng tay trước khi cài.
