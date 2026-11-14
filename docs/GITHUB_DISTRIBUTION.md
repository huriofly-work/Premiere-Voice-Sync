# Quản lý và phân phối trên GitHub

Repo hiện hành: [huriofly-work/Premiere-Voice-Sync](https://github.com/huriofly-work/Premiere-Voice-Sync),
khởi tạo lại ngày 14/11/2026 bằng một commit snapshot và chưa có release
([lý do](maintenance/REPO_RESTART_2026-11-14.md)). Tag, SHA và link release trong
`docs/releases/*.json` thuộc lịch sử cũ và được giữ nguyên làm bằng chứng.
Tài khoản phát triển của project là `huriofly-work`. Xem
[cấu hình và kiểm chứng sau chuyển tài khoản](maintenance/GITHUB_ACCOUNT_MIGRATION_2026-11-01.md).

Mỗi đợt sửa cần có mã nguồn/test/tài liệu trên nhánh `claude/`, PR có kết quả
CI, và bản phân phối gắn với tag trỏ đúng commit. Không chỉ giữ bản cài local.
Những thay đổi runtime chưa nghiệm thu trong Premiere được phát hành dưới
dạng **prerelease**, không thay bản stable/Latest đã được chấp nhận.

## Quy trình mỗi lần phát hành

1. Kiểm diff và trạng thái Git, cập nhật VERSION/changelog và metadata nhúng.
   Commit mã nguồn, test, tài liệu và khóa runtime; giữ audio, project, cache,
   jobs, weights thử nghiệm và binary sinh ra ngoài Git. Bộ cài chính thức
   vẫn chứa runtime/model baseline cần thiết theo quy trình đóng gói hiện có.
2. Chạy bộ hồi quy phù hợp; kiểm mã runtime trong gói khớp nguồn và hash các
   payload. Ghi kết quả/nghiệm thu/giới hạn thật trong `docs/releases/<version>.json`.
   GitHub CI chạy `-NoWindowsIntegration`; không phải bằng chứng nghiệm thu
   Premiere hay toàn bộ integration Windows.
3. Push nhánh, tạo PR vào `main`, đính kèm PR vào chat và chờ CI. Không tự merge
   các PR cũ hoặc nâng nhãn stable chỉ vì test tự động đạt.
4. Kiểm gói đã được xác minh bằng `tools/Verify-GitHubDistribution.ps1 -PackagePath
   <zip>`. Tạo GitHub Release nháp, target đúng SHA của commit trong PR, tải ZIP
   và file `.sha256` tương ứng. Xác minh asset đã lên đủ và đúng SHA-256/size,
   rồi mới công bố. Dùng `--prerelease --latest=false` khi native acceptance
   còn pending. Nội dung release nêu những gì đã kiểm và các lỗi còn mở.
5. Kiểm lại tag, target SHA, URL tải và digest trên GitHub; ghi liên kết PR/
   release và kết quả CI trong báo cáo giao việc. Giữ các bản trước để quay lại.

Gói phát hành được chọn theo hash đã kiểm chứng; không tự build lại rồi tải
một ZIP khác cùng version mà không xác minh lại. Không ghi đè asset đã công
bố bằng `--clobber`; phát hành version mới khi byte hoặc runtime thay đổi.

## Đồng bộ 2.20.72

Đợt đồng bộ này gom mã nguồn/test/tài liệu tích lũy sau commit 2.20.27, gồm
SRT join, timing/recovery, marker, pause/cancel và thông báo Windows. PR có
phạm vi lớn hơn riêng hai lib sửa ở 2.20.72; release notes phải nói rõ điều đó.

ZIP 2.20.72 được giữ nguyên đúng byte của gói đã kiểm/cài local, hash ở
`releases/2.20.72.json`. Source hiện có thêm tài liệu nghiên cứu/quy trình và
kết quả xác minh sau khi gói được tạo; đây không phải tính năng ASR đa ngôn
ngữ mới trong bộ cài. Runtime baseline vẫn Whisper small; ưu tiên hiện tại
là sửa SRT/tiếng Việt. Nghiệm thu native và các cue còn chưa giải quyết được
ghi rõ trong metadata và release notes.
