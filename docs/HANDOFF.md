# Bàn giao kỹ thuật Premiere Voice Sync

Ảnh chụp ngày 05/11/2026 cho Claude Code, viết lại ngày 13/11/2026 sau khi phát hành 2.20.90 và dọn các hướng đã đóng, cập nhật 14/11/2026 sau khi khởi tạo lại repo. Bắt đầu tại `F:\Tools\Premiere Voice Sync`, đọc [CLAUDE.md](../CLAUDE.md) (nạp [AGENTS.md](../AGENTS.md)), rồi đọc tài liệu này. [Maintainer briefing](MAINTAINER_BRIEFING.md) có bản đồ chi tiết hơn.

## Git, bản phát hành và bản cài

| Hạng mục | Trạng thái đã đối chiếu |
| --- | --- |
| Checkout | `F:\Tools\Premiere Voice Sync`, nhánh mặc định `main`. Ngày 13/11 (repo cũ): PR #98 (gỡ Qwen), #99 (dữ liệu dev có thể xóa), #100 (Whisper large-v3-turbo là model duy nhất), #101 (release 2.20.90), #102 (ghi bản cài) đã merge; sau đó là đợt dọn cue-first/nghiên cứu ASR. Repo mới 14/11: #2 (Dependabot, template issue/PR) và #3 (Dependabot nâng `actions/checkout`) đã merge. `main` có thay đổi panel (bỏ hook cue-first) chưa nằm trong bản nào; bản kế 2.20.91 là bản public đầu tiên. |
| Nhánh cũ | Các nhánh/PR Codex cũ (repo cũ) có tip trong [inventory](maintenance/BRANCH_INVENTORY_2026-11-04.json). Nhánh mới dùng tiền tố `claude/`. |
| Release trên GitHub | Repo được khởi tạo lại ngày 14/11/2026 bằng một commit snapshot ([lý do](maintenance/REPO_RESTART_2026-11-14.md)) và chưa có release; bản đầu tiên phát hành sau. Trong lịch sử cũ (đã lưu trữ ngoài GitHub, SHA dưới đây không có trong repo này): stable Latest v2.20.25; prerelease v2.20.90 công bố 13/11, tag tại `3e2faff06332ac7ee78c9bb2d7b033689020e049`, ZIP 1.535.356.630 byte, SHA-256 `CE627B55113CAE2B815E37C0EE90E85C6D4F0DA68EAE1B1C45BE650F0E7C86F5` (Whisper large-v3-turbo); trước đó v2.20.89 tại `7e682ae4ce9a281f36bf1bb95f22ef4c76ba6837` (Small) và v2.20.88 tại `0802eb62b39522084cf22ae6c686e7f95139151d`. Mã không kèm license mã nguồn mở (bảo lưu mọi quyền), thành phần bên thứ ba liệt kê ở [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md). |
| Bản trên máy | 13/11 user duyệt cài 2.20.90 bằng `dist/Install-Verified-2.20.90-20261113.ps1`; panel 2.20.89 sao lưu ở `dist/_install-2.20.90-20261113T092930Z/previous-panel`. Kết quả `verified.json`: 73 file panel đúng hash, 6.317 file dữ liệu người dùng, registry CEP và source không đổi; runtime chỉ có `ggml-large-v3-turbo.bin`, `Assert-PvsRuntimeLock` đạt. Chưa mở Premiere; nghiệm thu native pending. Các bản cài/rollback trước (2.20.89, 2.20.88, script `dist/Restore-Verified-2.20.0-20261103.ps1`) vẫn giữ trong `dist/`, chỉ chạy theo quyết định riêng của user. |

Từ 13/11/2026 các cây `.tmp*` và `_local/` (kể cả `_local/archive`) là dữ liệu dev có thể xóa: chỉ xóa theo danh sách user xác nhận, sau khi kiểm không có tiến trình hay phiên nào đang dùng, và không đi xuyên junction/symlink. Giữ backup trong `dist/`, runtime đã cài và dữ liệu người dùng.

## Sản phẩm và điểm vào

Panel CEP cho Adobe Premiere Pro trên Windows, ưu tiên SRT tiếng Việt. **Dựng theo voice** căn lời mới với SRT và dựng hình, âm gốc và voice từ template, theo các pha cắt/giữ khoảng, retime, caption và marker. **Chỉ tạo subtitle** dùng voice đã chọn với SRT tham chiếu tùy chọn, giữ hình/âm thanh của bản dựng. Có SRT thì bảo toàn chữ cue khớp, chèn lời thực sự phát sinh bằng ASR và đánh dấu ca khó.

