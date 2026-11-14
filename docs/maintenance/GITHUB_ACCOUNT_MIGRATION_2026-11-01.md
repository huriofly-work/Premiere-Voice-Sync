# Chuyển tài khoản GitHub ngày 01/11/2026

Repo hiện hành là [huriofly-work/Premiere-Voice-Sync](https://github.com/huriofly-work/Premiere-Voice-Sync).
GitHub xác nhận tài khoản `huriofly-work`, ID `298105426`, có quyền đọc, ghi
và quản trị repo private này.

## Cấu hình Git trên máy

Các giá trị sau được đặt trong cấu hình local dùng chung của repo, áp dụng
cho cả checkout chính và worktree cue-first đã đăng ký:

```text
remote.origin.url=https://github.com/huriofly-work/Premiere-Voice-Sync.git
user.name=huriofly-work
user.email=298105426+huriofly-work@users.noreply.github.com
credential.https://github.com.username=huriofly-work
```

GitHub CLI chọn `huriofly-work` làm tài khoản active. Khi cấu hình máy mới,
đăng nhập tài khoản này trước rồi đặt remote và danh tính commit:

```powershell
gh auth login --hostname github.com --git-protocol https --web
git remote set-url origin https://github.com/huriofly-work/Premiere-Voice-Sync.git
git config --local user.name huriofly-work
git config --local user.email 298105426+huriofly-work@users.noreply.github.com
git config --local credential.https://github.com.username huriofly-work
```

Kiểm bằng `gh api user`, `gh api repos/huriofly-work/Premiere-Voice-Sync`,
`git var GIT_AUTHOR_IDENT`, `git ls-remote origin HEAD` và `git fetch origin`.
Trên máy Windows này, đọc keyring cần chạy ngoài sandbox; thông báo token
không hợp lệ chỉ xuất hiện trong sandbox chưa đủ để kết luận phải đăng nhập lại.

## Tài liệu và bằng chứng

Các liên kết GitHub trong tài liệu Markdown được chuyển sang owner hiện hành.
Workflow CI không chứa owner cũ, tiếp tục checkout repo của sự kiện GitHub.
JSON inventory/receipt lịch sử giữ nguyên byte và tên chủ sở hữu tại thời điểm
thu thập, theo [quy định bằng chứng](../history/README.md). Commit cũ, tag và
release asset không được viết lại do đổi tài khoản.

Kết nối GitHub tích hợp trong ứng dụng có phiên OAuth riêng với GitHub CLI.
Sau khi chuyển tài khoản, người dùng cần kết nối tài khoản mới và cấp quyền
repo cho tích hợp đó; không dùng kết quả `gh auth status` để khẳng định phiên
tích hợp đã đổi tài khoản.

## Kiểm chứng

- Remote và danh tính commit của hai worktree đều dùng tài khoản mới;
  `git fetch origin` thành công, GitHub API xác nhận quyền ghi/quản trị.
- Đã đổi 21 URL trong 10 file Markdown. Rà hai liên kết ghim commit cũ:
  liên kết audit đã đúng, liên kết kế hoạch dùng nhầm đường dẫn sau di chuyển.
  Đã khôi phục đường dẫn `docs/BIG_UPDATE_CUE_FIRST_PLAN_2026-10-22.md`
  tồn tại tại commit `f45e0aa`, giữ nguyên commit tham chiếu.
- Kiểm các liên kết GitHub qua API có xác thực và các đích liên kết local;
  kết quả cuối cùng được ghi trong PR. Không cần chạy test runtime cho thay
  đổi URL/cấu hình này; CI của PR vẫn chạy theo workflow hiện hành.
- Hai chỉnh sửa có sẵn trong `AGENTS.md` và `tools/Build-AsrBlindReview.py`
  giữ nguyên SHA-256 và không nằm trong commit chuyển tài khoản.

Đây là thay đổi cấu hình và liên kết tài liệu. Không thay runtime/bộ cài hay
trạng thái nghiệm thu Premiere import, playback, timing hoặc marker.
