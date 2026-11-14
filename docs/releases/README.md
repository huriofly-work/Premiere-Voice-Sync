# Phát hành và ghi chú phiên bản

Repo được khởi tạo lại ngày 14/11/2026 nên chưa có release trên GitHub
([lý do](../maintenance/REPO_RESTART_2026-11-14.md)). Trong lịch sử cũ, stable đã
nghiệm thu là 2.20.25 và prerelease mới nhất là 2.20.90, còn chờ nghiệm thu
Premiere. Các JSON dưới đây giữ nguyên tag, SHA và link của repo cũ làm bằng chứng.

- [Tổng quan lịch sử đến 2.20.88](OVERVIEW_THROUGH_2.20.88.md), chuyển nguyên nội dung mô tả các bản từ README cũ, chỉ cập nhật link.
- [Quy trình phân phối GitHub](../GITHUB_DISTRIBUTION.md), [đóng gói](../RELEASE.md).
- JSON `<version>.json` trong thư mục này giữ metadata/hash/bằng chứng phát hành gốc.
- Bộ cài cũ, sidecar và staging local được giữ cùng phiên bản ở `dist/archive/releases/`.

## Ghi chú theo phiên bản

- [2.20.88 — Giảm tính chữ lặp và các đợt đổi tốc độ không có việc](notes/AUTO_EDIT_ACOUSTIC_2.20.88.md)
- [2.20.87 — Chia đợt native có giới hạn và dữ liệu gọn](notes/AUTO_EDIT_ACOUSTIC_2.20.87.md)
- [2.20.86 — Dựng hình theo cue SRT](notes/AUTO_EDIT_ACOUSTIC_2.20.86.md)
- [Auto edit: tự giải quyết timing trước khi yêu cầu sửa tay](notes/AUTO_EDIT_ACOUSTIC_2.20.85.md)
- [Marker phản ánh đúng phạm vi cần rà — 2.20.84](notes/REVIEW_MARKERS_2.20.84.md)
- [Nhận diện khó chuyển sang review và tiếp tục — 2.20.83](notes/EDITED_VOICE_2.20.83.md)
- [Auto edit nhiều file voice và phục hồi từng câu — 2.20.82](notes/EDITED_VOICE_2.20.82.md)
- [Khoảng không lời mặc định 0,5 giây — 2.20.81](notes/EDITED_VOICE_2.20.81.md)
- [Khoảng không lời bị nuốt khi gộp câu — 2.20.80](notes/EDITED_VOICE_2.20.80.md)
- [Vùng khó cần sửa tay trong Auto edit — 2.20.79](notes/EDITED_VOICE_2.20.79.md)
- [Auto edit phục hồi chữ SRT trước chốt omission — 2.20.78](notes/EDITED_VOICE_2.20.78.md)
- [2.20.77 — giữ primary DTW khi lượt bổ sung chỉ còn timing ước lượng](notes/SUBTITLE_TIMING_2.20.77.md)
- [2.20.76 — giữ outro ASR ban đầu khi lượt bổ sung mất lời](notes/SUBTITLE_TIMING_2.20.76.md)
- [2.20.75 — adapter nhận diện và thử timing tiếng Việt](notes/SUBTITLE_TIMING_2.20.75.md)
- [Premiere Voice Sync 2.20.74 — giữ SRT qua dạng chữ ASR và ngữ cảnh ngắn](notes/SUBTITLE_TIMING_2.20.74.md)
- [Premiere Voice Sync 2.20.73 — căn từ theo chính sách giữ SRT](notes/SUBTITLE_TIMING_2.20.73.md)
- [Premiere Voice Sync 2.20.72 — xét lại câu SRT trước khi dùng ASR](notes/SUBTITLE_TIMING_2.20.72.md)
- [Âm thanh cùng thông báo Windows 2.20.71](notes/NOTIFICATIONS_2.20.71.md)
- [Kênh thông báo thống nhất 2.20.70](notes/NOTIFICATIONS_2.20.70.md)
- [Thông báo hoàn tất 2.20.69](notes/NOTIFICATIONS_2.20.69.md)
- [Thông báo hoàn tất 2.20.68](notes/NOTIFICATIONS_2.20.68.md)
- [Premiere Voice Sync 2.20.67 — nhãn một chữ trong SRT](notes/SUBTITLE_TIMING_2.20.67.md)
- [Premiere Voice Sync 2.20.66 — nguồn SRT và audio gọn hơn](notes/SRT_JOIN_2.20.66.md)
- [Premiere Voice Sync 2.20.65 — thông báo và giao diện gọn hơn](notes/NOTIFICATIONS_2.20.65.md)
- [Premiere Voice Sync 2.20.64 — giữ SRT trong Short và chỉ rõ chữ ASR](notes/SUBTITLE_TIMING_2.20.64.md)
- [Premiere Voice Sync 2.20.63 — nguồn SRT và ngôn ngữ voice](notes/SRT_JOIN_2.20.63.md)
- [Premiere Voice Sync 2.20.62 — nhận ra câu thì giữ chữ SRT](notes/REVIEW_MARKERS_2.20.62.md)
- [Premiere Voice Sync 2.20.61 — giữ câu có số và câu cuối SRT trong Short](notes/SUBTITLE_TIMING_2.20.61.md)
- [Premiere Voice Sync 2.20.60 — bỏ marker số và chặn chữ thừa ở biên SRT](notes/SUBTITLE_TIMING_2.20.60.md)
- [Premiere Voice Sync 2.20.59 — nhận ra câu để giữ chữ SRT](notes/SUBTITLE_TIMING_2.20.59.md)
- [Premiere Voice Sync 2.20.58 — bỏ marker giữ chữ SRT khớp phần lớn](notes/REVIEW_MARKERS_2.20.58.md)
- [Kiểm tra toàn bộ marker của lần chạy 2.20.57](notes/MARKER_AUDIT_2.20.57.md)
- [Premiere Voice Sync 2.20.57 — nhận diện bổ sung có ngữ cảnh và bằng chứng](notes/SUBTITLE_TIMING_2.20.57.md)
- [Premiere Voice Sync 2.20.56 — ưu tiên giữ chữ SRT khi nhận diện gần khớp](notes/SUBTITLE_TIMING_2.20.56.md)
- [Premiere Voice Sync 2.20.55 — đối chiếu marker theo từng nguồn](notes/REVIEW_MARKERS_2.20.55.md)
- [Premiere Voice Sync 2.20.54 — nối nhiều SRT](notes/SRT_JOIN_2.20.54.md)
- [Premiere Voice Sync 2.20.53](notes/NOTIFICATIONS_2.20.53.md)
- [Premiere Voice Sync 2.20.52](notes/NOTIFICATIONS_2.20.52.md)
- [Voice đã lược bỏ nội dung — 2.20.51](notes/EDITED_VOICE_2.20.51.md)
- [2.20.50 — nguồn audio và phạm vi subtitle](notes/NOTIFICATIONS_2.20.50.md)
- [2.20.49 — ưu tiên SRT trong Project cho Chỉ tạo subtitle](notes/SRT_PRIORITY_2.20.49.md)
- [2.20.48 — marker số trỏ đúng caption chứa số](notes/REVIEW_MARKERS_2.20.48.md)
- [2.20.47 — marker tại các mốc cần kiểm tra](notes/REVIEW_MARKERS_2.20.47.md)
- [2.20.46 — phục hồi timing tham chiếu trước khi nhận diện bổ sung](notes/SUBTITLE_TIMING_2.20.46.md)
- [2.20.45 — timing âm học dùng chung trong Auto edit](notes/NOTIFICATIONS_2.20.45.md)
- [2.20.44 — đo từng phần của bước xuất audio](notes/NOTIFICATIONS_2.20.44.md)
- [2.20.43 — sửa lệch ranh giới Chỉ tạo subtitle](notes/SUBTITLE_TIMING_2.20.43.md)
- [2.20.42 — tối ưu căn SRT/voice theo từng nguồn](notes/NOTIFICATIONS_2.20.42.md)
- [2.20.41 — dùng chung lõi căn SRT/voice](notes/NOTIFICATIONS_2.20.41.md)
- [2.20.40 — SRT dài và nhận diện bổ sung](notes/NOTIFICATIONS_2.20.40.md)
- [2.20.39 — tạm dừng và tiếp tục](notes/NOTIFICATIONS_2.20.39.md)
- [2.20.38 — dừng tác vụ đang chạy](notes/NOTIFICATIONS_2.20.38.md)
- [2.20.37 — tách chuẩn bị audio khỏi lượt encoding](notes/NOTIFICATIONS_2.20.37.md)
- [2.20.36 — kiểm tra lỗi xuất WAV trước khi tạo subtitle](notes/NOTIFICATIONS_2.20.36.md)
- [Bản chờ kiểm thử 2.20.35 — chỉ nhận diện track voice](notes/NOTIFICATIONS_2.20.35.md)
- [Bản sửa 2.20.34 — kiểm tra caption-only trên CEP](notes/NOTIFICATIONS_2.20.34.md)
- [Thông báo 2.20.33 — áp dụng thống nhất theo tình huống](notes/NOTIFICATIONS_2.20.33.md)
- [Thông báo 2.20.32 — gia cố và kiểm thử không điều khiển Windows](notes/NOTIFICATIONS_2.20.32.md)
- [Thông báo nhiều kênh — ứng viên 2.20.31](notes/NOTIFICATIONS_2.20.31.md)
- [Thông báo và xử lý sự cố 2.20.30](notes/NOTIFICATIONS_2.20.30.md)
- [Rà soát 2.19.2](notes/AUDIT-2.19.2.md)

[Mục lục chung](../README.md)