| Thành phần | Điểm vào và trách nhiệm |
| --- | --- |
| Panel CEP | `extension/CSXS/manifest.xml` → `extension/index.html`, `extension/js/main.js`. Hai nút nối `runSync` và `runCaptions`. JS quản lý form, `localStorage`, job, thông báo, pause/cancel và recovery journal. |
| Premiere host | `extension/jsx/host.jsx` qua `evalScript`. ExtendScript ES3 đọc timeline, xuất WAV, thực thi edit, nhập SRT, đặt marker và đọc lại. `caption-input.js` dùng chung với host. `diagnostic-executor.jsx` sinh từ nguồn bằng `tools/Build-DiagnosticExecutor.js`. |
| Engine | `extension/engine/run-workflow.ps1` giám sát worker bằng Windows Job Object. Auto edit đi từ `run-alignment.ps1` qua sentence/DTW/speed-merge plans, caption-only dùng `run-captions.ps1`. `engine/lib/` giữ matching chung, cache, timing, chính sách dựng và bảo mật. |
| Runtime và phân phối | `engine-config.json` dùng Whisper large-v3-turbo, model duy nhất từ 2.20.90 (`Security.ps1:Get-PvsRuntimeModelProfile`). Các lock engine khóa whisper.cpp, FFmpeg, model và CUDA bằng hash. `extension/native/` là helper C# cho thông báo. `installer/` build ZIP theo allowlist và quản lý cài/gỡ/rollback. Dữ liệu job/log/cache/model/backend nằm dưới `%LOCALAPPDATA%\PremiereVoiceSync`. |
| Kiểm thử | `tests/unit/` (nhóm `Test-*.ps1` và mock Node), `tests/helpers/`, `tests/manual/` cho media/Premiere thật. `tools/` là công cụ dev. |

Xem [kiến trúc](ARCHITECTURE.md), [cấu trúc repo](PROJECT_LAYOUT.md) và [hướng dẫn test](TESTING.md) khi cần lần đường gọi.

## Hướng phát triển hiện hành (quyết định của user, 13/11/2026)

- Big update xây từng bước trên engine và panel 2.20.x, ra từng bản nhỏ; lỗi sửa trong lúc dùng. Từ 14/11/2026 mỗi lần commit, push, mở hay merge PR, build gói, công bố prerelease và cài đều hỏi user trước.
- 2.20.89: caption giữ đúng mốc đã căn, không nới 5 frame. [Ghi chú](releases/notes/SUBTITLE_TIMING_2.20.89.md). Native pending.
- 2.20.90: Whisper large-v3-turbo thay Small, là model duy nhất. Replay Nam Cực giữ 254/255 câu SRT (cue 138 chuyển sửa tay); CPU chậm hơn Small khoảng 2 lần. [Ghi chú](releases/notes/ASR_TURBO_2.20.90.md). Native pending.
- Đã đóng: nghiên cứu cue-first (S0–S10), chọn model ASR, Qwen, sequence kết quả riêng (Q5). Mã, test và báo cáo đã gỡ; lý do và phần còn giá trị ghi ở [bộ nhớ hồi quy](REGRESSION_MEMORY.md). Không đề xuất lại các hướng này.
- Auto edit tiếp tục sửa trên sequence template đang mở như 2.20.x.

## Việc còn lại (14/11/2026)

- Trước bản 2.20.91 (bản public đầu): gói mới chỉ có link GPL v3 của FFmpeg trong [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md), cần kèm toàn văn license; chạy kiểm phát hành trước khi gắn tag.
- Ruleset `Protect main` chưa bắt CI xanh; bật sau khi workflow lọc thay đổi ở cấp job, để PR chỉ sửa tài liệu không bị treo.
- Test để lại các thư mục `.tmp-*-tests` ở root (đã gitignore); chỉ xoá theo danh sách user xác nhận.

## Bài học còn áp dụng

