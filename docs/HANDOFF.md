# Bàn giao kỹ thuật Premiere Voice Sync

Ảnh chụp ngày 05/11/2026 cho Claude Code, viết lại ngày 13/11/2026 sau khi phát hành 2.20.90 và dọn các hướng đã đóng, cập nhật 14/11/2026 sau khi khởi tạo lại repo, 16/11/2026 khi chuẩn bị 2.20.92, 18/11/2026 khi chuẩn bị 2.20.93, 2.20.94, 2.20.95, 2.20.96 và 2.20.97. Bắt đầu tại `F:\Tools\Premiere Voice Sync`, đọc [CLAUDE.md](../CLAUDE.md) (nạp [AGENTS.md](../AGENTS.md)), rồi đọc tài liệu này. [Maintainer briefing](MAINTAINER_BRIEFING.md) có bản đồ chi tiết hơn.

## Git, bản phát hành và bản cài

| Hạng mục | Trạng thái đã đối chiếu |
| --- | --- |
| Checkout | `F:\Tools\Premiere Voice Sync`, nhánh mặc định `main`. Ngày 13/11 (repo cũ): PR #98 (gỡ Qwen), #99 (dữ liệu dev có thể xóa), #100 (Whisper large-v3-turbo là model duy nhất), #101 (release 2.20.90), #102 (ghi bản cài) đã merge; sau đó là đợt dọn cue-first/nghiên cứu ASR. Repo mới 14/11: #2 (Dependabot, template issue/PR) và #3 (Dependabot nâng `actions/checkout`) đã merge. Đợt 15/11: PR #21–#39 merge, phát hành v2.20.91 (bản public đầu tiên). Đợt 16/11: #43 (sửa lỗi lập kế hoạch), #45 (số đo timeline), #46 (phát hành 2.20.92) merge. Đợt 16–18/11: #48 (bỏ chia đợt), #50 (đo lệnh marker, script thử), #52 (sắp xếp clip), #54 (dời marker), #56 (ghi marker trước khi cắt) merge; #57 phát hành 2.20.93. Đợt 18/11: #60, #61, #64, #65 (marker) merge; #66 phát hành 2.20.94; #68 (sửa thứ tự ghi marker) merge; PR chuẩn bị 2.20.95. |
| Nhánh cũ | Các nhánh/PR Codex cũ (repo cũ) có tip trong [inventory](maintenance/BRANCH_INVENTORY_2026-11-04.json). Từ 16/11/2026 nhánh mới đặt tiền tố theo loại việc (`fix/`, `perf/`, `release/`). |
| Release trên GitHub | Repo được khởi tạo lại ngày 14/11/2026 bằng một commit snapshot ([lý do](maintenance/REPO_RESTART_2026-11-14.md)) Release đầu tiên: **v2.20.91 stable/Latest** (công bố 15/11 dạng prerelease, user nâng stable cùng ngày sau khi chạy thật không thấy lỗi), tag tại `8df2aca2c27b76913898daf54461841a78e38dc1`, ZIP 1.535.368.451 byte, SHA-256 `2C9F66FBFAB9864BA6757A53C254387C13B396CD7006279495BA0F80FA71CEDE`. **v2.20.92** prerelease (`--latest=false`) công bố 16/11, tag tại `552bb757ff1d015b8ccc2aedf16566a25e09d693`, ZIP 1.535.369.790 byte, SHA-256 `877EB8B7837F75AC82BE8CEA2466CED441C373322F8D9406F860DDA8D650BF64`. **v2.20.93** prerelease (`--latest=false`) công bố 18/11, tag tại `4b9141cec1656e5d2ed9f00cf0deb1b2583a253f`, ZIP 1.535.380.089 byte, SHA-256 `1B76093D69140245F17C37FA61CB039ED679E32FB48546D37F58969C8CCB5E0D`. **v2.20.94** prerelease công bố 18/11, tag tại `edebc544a201dc8c717eb159944ed731e0f09641`, ZIP 1.535.382.765 byte, SHA-256 `ABC66DAA3DD4C6B20639DD4BA1AFC74774B46D750C262D73F1598651EB514AA5` (lỗi dời marker, thay bằng 2.20.95). **v2.20.95** đang chuẩn bị dạng prerelease. Trong lịch sử cũ (đã lưu trữ ngoài GitHub, SHA dưới đây không có trong repo này): stable Latest v2.20.25; prerelease v2.20.90 công bố 13/11, tag tại `3e2faff06332ac7ee78c9bb2d7b033689020e049`, ZIP 1.535.356.630 byte, SHA-256 `CE627B55113CAE2B815E37C0EE90E85C6D4F0DA68EAE1B1C45BE650F0E7C86F5` (Whisper large-v3-turbo); trước đó v2.20.89 tại `7e682ae4ce9a281f36bf1bb95f22ef4c76ba6837` (Small) và v2.20.88 tại `0802eb62b39522084cf22ae6c686e7f95139151d`. Mã không kèm license mã nguồn mở (bảo lưu mọi quyền), thành phần bên thứ ba liệt kê ở [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md). |
| Bản trên máy | 16/11 user duyệt cài 2.20.92 bằng `dist/Install-Verified-2.20.92-20261116.ps1`; panel 2.20.91 sao lưu ở `dist/_install-2.20.92-20261116T155956Z/previous-panel`. `verified.json`: 66 file panel đúng hash, 6.297 file dữ liệu người dùng, registry CEP và source không đổi. User chạy lại project Sông Congo: qua bước lập kế hoạch, chạy hết các bước (timeline 85,5 s). Trước đó: 15/11 user duyệt cài 2.20.91 bằng `dist/Install-Verified-2.20.91-20261115.ps1`; panel 2.20.90 sao lưu ở `dist/_install-2.20.91-20261115T152003Z/previous-panel`. `verified.json`: 66 file panel đúng hash, 6.252 file dữ liệu người dùng, registry CEP và source không đổi, không ghi registry. User chạy lại project Ếch trên Premiere 26.2.2: chưa phát hiện lỗi; job giữ lại cho thấy 6 marker review đều trên clip voice (0 fallback), 20 marker tốc độ V1, 0 lỗi marker. Trước đó: 13/11 user duyệt cài 2.20.90 bằng `dist/Install-Verified-2.20.90-20261113.ps1`; panel 2.20.89 sao lưu ở `dist/_install-2.20.90-20261113T092930Z/previous-panel`. Kết quả `verified.json`: 73 file panel đúng hash, 6.317 file dữ liệu người dùng, registry CEP và source không đổi; runtime chỉ có `ggml-large-v3-turbo.bin`, `Assert-PvsRuntimeLock` đạt. Chưa mở Premiere; nghiệm thu native pending. Các bản cài/rollback trước (2.20.89, 2.20.88, script `dist/Restore-Verified-2.20.0-20261103.ps1`) vẫn giữ trong `dist/`, chỉ chạy theo quyết định riêng của user. |

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
- Quyết định 15/11/2026 (issue #24): khôi phục nới mép caption tối đa 5 frame khi còn chỗ ở cả hai chức năng, không chồng caption; đảo quyết định 25/10 đã port vào 2.20.89. [Ghi chú 2.20.89](releases/notes/SUBTITLE_TIMING_2.20.89.md) giữ nguyên làm lịch sử. Native pending.
- 2.20.90: Whisper large-v3-turbo thay Small, là model duy nhất. Replay Nam Cực giữ 254/255 câu SRT (cue 138 chuyển sửa tay); CPU chậm hơn Small khoảng 2 lần. [Ghi chú](releases/notes/ASR_TURBO_2.20.90.md). Native pending.
- Đã đóng: nghiên cứu cue-first (S0–S10), chọn model ASR, Qwen, sequence kết quả riêng (Q5). Mã, test và báo cáo đã gỡ; lý do và phần còn giá trị ghi ở [bộ nhớ hồi quy](REGRESSION_MEMORY.md). Không đề xuất lại các hướng này.
- Auto edit tiếp tục sửa trên sequence template đang mở như 2.20.x.

## Đợt sửa sau lượt chạy "Ếch" (15/11/2026)

User chạy Auto edit 2.20.90 trên project thật và báo 21 lỗi. Đã merge vào `main`
(chưa phát hành, native pending): #23 thứ tự từ ổn định khi Whisper trả nhiều từ
cùng mốc (gốc của các cue sai chữ/đảo từ), #25 nới lại mép caption 5 frame, #27 lấy
lại chữ SRT khi máy nghe lệch đúng một từ gần giống (luật user duyệt, ghi ở
[ASR_ACCEPTANCE_POLICY](ASR_ACCEPTANCE_POLICY.md)), #29 marker một dòng ngắn
"Cue N: … – …", #31 marker tốc độ ngoài ngưỡng cho plan dựng hình theo cue, #33
giữ thư mục job của lượt chạy gần nhất mỗi workflow, #35 phép thử native marker
clip voice, #37 marker review gắn vào clip voice A2 và sửa vị trí marker clip khi
speed khác 100%. Replay offline project Ếch: câu SRT giữ nguyên văn 37/65 → 57/65,
marker review 17 → 6.

- Phép thử native #34/#37 trên Premiere 26.2.2: marker ghi lên ProjectItem voice
  hiện trên clip A2, đi theo clip khi kéo/trim và đặt được `marker.end` bằng số
  giây; in/out của TrackItem báo theo đơn vị đã chia speed. Chưa đo nest V1, speed
  khác 110%, reverse, time remap.
- Cách làm đợt này: Claude chia việc, giao Codex viết code qua
  `codex-companion.mjs task --prompt-file`, rồi Claude đọc diff, chạy lại suite và
  hỏi user trước mỗi commit/PR/merge. PR #37 có thêm một lượt review của Claude.
- Bài học quy trình: các PR #23–#37 quên cập nhật CHANGELOG trong cùng PR; đã bù ở
  PR chuẩn bị 2.20.91. Từ nay kiểm CHANGELOG trước mỗi commit đổi hành vi.
- Đã xong: phát hành v2.20.91, cài lên máy user, user chạy lại project Ếch không
  thấy lỗi và nâng 2.20.91 lên stable/Latest (15/11). Chưa đo: marker trên clip nest
  V1, tốc độ khác 110%, reverse/time remap; Setup/Remove trên tài khoản sạch và quét
  antivirus chưa ghi nhận.

## Đợt sửa sau lượt chạy "Sông Congo" (16/11/2026)

- Lượt Auto edit 16/11 16:42 (2.20.91, 135 câu SRT, 14 vùng sửa tay) dừng ở bước
  lập kế hoạch với `ACOUSTIC_PARTITION_SOURCE_BOUNDARY_CHANGED`, trước khi sửa
  timeline. Nguyên nhân: `ConvertFrom-Json` của PowerShell 5.1 trả số lẻ dạng
  decimal, bước tự kiểm tính điểm cắt bằng decimal còn bộ lập kế hoạch dùng double,
  lệch 1 frame ở điểm giữa đúng nửa frame. #43 (issue #42) sửa bước tự kiểm; replay
  ngoại tuyến job thật ra `SENTENCE_PLAN_READY`. Native pending.
- User thấy timeline "làm một khúc lại nghỉ". Đo log lượt 16/11 15:28 (100 s dựng):
  không có timer chờ; việc dựng chia đợt (tối đa 4 cặp speed / 20 vòng / 250 ms, có
  từ 2.20.87 sau sự cố treo 30 phút ở 2.20.86). Chi phí chuyển đợt ≈ 45 s (tự kiểm
  17 s, chụp timeline 9,5 s, Premiere xử lý ngoài script 18 s). Lệnh đơn dài nhất:
  cập nhật marker nguồn 9,4 s (2.20.90: 0,09 s). #45 (issue #44) chỉ thêm số đo vào
  `Performance_*.jsonl`. Việc kế: user chạy 2.20.92 để lấy số đo, rồi tối ưu trong
  issue riêng; nới giới hạn mỗi đợt hoặc chia ghi marker phải hỏi user trước vì
  đổi cơ chế an toàn.
- Bài học: CHANGELOG lại quên cập nhật trong #43/#45, bù ở PR chuẩn bị 2.20.92.
  Test chuỗi lệnh native không được khóa hash cứng: proxy mock thấy cả lượt đọc nội
  bộ của Node, Node 22 (CI) khác Node 26 (máy dev).
- Lượt 2.20.92 trên Sông Congo (16/11 23:02): timeline 85,4 s, 76 host call. Chuyển
  đợt ≈ 27 s; marker voice A2 25,2 s một lần (19 marker, 18 tạo/23 xóa); marker review
  22 cái ≈ 5 s; sắp xếp clip đọc `start.seconds` 34.316 lần (2,6 s).
- Quyết định user 16/11: **bỏ hẳn giới hạn chia đợt** của no-delay; lần treo 2.20.86 là
  native call không trả về, chia đợt không cứu được. Không đề xuất lại giới hạn này.
- Script thử marker 17/11 trên project thật (file voice, 37 marker, dọn sạch cả hai
  lượt): mỗi lệnh 7–25 ms khi 1 clip dùng file, 23–47 ms khi 101 clip; `marker.start`
  gán bằng số giây dời được marker, gán `Time` báo lỗi. Ước tính theo số lệnh chỉ
  khoảng 7 s so với 25 s thực tế; phần chênh chưa giải thích, chờ số đo 2.20.93.
- Đã merge cho 2.20.93: #48, #50, #52, #54, #56 (ghi marker voice/review trước khi cắt,
  bước sau dựng vẫn quyết định; lỗi hoặc Dừng thì trả marker về snapshot).
