# Sắp xếp project 23–24/10/2026

Lần bảo trì này gom mã/tài liệu/bằng chứng để dễ tìm, giữ toàn bộ dữ liệu và
lịch sử. Không có thay đổi engine, executor, panel, model mặc định hoặc VERSION;
không tạo gói, cài panel hay gọi Premiere.

## Thư mục local

- Chuyển 114 tài liệu: 61 ghi chú phiên bản vào `docs/releases/notes/`, 22 tài liệu
  cue-first vào `docs/research/cue-first/`, 18 tài liệu ASR vào `docs/research/asr/`
  và 13 báo cáo vào `docs/reviews/`. Bổ sung mục lục từng nhóm, tools và experiments.
- Rút phần nhật ký dài khỏi README vào [tổng quan phát hành](../releases/OVERVIEW_THROUGH_2.20.88.md),
  giữ nội dung và cập nhật link. README phân biệt stable, prerelease và nghiên cứu.
- Cập nhật đường dẫn đọc tài liệu trong `installer/build-release.ps1`; kiểm khối
  xuất tài liệu riêng, không chạy build để tránh thay ZIP cùng version.
- Lưu trữ 510 mục: 131 workspace/log ở `_local/archive/2026-10-23/initial/`,
  379 mục cũ ở `dist/archive/`. Giữ bộ 2.20.25 và 2.20.88 ở `dist/` để tra/cài lại.
- Đối chiếu trước/sau khớp 29.489 file, 127.200.240.472 byte và toàn bộ metadata
  tương đối của các cây di chuyển. Đây là kiểm metadata cùng thao tác di chuyển
  trên cùng ổ, không phải tuyên bố đã hash toàn bộ 127 GB. Không giải phóng dung
  lượng bằng cách xóa file; gói cũ, bản sao panel, audio, jobs và cache được giữ.
- Hai cây model/nghiên cứu cần giữ đường dẫn, runtime local và dữ liệu người
  dùng đã cài không đổi địa chỉ. Hai file có chỉnh sửa từ trước là `AGENTS.md`
  và `tools/Build-AsrBlindReview.py` giữ nguyên byte và nằm ngoài commit bảo trì.

[Bảng chuyển tài liệu và hash](DOCUMENT_RELOCATIONS_2026-10-23.json) lưu đường
dẫn cũ/mới. JSON receipt lịch sử không được viết lại. Bảng di chuyển private,
snapshot file và Git bundle nằm ở `_local/maintenance/2026-10-23/`, bị loại khỏi Git.
Xem [cấu trúc và cách phục hồi](../PROJECT_LAYOUT.md).

## GitHub và lịch sử Git

Giữ `main`, `codex/github-sync-2.20.72` (PR #13 (repo cũ)),
`codex/cue-first-big-update` (PR #17 (repo cũ))
và nhánh bảo trì `codex/organize-project-2026-10-23`. Đây là trạng thái ngày
23/10: ngày 04/11, PR #89 đã merge toàn bộ nhánh `codex/` vào `main` rồi xóa
chúng, đầu nhánh lưu trong [inventory 04/11](BRANCH_INVENTORY_2026-11-04.json).

Đã lưu 12 đầu nhánh cũ thành annotated tag `archive/2026-10-23/<nhanh-cu>`
và xác minh SHA sau khi push, rồi bỏ 10 nhánh remote và 12 nhánh local.
[Registry tag phục hồi](BRANCH_ARCHIVES_2026-10-23.json) ghi đủ SHA, lý do và PR.
Các nhánh remote được xóa với lease theo SHA; thao tác push dùng atomic.

PR #10 (repo cũ) và
PR #11 (repo cũ) được đóng vì
head của cả hai là ancestor của candidate ở PR #13; ghi chú và thảo luận cũ giữ.
Không gọi đây là merged/native accepted. PR #13 và #17 giữ draft; `main`,
stable/Latest và 22 release với 40 asset không đổi ID/size/digest/trạng thái.
Không rewrite commit hoặc thay byte release asset. Tag phát hành cũ vẫn còn.

Để khôi phục nhánh, dùng tag tương ứng trong registry:

```powershell
git fetch origin --tags
git switch -c <nhanh-can-khoi-phuc> archive/2026-10-23/<nhanh-cu>
```

Git bundle trước bảo trì còn giữ đầy đủ refs local, gồm các checkpoint riêng;
bundle và bản sao hai local edits không được đẩy lên GitHub.

## Kiểm chứng

- Full suite đạt `75` nhóm, parse `164` script PowerShell với
  `-NoWindowsIntegration`; sáu nhóm integration được runner bỏ qua. Lượt sandbox
  đầu bị chặn tạo junction ở `Test-Security`; chạy lại nguyên suite với quyền
  thực thi phù hợp và TEMP/TMP trong project đã đạt, không sửa guard/runtime.
- Kiểm 150 file Markdown, 819 link local, không có link hỏng. 56 JSON bằng
  chứng lịch sử và 406 file nguồn không phải Markdown ngoài các thay đổi bảo
  trì cho phép giữ nguyên hash; hai local edits giữ byte và không stage.
- Khối xuất tài liệu thật của build tạo đủ README/hướng dẫn/ghi chú, đọc đúng
  note 2.20.88 và chuyển link note sang `THONG_BAO.md`. Gói 2.20.88 đã có tiếp
  tục qua `Verify-GitHubDistribution.ps1 -PackagePath`; không build lại.
- 12 file trong deferred snapshot/bản sao và patch khớp hash manifest riêng.
  Việc kiểm Markdown loại toàn bộ cây `_local` khỏi tập nguồn được sửa/kiểm link.
- Sau hồi quy, các thư mục test mới sinh được gom thêm ở các đợt
  `post-validation*`; manifest giữ metadata file và tên cây. Một thư mục con
  cập nhật mtime sau di chuyển, toàn bộ metadata file vẫn khớp; ghi riêng trong
  receipt thay vì bỏ qua khác biệt.
- Exact-head CI được theo dõi tại PR bảo trì; không coi CI của PR #17 hay
  commit gốc là CI của thay đổi sắp xếp này.

Các kiểm offline/CI này không thiết lập nghiệm thu Premiere import, playback,
timing, marker hoặc hiệu năng native. Tất cả giới hạn nghiệm thu trước đây giữ nguyên.

## Đối chiếu nhánh trước đợt dọn 2026-11-04

[BRANCH_INVENTORY_2026-11-04.json](BRANCH_INVENTORY_2026-11-04.json) ghi 80 nhánh từ xa (tên, SHA
đầu nhánh, ngày commit cuối, PR liên quan) và 34 tag tại thời điểm PR #89 được
merge vào `main` bằng merge commit `b89c9883`. Mọi đầu nhánh đều là tổ tiên của
`main`, nên có thể khôi phục bằng `git branch <tên> <sha>`. Bảng này được lưu
trước khi đóng các PR nháp xếp chồng và xóa nhánh.
