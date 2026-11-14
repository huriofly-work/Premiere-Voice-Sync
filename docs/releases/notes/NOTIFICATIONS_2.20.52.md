# Premiere Voice Sync 2.20.52

Sửa lỗi “Chưa nạp bộ lập kế hoạch nguồn audio” tại preflight của Chỉ tạo subtitle. Planner được giữ trên đối tượng Adobe dùng chung, kiểm đầy đủ khi bootstrap và host được nạp lại từ UTF-8 để tránh thông báo tiếng Việt bị vỡ. Chỉ hiện hướng dẫn Encoding 0% khi lỗi xảy ra ở native export.

Log lần chạy 17/10/2026 08:27 trên 2.20.51 ghi prepare thất bại sau 335 ms, trước native export/ASR/caption. Lỗi này không chứng minh WAV/project bị hỏng.

Kiểm tự động: bootstrap qua nhiều lượt gọi, receiver tạm, host cũ/thiếu module, lỗi đọc và retry, UTF-8; hồi quy resolver/export và bộ kiểm dự án. Đây là kiểm fixture/VM, cần chạy lại trong Premiere để xác nhận WAV/ASR/caption thực tế.

Trước khi cài, lưu công việc và đóng Premiere cùng helper thông báo nếu đang mở; bộ cài giữ chốt kiểm tra tiến trình. Sau cập nhật, mở Premiere/panel, xác nhận 2.20.52, bấm Cập nhật đầu vào rồi chạy lại. Không tự thao tác timeline hay lưu project. Chưa nghiệm thu native.

Kết quả kiểm ngày 17/10/2026: 45 nhóm đạt, parse 114 script PowerShell; sáu nhóm Windows integration được bỏ qua theo runner. Log: .tmp-host-bootstrap/suite-full.log. Syntax ES3 của host/model và generated-source check đạt. Đã cài sau khi người dùng đóng Premiere/helper; chưa thử native.

Cài 17/10/2026 08:34: xác minh 61 tệp đúng checksum, giữ nguyên 924 tệp/24 thư mục dữ liệu và registry CEP. Sao lưu panel 2.20.51 và bằng chứng tại dist/_installation-2.20.52-20261017-083448/verified.json. Không thao tác project hoặc khởi chạy Premiere/helper. Gói ZIP SHA256: C5B5C00DE0E9A2D8EB134CA14181E203DFBC53D26DDE72AE012E5C76ED52AB23.