- 2.20.93 công bố 18/11 (prerelease, tag tại `4b9141c`, ZIP 1.535.380.089 byte, SHA-256
  `1B76093D…CB5E0D`), đã cài lên máy user. Lượt chạy Sông Congo 18/11 15:09: timeline
  64,5 s (34 host call, chi phí giữa call 8 s). Nhóm 19 marker tốn 25 s trước đây là marker
  clip hình V1 (không được ghi trước theo thiết kế), giờ 3,5 s nhờ tái sử dụng (#54), còn 19
  lần ghi lại `end` do so số thực tuyệt đối. Ghi trước khi cắt không ghi gì ở lượt này.
  Marker review 22 cái ghi sau dựng 8,7 s. File voice có marker review chồng qua các lần chạy
  (15 → 37 → 59); user xác nhận trùng.
- Quyết định user 18/11 về marker: thay bộ review cũ của cùng chức năng (#58, PR #60); mọi
  marker là điểm ở giữa đoạn (#59, PR #61); mỗi loại một marker cho mỗi đoạn trên một layer,
  khác loại đặt sát bên, marker voice giữa đoạn voice, marker SRT giữa đoạn cue (#62, PR #64);
  bỏ hẳn marker dự phòng trên thước, Tạo phụ đề chế độ trộn gắn vào track đầu tiên có clip
  (#63, PR #65). Bốn PR đã merge; #66 phát hành 2.20.94 (prerelease, tag tại `edebc54`,
  ZIP 1.535.382.765 byte, SHA-256 `ABC66DAA…EB514AA5`), đã cài lên máy user.
- Lượt 2.20.94 trên Sông Congo (18/11 20:13) **hỏng** ở bước dựng timeline sau khi đã cắt:
  mọi marker phải dời (19 clip hình, 21 review) kiểm lại sai, khôi phục không trọn vẹn, 43
  cảnh báo chưa gắn. User đóng project không lưu và mở lại bản đã lưu.
- Probe native `tools/probes/Probe-MarkerMoveEnd.jsx` (18/11, chỉ marker có tag, 59 → 59):
  gán `start` dời cả marker và giữ độ dài; gán `end` chỉ đổi điểm cuối; marker mới là điểm.
  Tool ghi `end` trước `start` khi dời về sau; mock coi hai mép độc lập nên test không bắt.
  Đường dời marker #54 chưa từng chạy native trước 2.20.94. Sửa ở #67/PR #68 (ghi `start`
  trước, đọc lại rồi mới ghi `end`; mock dùng chung `tests/unit/marker-bounds.js`); chuẩn
  bị bản vá 2.20.95. Bài học: năng lực native mới phải có probe đọc lại đủ các trường trước
  khi viết mock và phát hành.
- #69 phát hành 2.20.95 (prerelease, tag tại `f8622b3`, ZIP 1.535.382.608 byte, SHA-256
  `77C15577…7DB0DA32`), đã cài. Lượt chạy Sông Congo 18/11 21:38 **xong**: timeline 75,0 s
  (gồm đổi marker cũ một lần: clip hình 7,6 s, review 8,8 s), 0 cảnh báo chưa gắn, 0 lỗi;
  file voice 59 → 21 marker. User xem timeline và xác nhận marker đúng (nghiệm thu, một
  project); vẫn là prerelease.
- Việc kế: đo lượt chạy thứ hai (gần như không ghi marker); cân nhắc nâng 2.20.95 lên stable
  sau khi chạy thêm project khác. Còn mở: vì sao marker review không được ghi trước khi cắt (2.20.93, 2.20.94);
  Dừng khi bước cuối đang chạy sẽ trả marker về cũ; panel có thể mất câu lỗi gốc nếu cả
  khôi phục marker cũng lỗi; AGENTS.md dòng 47 về tiền tố tên branch cần sửa (chờ user duyệt).
- Điều tra ghi trước marker (#72): hậu kiểm review ở cả ba lượt báo `ownerIndex=-1` (tra
  `ownerByKey` trượt), mock báo 1. Probe chỉ đọc `Probe-StaleTrackItem.jsx` loại giả thuyết TrackItem
  cũ mất định danh (0/100 lệch); Premiere trả object mới mỗi lần đọc `clips[i]`, mock mô phỏng vẫn
  ghi trước bình thường. #73 thêm số đo chỉ trong executor có đo. Chuẩn bị 2.20.96 (bản chẩn đoán,
  không đổi hành vi) để user chạy Dựng theo voice một lần và đọc các trường `preKey`,
  `reviewOwners`, `sourceOwnerFound`, `ownerKnown`.
- Lượt 2.20.96 (18/11 23:42) chỉ ra nguyên nhân: khoá review `path`, khoá nguồn `node:000f42bc`.
  ExtendScript gộp biểu thức điều kiện lồng không ngoặc từ trái sang (phép thử native: `a ? "N" : b ? "P" : "E"`
  ra "P"). #76 sửa (hàm khoá chung `$._PVS._projectItemKey`, thêm ngoặc, test tĩnh). Chuẩn bị 2.20.97; việc kế:
  user chạy Dựng theo voice để thấy 21 marker review ghi trước khi cắt. Để sau: #75 (19 marker hình bị
  dời/ghi lại mỗi lượt, ~7,8 s).