- Ghi caption trực tiếp vào track chưa từng được chứng minh trên Premiere; đường đang dùng là tạo SRT rồi import. Năng lực native mới phải qua [chính sách khả thi](DEVELOPMENT_FEASIBILITY_POLICY.md) trước khi làm feature.
- ExtendScript có khác biệt parser so với V8 và có thể đọc file không BOM như ANSI. Dùng ES3 và `File.encoding = "UTF-8"` khi đọc. `captionTracks`/Start thiếu là unknown. PowerShell StrictMode cần kiểm `$null` trước `.Count`. Dùng generator và kiểm parity cho executor.
- Đóng gói và phát hành: installer có đường dẫn tiếng Việt cần UTF-8 BOM, kiểm ZIP phải chuẩn hóa `\` thành `/`, mỗi lần phát hành phải tăng mọi chuỗi version nhúng. Không viết lại receipt lịch sử.
- Đánh giá ASR: WER tổng có thể che hồi quy của toàn engine. Kiểm toàn bộ caption cuối (cue giữ lại, outro/CTA, số, nhãn một chữ cái), không chỉ số đo.
- CEP production chưa ký, dùng PlayerDebugMode và có Node filesystem/process access. Allowlist, hash, traversal/link guards và rollback giảm rủi ro gói cài, còn TOCTOU, binary bên thứ ba và dữ liệu dưới cùng tài khoản. Kiểm SHA-256 toàn ZIP qua kênh tin cậy trước cài. [Bảo mật](SECURITY.md)
- CI Windows trên runner: `fs.cpSync` của Node lỗi với đích có dấu tiếng Việt, và TEMP là đường dẫn 8.3 (`RUNNER~1`). Test so đường dẫn phải chuẩn hóa bằng `GetFullPath`.

## Lệnh

Chạy tại root bằng Windows PowerShell. Máy có Windows PowerShell 5.1 và Node cho test dev. Panel chạy bằng CEP và engine đã pin. Repo không có bước npm install, linter, typecheck hay dead-code check cấu hình sẵn.

| Việc | Lệnh hoặc điểm vào |
| --- | --- |
| Nhập phụ thuộc runtime | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/setup-engine.ps1 -ArtifactsRoot <folder>` với artifact đã duyệt khớp lock. |
| Build và chạy | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File installer/build-release.ps1`. Bản đã cài mở từ **Window > Extensions (Legacy) > Premiere Voice Sync**. Cài/gỡ qua `Setup-Panel.cmd` / `Remove-Panel.cmd` của gói đã xác minh. |
| Hồi quy | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1 -NoWindowsIntegration`; dùng TEMP/TMP trong `_local/` khi sandbox chặn temp hệ thống. |
| Syntax và mô phỏng JS | `node --check extension/js/main.js`, `node --check extension/js/security.js`, `node tests/unit/speed-merge-host.js`, `node tools/Build-DiagnosticExecutor.js --check`. |
| Metadata | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Verify-GitHubDistribution.ps1`. |

Sáu nhóm bỏ qua bởi `-NoWindowsIntegration` gồm `Test-InstallerLifecycle.ps1`, `Test-InstallRollback.ps1`, `Test-PanelRegistry.ps1`, `Test-NotificationShortcut.ps1`, `Test-NativeNotifications.ps1`, `Test-IncidentNotifications.ps1`. CI chạy trên mọi pull request: job `changes` xem PR có đổi code không; PR chỉ đổi Markdown/`docs/` (trừ `docs/releases/*.json`) thì job `regression-tests` được bỏ qua (GitHub tính là đạt). Native import/playback/timing/marker và hành vi lúc dừng cần kiểm riêng trên Premiere với user.

## Quyết định cần giữ

- Chọn file SRT và import SRT nội bộ. Gộp hình là lựa chọn riêng, tối đa hai cue liền kề.
- Phân biệt định danh chữ, thẩm quyền timing và thẩm quyền bỏ lời/cắt. Khoảng trống cue chưa đủ chứng minh im lặng. Timing ước lượng giữ provenance và không được nâng lên verified DTW. Ca khó chuyển review theo [chính sách ASR](ASR_ACCEPTANCE_POLICY.md).
- Giữ Pause/Resume, default khoảng không lời 0,5 giây và giá trị user đã lưu. Dùng lại UI hiện có. Chỉ phát thông báo khi cần chú ý/quyết định. Âm thanh thông báo do user bật/tắt (`pvs.notificationSound`, mặc định bật).
- Mỗi lượt native cần quyền mới, có giới hạn, do user cấp. Giữ project, jobs, models, cache, backups. Tuyệt đối tránh điều khiển Save/Undo hoặc ép đóng Premiere/helpers.
- Việc ngoài kế hoạch không cần user duyệt trước nếu phục vụ việc đang làm, nhưng phải ghi rõ trong báo cáo. Mỗi bug fix cần lần cả luồng liên quan, shared/fallback, thêm reproducer và cập nhật [REGRESSION_MEMORY.md](REGRESSION_MEMORY.md).
- Cách user làm việc: khi user báo lỗi kèm ví dụ đại diện, xem bằng chứng toàn lượt chạy thay vì đòi danh sách lỗi đầy đủ. Với thay đổi UX hoặc an toàn, trình kế hoạch có phạm vi trước và chờ duyệt. Bản sửa runtime đã duyệt đi theo quy trình đóng gói/cài đã xác minh, chỉ cài khi user đồng ý và đã tự đóng Premiere/helpers. Không hứa hết lỗi trên mọi trường hợp.
- Trả lời bằng tiếng Việt. Claude Code là công cụ phát triển chính, Codex là lượt review bổ sung khi được yêu cầu.
