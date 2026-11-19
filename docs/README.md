# Mục lục tài liệu

Đọc [hướng dẫn sử dụng](USER_GUIDE.md) để cài và chạy panel. Khi phát triển,
đọc [quy tắc khả thi](DEVELOPMENT_FEASIBILITY_POLICY.md), [bộ nhớ hồi quy](REGRESSION_MEMORY.md)
và tài liệu của luồng bị ảnh hưởng trước khi sửa mã.

| Nhóm | Nội dung |
| --- | --- |
| [Phát hành](releases/README.md) | Ghi chú từng bản, metadata JSON và lịch sử tổng quan. |
| [Rà soát](reviews/README.md) | Các báo cáo có ngày về giao diện, timing, marker, thông báo và bảo mật. |
| [Lịch sử](history/README.md) | Kiến trúc đến 2.20.22. |
| [Bảo trì project](maintenance/README.md) | Kết quả sắp xếp thư mục/nhánh và bảng tra đường dẫn cũ. |

## Tài liệu vận hành

- [Maintainer briefing](MAINTAINER_BRIEFING.md) và [bàn giao kỹ thuật](HANDOFF.md): bản đồ project cho người mới tiếp quản.
- [Cấu trúc project và dữ liệu local](PROJECT_LAYOUT.md).
- [Kiến trúc runtime](ARCHITECTURE.md), [đánh giá hiệu năng](PERFORMANCE_REVIEW.md).
- [Kiểm thử](TESTING.md), [bộ nhớ hồi quy](REGRESSION_MEMORY.md).
- [Khả thi trước phát triển](DEVELOPMENT_FEASIBILITY_POLICY.md), [nghiệm thu ASR](ASR_ACCEPTANCE_POLICY.md).
- [Quy trình GitHub](GITHUB_DISTRIBUTION.md), [đóng gói/phát hành](RELEASE.md), [bảo mật](SECURITY.md).
- [Công cụ developer](../tools/README.md).

## Trạng thái cần phân biệt

Repo khởi tạo lại ngày 14/11/2026 ([lý do](maintenance/REPO_RESTART_2026-11-14.md));
stable/Latest hiện tại là [2.20.98](releases/notes/REVIEW_MARKERS_2.20.98.md), user chạy thật
với hai project ngày 19/11/2026. Bản public đầu tiên là [2.20.91](releases/notes/REVIEW_MARKERS_2.20.91.md)
(stable đến 19/11/2026, user đã chạy thật ngày 15/11/2026); các prerelease
[2.20.92](releases/notes/AUTO_EDIT_ACOUSTIC_2.20.92.md),
[2.20.93](releases/notes/AUTO_EDIT_ACOUSTIC_2.20.93.md),
[2.20.94](releases/notes/REVIEW_MARKERS_2.20.94.md) và bản vá
[2.20.95](releases/notes/REVIEW_MARKERS_2.20.95.md); 2.20.95 đã chạy thật ngày 18/11/2026;
[2.20.96](releases/notes/REVIEW_MARKERS_2.20.96.md) chỉ thêm số đo chẩn đoán, đã chạy thật;
[2.20.97](releases/notes/REVIEW_MARKERS_2.20.97.md) sửa lỗi ghi trước marker review nhưng hỏng khi chạy thật;
bản vá 2.20.98 công bố prerelease rồi được nâng stable cùng ngày;
2.20.93/2.20.94/2.20.97 có lỗi marker, không dùng cho Dựng theo voice. Trước đó stable là 2.20.25 và
prerelease gần nhất là [2.20.90](releases/notes/ASR_TURBO_2.20.90.md). Nghiên cứu cue-first, chọn model ASR và Qwen đã đóng
ngày 13/11/2026; mã, test và báo cáo của chúng đã gỡ khỏi repo (chỉ còn trong
bản sao lưu lịch sử repo cũ, ngoài GitHub). Không coi test/CI hoặc việc sắp xếp này là nghiệm thu native.