## Việc còn lại (14/11/2026)

- Trước bản 2.20.91 (bản public đầu): toàn văn GPL v3 của FFmpeg đã nằm trong repo ở `licenses/GPL-3.0.txt` (tải một lần từ gnu.org ngày 14/11/2026, SHA-256 `3972dc97…6986`, test khóa hash) và có trong allowlist của gói; chưa build ZIP để xem file thật nằm trong gói. File LICENSE gốc của whisper.cpp v1.9.1 cũng đã đi kèm ở `licenses/whisper.cpp-LICENSE.txt` (SHA-256 `94f29bbe…010d`, test khóa hash). User quyết ngày 15/11/2026: **không** đính kèm mã nguồn FFmpeg vào GitHub Release, chỉ trỏ link ffmpeg.org/gyan.dev như trong `THIRD_PARTY_NOTICES.md`.
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

Sáu nhóm bỏ qua bởi `-NoWindowsIntegration` gồm `Test-InstallerLifecycle.ps1`, `Test-InstallRollback.ps1`, `Test-PanelRegistry.ps1`, `Test-NotificationShortcut.ps1`, `Test-NativeNotifications.ps1`, `Test-IncidentNotifications.ps1`. CI chạy trên mọi pull request: job `changes` xem PR có đổi code không; PR chỉ đổi Markdown/`docs/` (trừ `docs/releases/*.json`) thì job `regression-tests` được bỏ qua (GitHub tính là đạt). Từ 14/11/2026 ruleset `Protect main` bắt buộc hai check `changes` và `regression-tests` của GitHub Actions; đổi tên một trong hai job thì phải sửa ruleset cùng lúc, nếu không mọi PR bị chặn. Native import/playback/timing/marker và hành vi lúc dừng cần kiểm riêng trên Premiere với user.

## Quyết định cần giữ

- Chọn file SRT và import SRT nội bộ. Gộp hình là lựa chọn riêng, tối đa hai cue liền kề.
- Phân biệt định danh chữ, thẩm quyền timing và thẩm quyền bỏ lời/cắt. Khoảng trống cue chưa đủ chứng minh im lặng. Timing ước lượng giữ provenance và không được nâng lên verified DTW. Ca khó chuyển review theo [chính sách ASR](ASR_ACCEPTANCE_POLICY.md).
- Giữ Pause/Resume, default khoảng không lời 0,5 giây và giá trị user đã lưu. Dùng lại UI hiện có. Chỉ phát thông báo khi cần chú ý/quyết định. Âm thanh thông báo do user bật/tắt (`pvs.notificationSound`, mặc định bật).
- Mỗi lượt native cần quyền mới, có giới hạn, do user cấp. Giữ project, jobs, models, cache, backups. Tuyệt đối tránh điều khiển Save/Undo hoặc ép đóng Premiere/helpers.
- Việc ngoài kế hoạch không cần user duyệt trước nếu phục vụ việc đang làm, nhưng phải ghi rõ trong báo cáo. Mỗi bug fix cần lần cả luồng liên quan, shared/fallback, thêm reproducer và cập nhật [REGRESSION_MEMORY.md](REGRESSION_MEMORY.md).
- Cách user làm việc: khi user báo lỗi kèm ví dụ đại diện, xem bằng chứng toàn lượt chạy thay vì đòi danh sách lỗi đầy đủ. Với thay đổi UX hoặc an toàn, trình kế hoạch có phạm vi trước và chờ duyệt. Bản sửa runtime đã duyệt đi theo quy trình đóng gói/cài đã xác minh, chỉ cài khi user đồng ý và đã tự đóng Premiere/helpers. Không hứa hết lỗi trên mọi trường hợp.
- Trả lời bằng tiếng Việt. Chỉ dùng Codex (review hoặc viết code) khi user yêu cầu (quyết định 15/11/2026).
