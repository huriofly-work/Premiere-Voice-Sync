# Bộ nhớ hồi quy của project

## Thông báo bên thứ ba trong gói phát hành (13/11/2026)

Trước khi chuyển repo sang public, rà gói phát hành thấy ZIP chứa FFmpeg 8.1.2
`essentials_build` của gyan.dev (build `--enable-gpl --enable-version3`, tức
GPL v3), whisper.cpp/ggml v1.9.1 (MIT), SDL2 (zlib) và model large-v3-turbo
(MIT) nhưng không kèm thông báo giấy phép nào. 24 bản Release cũ (22 ZIP, 2
Setup.exe) đều thiếu.

- **Sửa.** Thêm `THIRD_PARTY_NOTICES.md` ở root repo; `build-release.ps1` chép
  nó vào gốc ZIP, `Get-PvsPackageFiles` đưa nó vào danh sách checksum bắt buộc.
  Asset cũ không ghi đè; ghi chú Release cũ được bổ sung link tới notices.
- **Invariant.** `Test-OpenSourceRelease` yêu cầu notices có trong allowlist,
  build phải chép nó, và mọi file runtime trong gói phải được nêu tên trong
  notices (thêm binary mới mà không cập nhật notices thì test fail), kèm link
  mã nguồn FFmpeg 8.1.2.
- **Chưa xong.** Gói chỉ kèm link toàn văn GPL v3, chưa kèm file giấy phép đầy
  đủ. Thay đổi tới tay người dùng ở bản phát hành sau; chưa build gói để kiểm.

## Dọn dẹp sau khi chốt large-v3-turbo (13/11/2026)

User chốt Whisper large-v3-turbo và yêu cầu bỏ mọi phần không còn theo hướng
hiện tại. Đã gỡ khỏi repo: `experiments/` (cue-first và bảy thí nghiệm cũ đã
promote hoặc bỏ), khoảng 100 test cue-first cùng helper/oracle/fixture, 13 tool
Python chọn model ASR, `docs/research/`, receipt `docs/history/CUE_FIRST_*` và
benchmark ASR/CTC (giữ `SRT_REGRESSION_2.20.7x`). Panel bỏ hook mượn giao diện
của cue-first (`PvsLegacyPanelView`, `captureAnalysisInput`, `productEnvironment`,
gate owner trong `evalRaw`), năm file `extension/ui/`, `big-update-lock.js`,
`product-installation.js`; installer bỏ payload `big-update/`, Node pin và tham
số `-ProductBetaNodeRoot`. Hai nút Dựng theo voice / Chỉ tạo subtitle vốn không
gọi các hook này.

- **Invariant.** Gói chỉ chứa runtime 2.20.x đã liệt kê; `Test-RepositoryLayout`
  chặn các đường cue-first quay lại. `Test-HostBootstrap` khóa `evalRaw` /
  `ensureHostLoaded` không còn tham số owner.
- **CI.** `Test-CueFirstCore` chiếm 915/1.212 giây của bộ hồi quy trên CI; bước
  self-test Python chỉ phục vụ nghiên cứu ASR. Workflow chỉ chạy trên pull
  request có đổi code (bỏ qua `*.md` và `docs/`, trừ `docs/releases/*.json`),
  hủy lượt cũ khi PR có push mới, không chạy lại trên `main` sau merge.
- **Bài học còn giá trị.** Ghi caption trực tiếp vào track (W0) chưa từng được
  chứng minh trên Premiere; đường đang dùng là tạo SRT rồi import. Mọi năng lực
  native mới vẫn phải qua [feasibility policy](DEVELOPMENT_FEASIBILITY_POLICY.md)
  trước khi làm feature.
- **Tra lại lịch sử.** Ghi chép đầy đủ S1–S8, M1, Q13–Q18, ASR/CTC và Qwen
  (142 mục) nằm trong lịch sử repo cũ (`docs/REGRESSION_MEMORY.md` tại commit
  `1d56546`, repo cũ), nay chỉ còn ở bản sao lưu ngoài GitHub
  ([khởi tạo lại repo](maintenance/REPO_RESTART_2026-11-14.md)).
- **Chưa kiểm native.** Gỡ hook cần một bản phát hành mới mới tới bản cài;
  replay/CI không chứng minh hành vi trên Premiere thật.

## Model nhận diện: Whisper Small → large-v3-turbo (13/11/2026)

User bỏ Qwen, chọn ở lại họ Whisper và đồng ý dùng large-v3-turbo làm model
duy nhất. Engine vốn đọc model từ `engine.json`; chỗ khóa cứng Small nằm ở
`Assert-PvsRuntimeLock`, danh sách đóng gói và đường runtime của cue-first.

- **Khả thi.** Weights `ggml-large-v3-turbo.bin` 1.624.555.275 byte, SHA-256
  `1fc70f77…e2bc69`, khớp LFS của `ggerganov/whisper.cpp` tại revision
  `5359861c`. whisper.cpp 1.9.1 đã chạy checkpoint này với preset DTW
  `large.v3.turbo` trên CUDA (các replay 2.20.75–2.20.77) và CPU. Đo CPU-only trên
  i7-14700K, đoạn 26,5 s, đủ cờ DTW/SOW của engine: Small 8,7 s, Turbo 18,1 s.
- **Một model, không tự đổi model.** CPU fallback dùng cùng Turbo; không giữ Small
  làm đường lui tự động vì job/retry/cache sẽ đổi model giữa chừng. Cache key đã
  có hash model nên cache Small cũ không bị dùng lại. Gói ZIP chỉ chứa Turbo
  (khoảng 1,63 GB, dưới giới hạn asset 2 GiB của GitHub); model Small cũ trong
  `%LOCALAPPDATA%` là dữ liệu user, không xóa.
- **Invariant.** `Security.ps1:Get-PvsRuntimeModelProfile` (code đã review, không
  phải config) đặt id/path model. Lock phải pin đúng một file `models\` và đó phải
  là Turbo (`SECURITY_RUNTIME_MODEL_LOCK`); config phải trùng id/path, phân biệt
  hoa/thường (`SECURITY_RUNTIME_CONFIG_CHANGED`). Runtime Small khóa đủ hash vẫn
  bị từ chối, tránh lặng lẽ quay về model cũ.
- **Cue-first.** Đường đọc runtime sản phẩm (bootstrap, primary recognition,
  observer retry, lifecycle, CEP trial) đổi sang `large.v3.turbo`; bản ghi bằng
  chứng S8 lịch sử (`evaluation/*`, README) giữ Small. Kiểm tên raw
  `ggml-<model>.bin` đổi dấu chấm của preset thành gạch nối.
- **Test.** `Test-RuntimeModelLock.ps1` (mới): profile/config/lock là Turbo với
  hash upstream, DTW dùng `-dtw large.v3.turbo -nfa`, từ chối lock Small, config
  Small, lock hai model, sai preset, sai hoa/thường. `Test-OpenSourceRelease`
  copy Turbo và không mang Small còn sót trong runtime dev. Fixture cue-first
  đổi sang Turbo.
- **Sửa sau review.** (1) Cache probe CUDA (`Get-BackendFingerprint`) trước chỉ
  khóa theo GPU/driver/binary; máy đã qua probe với Small sẽ dùng lại kết quả đó
  cho Turbo mà không nạp thử model lớn hơn. Fingerprint giờ gồm tên và kích
  thước file model; `Test-BackendCooldown` báo `CUDA_PROBE_CACHE_IGNORES_MODEL`
  trên code cũ. (2) `primary-recognition.js` của cue-first từ chối file trên
  1 GiB khi pin runtime, nên weights 1,62 GB không chạy được; nâng lên 4 GiB như
  `tail-live.js`. (3) Kiểm "đúng một model" chuẩn hóa `/` thành `\`.
- **Replay toàn engine (commit `d9c8924`).** Audio Nam Cực dựng lại 766,5 s
  (SHA-256 `77e61450…`), SRT 255 cue (`82dd6df2…`), CUDA, cache private mixed.
  `Verify-CaptionReplay.py` kiểm chuỗi SRT ở caption cuối và lời outro 77 token:

  | Model | Giữ SRT | Cue chưa giữ | Caption | Vùng timing ước lượng | Lỗi outro |
  |---|---:|---|---:|---:|---:|
  | large-v3-turbo | 254/255 | 138 | 467 | 0 | 3/77 |
  | Small (mốc so sánh) | 255/255 | – | 468 | 2 | 7/77 |

  Khớp số 2.20.77. Cue 138: Turbo nghe "nước hồ dầu sắc" (điểm khớp 0,6875 dưới
  ngưỡng 0,7), nên caption cuối hiện chữ ASR thay "giàu sắt" và cue nằm trong
  `unresolvedReferenceCueIndices` để sửa tay. Không hạ ngưỡng, không chép SRT
  khi chưa đủ bằng chứng (theo `ASR_ACCEPTANCE_POLICY`). Thời gian replay không
  dùng để so tốc độ vì cache mixed.
- **Còn để sau.** Mỗi entrypoint vẫn hash toàn bộ lock (giờ 1,6 GB model); probe
  CUDA vẫn chép model vào `%LOCALAPPDATA%\PremiereVoiceSync\Models`. CPU (mặc
  định trên máy chưa tải CUDA, và AMD/Intel) chậm hơn Small khoảng 2 lần; engine
  chưa đặt số luồng `-t` cho whisper.cpp.
- **Chưa chứng minh.** Nghiệm thu Premiere (import, phát, timing, marker, thời
  gian chạy thật cùng Premiere, VRAM) còn chờ. Ngôn ngữ ngoài tiếng Việt chưa đo.

## Gỡ toàn bộ nghiên cứu và đường dùng Qwen (13/11/2026)

User quyết định không dùng Qwen nữa. Panel và engine sản phẩm (`extension/`,
`installer/`) chưa từng gọi Qwen, nên hành vi bản cài không đổi.

- **Đã gỡ.** `experiments/asr-adapter/` (worker, session, panel job, replay,
  profile), sáu test Qwen (`Test-Qwen*.ps1`, `qwen_*_test.py`), các tool
  `QwenRecognitionAdapter.py`, `Probe-VietnameseCtcAlignment.py`,
  `Probe-WhisperTextAlignment.py`, `Score-PairedVietnameseStudy.py`, adapter
  cue-first `recorded-recognition-input.js` cùng test, thí nghiệm
  `evaluation/prepare-word-timing.py`, và tám báo cáo/benchmark riêng của Qwen.
- **Đã sửa để bỏ nhánh Qwen.** `Benchmark-HfRecognitionModels.py` chỉ nạp RNNT
  và từ chối model `qwen*`; `Prepare-VietnameseGoldStudy.py` chỉ giữ Turbo;
  corpus cue-first chỉ còn profile Turbo; `file-input.js`/`job-spec.js` từ chối
  `recognitionInput` (`RECOGNITION_INPUT_UNSUPPORTED`); hàm tách từ
  `lexical_words` chuyển vào `Score-WordBoundaryProvider.py`. CI bỏ các bước
  tự kiểm của tool đã gỡ.
- **Test.** Corpus, word timing, layout replay và reference terms cue-first đổi
  sang một model (6 lượt thay vì 12); test so cặp hai model bị bỏ vì không còn hai model; test provider sai giờ
  dùng provider attention của Qwen làm ca bị từ chối.
- **Giữ lại.** Hồ sơ lịch sử, release note và receipt có nhắc Qwen vẫn giữ;
  link tới file đã gỡ đổi thành chữ thường. File model Qwen trên đĩa (ngoài Git)
  chưa xóa; xóa cần user xác nhận riêng.

## 2.20.89: caption bỏ padding 5 frame ở mép (13/11/2026)

Big update chuyển sang xây trên bản 2.20.x thay vì chồng cue-first song song
(quyết định của user ngày 13/11). Phần đầu tiên port là quyết định S6 ngày
25/10: giữ timing caption đã căn, không padding.

- **Nguyên nhân.** `Add-PvsCaptionEdgePadding` nới tối đa 5 frame mỗi mép ở cả
  Auto edit (`build-sentence-plan.ps1`) lẫn Chỉ tạo subtitle
  (`New-PvsStandaloneCaptions`). Hàm cũng là nơi gỡ chồng lấn 1 frame giữa hai
  phần caption; với `PaddingFrames 0` nó thoát sớm nên bỏ qua bước gỡ đó.
- **Invariant.** Mặc định 0 frame (giới hạn 0–30 khi gọi tường minh). Hàm vẫn
  chạy hết với 0 frame: gỡ chồng lấn 1 frame, từ chối chồng lấn lớn hơn, không
  đổi mép hình/voice. Hai caller dùng mặc định, không còn truyền 5.
- **Test.** `Test-CaptionOnly` (mép 303/333 frame thay vì 300/338),
  `Test-CaptionVoiceAlignment` (mặc định giữ nguyên bốn caption; padding 5 chỉ
  khi gọi tường minh; planner giữ 2,1–3,1 s đúng word timing),
  `Test-CaptionDtwTiming` (mép quanh khoảng nghỉ 18/48 frame),
  `Test-MissingWordTimingRecovery` (gỡ chồng lấn 1 frame vẫn chạy).
- **Đã rà.** Chỉ có một hàm padding, hai caller nêu trên; JS/JSX không tự
  padding. Native Premiere chưa kiểm: thời gian hiện caption ngắn hơn bản
  trước khoảng 5 frame mỗi mép, khoảng trống giữa hai caption sát nhau có thể
  dễ thấy hơn. Nghiệm thu native pending.

## 2.20.88 — Tính chữ lặp và batch đổi speed không có việc

Native87 hoàn tất909477ms: alignment277035ms dù248 Whisperhit/0miss,
planner80099ms, timeline544299ms. Không suy mất cache từ thời gian lâu.
Planner Alien319cue gọi chuẩn hóa101095 lần trong lượt có instrumentation;
whole-cue proof lặp quét toàn reference. Dùng bảng đếm reference dựng một
lần cho mỗi batch kiểm, không nhận index từ JSON/plan hoặc lưu proof result;
normalizer có bộ nhớ process bounded và raw-text key. Không nới uniqueness,
DTW/quiet/chapter/frame, omission hoặc estimated-timing guards.

Cap4 cặp speed trước đây đếm cả đoạn skip. Tách work/scan, vẫn4 cặp native
nguyên tử và iteration/time cap, guard/snapshot/rebind/hậu kiểm như cũ.
[Batch](../tests/unit/Test-AcousticCutBatch.ps1) kiểm số phép chuẩn hóa tuyến
tính, single/batch parity và tamper; [lexical](../tests/unit/Test-LexicalReuse.ps1)
kiểm Unicode/số/chữ đổi/caller mutation/eviction/long text;
[native](../tests/unit/diagnostic-executor.test.js) tái hiện34 đợt speed dư
trên65đoạn trước sửa, giảm sau sửa, mọi profile vẫn tối đa4 cặp. Mock302đoạn:
speed152→52, tổng280→180 no-delay. Không suy thành số giây tiết kiệm native.
Rà cuối tái hiện StrictMode lỗi `.Count` khi caller truyền cut list `$null`;
duyệt theo mảng validity luôn có container, giữ kết quả nhóm rỗng như cũ.
Regression khóa cả null/empty proof và null cut list trước phát hành.

Rà Auto edit/caption-only, shared primary/recovery/supplement, manual/raw DTW,
legacy/DTW/speed planners, direct/staged baseline/fast/no-delay, stop/pause và
marker. Direct native statements không đổi. [Đo và giới hạn](releases/notes/AUTO_EDIT_ACOUSTIC_2.20.88.md)
ghi cặp planner66591→32938ms/CUDA alignment227682→121845ms, cùng cache
248Whisper/126quiet hit và0miss; toàn bộ JSON/SRT giống sau chuẩn hóa
createdAt/đường dẫn đo. Không dùng cặp CPU pilot khác cache để kết luận.
Đạt74 nhóm/152 PowerShell,22 suite trên đúng runtime trong gói;74 payload/
75 ZIP entry khớp hash/nguồn. Cài đặt chờ đóng Premiere thủ công; native
acceptance và số giây tiết kiệm thực tế trong Premiere còn pending.

## 2.20.87 — Native86 kẹt đổi tốc độ, Dừng phải chờ

Log86: no-delay bật batchLimitsDisabled; prepare273734ms, vài bước host9ms
nhưng wall112289ms; call7 đổi speed chưa trả về, panel gần30 phút. Không
modal khi quan sát, chưa biết native method nào kẹt. Chặn unbounded loop:
mọi profile có budget/cap, speed tối đa4 linked pair, no-delay20 iteration/
250ms và không artificial sleep. Giữ thứ tự/atomic pair/guard/hậu kiểm.
Tách payload native khỏi chứng cứ ASR; Alien3874932→889562 byte,12208→1212
object, geometry/voice/marker giữ tuyệt đối. Caption-only giữ snapshot và
review scope. Trace native trước/sau lookup/speed/move/razor, path trong job,
IO failure không fatal, panel không coi dòng cũ là tiến độ mới.

[Payload](../tests/unit/host-executor-input.test.js),
[native parity/cancel](../tests/unit/diagnostic-executor.test.js),
[caption](../tests/unit/caption-only-host.test.js) và
[UI](../tests/unit/performance-trial-ui.test.js) tái hiện unbounded trước sửa,
giới hạn4 cặp/hủy giữa cặp, full/compact đúng call/report, proof/source giữ,
omission/cue/frame/A2 guards, trace invalid/IO/stale/partial.72 nhóm/150 PS;
21 suite packaged. Rà direct/staged, mọi profile, Auto edit/caption-only,
pause/cancel/recovery/marker và DTW/speed. Native responsiveness/hết treo
còn pending; một lệnh native đơn lẻ bị kẹt vẫn không ngắt an toàn được.
[Chi tiết và giới hạn](releases/notes/AUTO_EDIT_ACOUSTIC_2.20.87.md).

## 2.20.86 — Khôi phục dựng hình theo cue SRT

Native85 thực sự chạy158 đoạn voice/695 caption/74 review marker; người dùng
vẫn báo thiếu cut/lệch hình. Lịch sử có helper per-cue chỉ gộp nguồn overlap,
nhưng production cũng có sentence grouping; không đồng nhất hai nhánh và
không khôi phục speed clamp cũ. Proxy và gate tám từ/silence đã buộc hình
chung mọi ranh giới A2, bỏ qua mép cue có timing thật. Thêm picture plan riêng
theo SRT/DTW thật, giữ đủ frame parent/A2/gap/đuôi; mở quiet cut bằng proof
DTW nguyên cue với guard85%/đầu-cuối exact hiện có. Không cấp omission hoặc
đổi estimated thành DTW. Speed merge giữ cue; expected retime chỉ chẩn đoán,
native speed sai/không đọc được vẫn có marker.

[Cue regression](../tests/unit/Test-CuePicturePlan.ps1),
[shipping planner](../tests/unit/Test-AutoEditAcousticPartitions.ps1) và
[native mock](../tests/unit/diagnostic-executor.test.js) kiểm cue không dấu
câu/voice liền, gap và full-frame/A2 conservation, proof/tamper, recovery
nguyên cue exact100% độc lập và negative số/thiếu/thừa/chapter/trim/duplicate.
71 nhóm/149 PS; Alien bốn stage:302 hình/234 voice/231 proof/68 picture-only,
286/319 SRT,695 caption, đủ hình/voice; sáu cue phục hồi đúng nguồn, chữ cell
khác nguyên vẹn.67 issue/62 vị trí review dự kiến, không phải lỗi đã nghe.
37 cell timing ước lượng vẫn pending. Island chuẩn/mismatch và ca27/199 đạt.
Rà normal/manual/legacy, DTW/speed, direct/staged, caption-only, omission,
fallback/trimmed và marker/package. Native timing/playback/marker còn pending.
Mép từ trùng đúng đuôi voice không có frame phía sau: regression tái hiện
`CAPTION_OUTSIDE_VOICE_COVERAGE`, sau sửa giữ nhóm hiện có và chạy tiếp;
không biến một refinement không khả dụng thành lỗi dừng tác vụ.
[Chi tiết/lịch sử/giới hạn](releases/notes/AUTO_EDIT_ACOUSTIC_2.20.86.md).

## 2.20.85 — Khối review dài làm ít điểm cắt và lệch hình/voice

Log native84 vẫn 19 nhóm/695 caption. Resolver dùng recognition thô để tạo
56 proxy, planner cấm mọi mép bên trong proxy; luồng DTW đã chạy nhưng loại
toàn bộ từ thuộc proxy. Sửa marker84 không chữa nguyên nhân đồng bộ này.
Thêm quyền phân hoạch độc lập: hai ngữ cảnh bốn từ duy nhất trong SRT và
raw DTW, liền nhau/cùng chapter, tám timing DTW thật và frame có khoảng
bảo vệ trong silence đã đo. Không cấp omission, không coi proxy/text/ước
lượng là quyền cắt. Caption giữ identity/cell, dùng toàn bộ voice map, thử
DTW cục bộ; chỉ các phần còn ước lượng tạo timing review. Speed merge giữ
mốc đồng bộ trong một frame. Retry thất bại vẫn là chẩn đoán; review lấy
theo chất lượng cell cuối, không đánh dấu lại phần đã phục hồi.

[Regression](../tests/unit/Test-AutoEditAcousticPartitions.ps1) tái hiện
1 khối trước capability/4 nhóm sau; kiểm ambiguity, extra speech, estimated,
overlap, bounds/chapter/inPoint/fps, caption retry, IO fatal và tamper.
[Speed merge](../tests/unit/Test-SpeedMergeTrial.ps1) kiểm drift/reject và
merge vẫn giữ mốc; [marker](../tests/unit/review-markers.test.js) chỉ còn
phần chưa đo được. Đạt 70 nhóm/148 PS; Alien bốn stage: 155 mốc/158 nhóm,
231/268 cell DTW, 695 caption cùng chữ84, đủ frame nguồn/voice, không omission.
79 review issue/74 vị trí dự kiến, 25 vùng timing trong17 khối, 36 vùng chữ,
4 DTW ngoài proxy và14 gap; không diễn giải thành số lỗi thực.
Island chuẩn/mismatch và ca27/199 giữ chữ/frame, không phục hồi SRT giả103.
Rà direct/diagnostic, legacy/additive-DTW/speed, caption-only, omission,
fallback/trimmed và allowlist package. Native import/playback/timing/marker
còn pending. [Chi tiết và giới hạn](releases/notes/AUTO_EDIT_ACOUSTIC_2.20.85.md).

## 2.20.84 — Manual proxy bị hiểu nhầm thành hàng trăm lỗi nhận diện

Log native Alien 695 caption/620 review marker; replay tái hiện 1.816 issue
trên 620 vị trí. 598 caption thuộc 56 manual proxy confidence=0/no-word-time
bị nhân cảnh báo DTW/low-confidence/manual. Planner thêm 11 marker A2 từ
confidence tổng hợp. Giữ proxy safety, đổi presentation: một timing region
cho mỗi block, chữ ASR theo cell cuối; tách completion timing với text pending.
Cell trùng đủ một câu SRT giữ lại chữ hoa/dấu câu, lưu raw, không nhận số,
thiếu/thừa/mơ hồ hoặc cấp thêm word timing/cut/omission.

[Marker](../tests/unit/review-markers.test.js) fail runtime 83/pass sau,
400 caption→2 issue, reconciliation 620 owned→2 giữ marker tay/scope khác;
[manual](../tests/unit/Test-AutoEditManualReview.ps1) giữ lexical/omission/
timing guards và cảnh báo confidence thật. Đạt 69 nhóm/146 PS. Alien replay
166 hit/0 miss: 695 caption, 280/319 SRT/39 pending, 114 issue→111 marker
dự kiến; giữ 56 timing/36 text/4 DTW/18 gap và toàn bộ segment frame.
Rà legacy/DTW/speed, direct/diagnostic, caption-only và reconciliation;
không thao tác Premiere/Save/Undo. Native còn pending.
[Phạm vi và kiểm chứng](releases/notes/REVIEW_MARKERS_2.20.84.md).

## 2.20.83 — Nhận diện khó không hủy tác vụ

Người dùng đổi chính sách: lỗi model chưa nhận đúng phải báo review và
tiếp tục. Giữ khối nguồn/voice đã xác định, kể cả dài hơn giới hạn retry 30 giây;
không cắt bên trong, không omission hoặc nâng DTW. Chưa gán được phạm vi
thì giữ template và hoàn tất phân tích có vị trí cần sửa tay, không gọi
executor hoặc nói đã dựng xong. Planner giữ toàn bộ mép chapter trong job review.
Caption-only retry mép chưa đạt giữ primary; vùng chưa được phủ có review.
Kết quả rỗng không import caption giả. Allowlist model-quality riêng, IO/
runtime/cancel không bị biến thành thành công. Rà primary/CPU fallback/
retry/supplement, legacy/DTW/speed và marker.

Alien offline đã qua đủ bốn entrypoint:319 → 695 caption,276 cue SRT giữ
nguyên/43 pending;56 khối review,4 khối dài. Kiểm từng cell chữ, toàn bộ frame
hình và voice, không omission mới. SRT/MP3 giữ hash; geometry dựa snapshot
lịch sử sau khi project được người dùng lưu lại, không native acceptance.
[Phạm vi/tests](releases/notes/EDITED_VOICE_2.20.83.md): 69 nhóm/146 PS, 20 bộ Node trong
gói, 73 payload/74 ZIP entry khớp nguồn. Cài 65 file, giữ 6.260 file dữ
liệu/22 thư mục/registry; ASR rỗng hoàn tất review trước mapper. Native pending.

## 2.20.82 — Alien: timestamp đuôi, recovery từng câu và vùng nhiều chapter

Tái hiện đúng159cue unresolved của Alien 319 cue/3 voice trên81,149hit/0miss.
Primary chưa giới hạn word theo clip trước resolver; hai từ cuối vượt
69,162/142,424ms. Clamp mới ở primary/CPU fallback/retry giữ raw bất biến.
Recovery giữ riêng candidate đạt toàn bộ kiểm thay vì bỏ cả lượt vì một cue;
partial vẫn qua resolver, manual kiểm lại theo raw hiện tại, không cấp omission.

Manual chỉ nhận mép chapter khi neo nguyên câu duy nhất phủ tới từ cuối;
đuôi unknown vẫn dừng. Nhóm nối lớn được chia ở cuối neo nguyên câu, giữ
neo đúng một lần/hình/voice/lời thêm hai mép, không nâng timing hoặc giới hạn
30s/40cue/800từ. Rà shared subtitle/acoustic/DTW, legacy/speed/marker.
[Partition](../tests/unit/Test-AutoEditPartition.ps1) và
[partial recovery](../tests/unit/Test-AutoEditPartialRecovery.ps1) fail trước/
pass sau; giữ nguyên các ca78/79. Đạt68nhóm/145PS và20bộNode trong gói;73payload/74ZIP entries khớp nguồn.

**Alien vẫn pending:**149hit/0miss,157cue unresolved; vùng đầu35–44 dài
41,254545s chưa có neo an toàn ở giữa. Báo reason/cue/chapter/bounds thay
vì chỉ danh sách unresolved. Không nới guard hoặc tuyên bố ca Alien hoàn tất.
Hòn đảo qua đủ bốn entrypoint offline;30/30→66caption giống byte81. Cài82
kiểm65file panel, giữ6333file/22thư mục dữ liệu và registry CEP. Native pending.
[Phạm vi](releases/notes/EDITED_VOICE_2.20.82.md).

## 2.20.81 — Mặc định Khoảng không lời 0,5 giây

Mặc định cũ 1s nằm ở cả HTML, settingDefaults của panel, planner và hàm DTW
dự phòng. Đổi cả bốn thành0,5s; không tăng schema hoặc ghi đè giá trị đã lưu.
Nút reset dùng cùng settingDefaults. Rà cả luồng DTW mặc định/legacy,
speed merge và caption-only; caption-only không tiêu thụ ngưỡng dựng này.
Ngưỡng khoảng lặng âm thanh0,12s và các guard cắt/omission/recovery không đổi.

[UI regression](../tests/unit/default-edit-ui.test.js) tái hiện job mới còn1s
trước sửa; kiểm mới/missing và giữ giá trị đã lưu1/2s, tùy chỉnh1,5s.
[Planner](../tests/unit/Test-SourceDialogueGaps.ps1) kiểm job bỏ trường ngưỡng
vẫn giữ gap0,5s. [DTW](../tests/unit/Test-DtwEditTrial.ps1) kiểm caller trực tiếp
bảo vệ gap0,5s, vẫn chấp nhận ngưỡng tùy chỉnh1,5s.
Đã đạt66 nhóm/143 script và20 bộ Node trong gói. Replay đảo bỏ trường ngưỡng
dùng0,5s:30/30→66caption, SRT cuối giống từng byte với80 đặt rõ0,5s;
giữ27gap,1gap review, bảo toàn hình/voice và hash nguồn. Cài81 giữ6189file/
22thư mục dữ liệu và registry CEP. [Metadata](releases/2.20.81.json) lưu
bằng chứng; native Premiere còn pending. Giữ các ca khó và gap rà tay của80.

## 2.20.80 — Gap nguồn bị gộp bên trong câu/nhóm review

Ngưỡng người dùng0,5s được CEP lưu/UI truyền/engine đọc đúng; bản tái hiện
1s trước đó không chứng minh thông số lượt native đã tự dọn. Với0,5s,
gap4,16s cue11–12 retime vào42,77–45,50s, chứa mốc00:00:42:27 người dùng báo.
Planner gộp câu/nhóm an toàn trước khi xét gap nên gap nội bộ bị nuốt.

Xét gap trước punctuation grouping, giữ riêng chỉ khi cut voice an toàn.
Cue phục hồi cần capability độc lập từ ngữ cảnh raw DTW duy nhất hai mép,
coverage/số/bounds/chapter và quiet duy nhất đủ margin; không nâng span
estimated thành mốc từ. Manual block/omission đã xác minh giữ chính sách
riêng. Gap không tách được phải có metadata/marker theo V1 cuối/completion.
DTW/speed merge giữ cả gap và danh sách review. Log lưu năm thông số số
engine dùng, không lời/media, để audit sau dọn job.

[Regression](../tests/unit/Test-SourceDialogueGaps.ps1) fail trước/pass sau,
30/29,97fps, ngưỡng đúng/dưới, comma, raw compact digits, invalid/estimated/
ambiguous proof, offset và manual block. Các guard78/79 khi chưa có proof
mới vẫn đạt. UI test bỏ stub reader, kiểm truyền0,5 và các thông số khác;
metrics/marker test giữ privacy và ánh xạ theo hình cuối. Review cả legacy,
DTW, speed merge, manual fallback, omission map và subtitle-only.

Đảo0,5s giữ30/30→66caption;28gap đạt ngưỡng=27preserved+1review. Gap báo lỗi
giữ125frame/tốc độ gốc, cut voice34,4s có raw DTW/quiet0,484024s. Gap0,72s
cue5–6 còn review. Reference cố ý sai vẫn5khối/65caption, không chia khối.
Full66nhóm/143PS đạt, sáu Windows integration bỏ qua. Native pending;
[phạm vi và giới hạn](releases/notes/EDITED_VOICE_2.20.80.md).

## 2.20.79 — Auto edit giữ vùng khó để sửa tay

Sau phục hồi 78, một cue unresolved vẫn dừng cả job vì chưa phân biệt ASR
sai và voice bị cắt. Thêm đường manual riêng sau resolver, chỉ khi có neo
nguyên câu duy nhất/đúng thứ tự, giới hạn 30s/40cue/800từ và bounds/chapter
hợp lệ. Giữ đủ hình/voice thành khối retime, cấm omission cho job fallback;
không sửa ngưỡng hay kết luận omission của resolver đã resolved.

Giữ SRT khi identity/coverage riêng đạt; phần khác dùng surface ASR gốc.
Không khôi phục suffix thiếu, không bịa word timing. Chia cell caption chỉ
ước lượng, không DTW/voice-aligned; acoustic/legacy/DTW không mở điểm cắt.
Marker theo caption cuối; completion phải nói còn sửa tay. Vùng không đủ
neo vẫn dừng. Luồng subtitle giữ nguyên và Small vẫn mặc định.

[Regression](../tests/unit/Test-AutoEditManualReview.ps1) chạy planner thật,
kiểm SRT cuối/DTW/speed merge, từ chối plan bị sửa mất hình/voice/text/timing/
metadata. Test raw surface khóa trường hợp token một từ trên PowerShell 5;
fixture planner cũ được thêm dependency mới, không đổi kỳ vọng lịch sử.
Replay đảo gốc giữ30/30→66, giống byte78; bản sao reference cố ý sai tạo
5khối/65caption, giữ raw102 và không phục hồi chữ sai, toàn hình/voice giữ đủ.
65nhóm/142PS đạt, sáu nhóm Windows integration bỏ qua; lịch sử27/199 giữ nguyên.
Full Small Nam Cực255/255→468 caption giống byte78,113hit/0miss.
Native còn pending. [Chi tiết](releases/notes/EDITED_VOICE_2.20.79.md).

CI phát hiện phép kiểm allowlist mới cắt relative path theo độ dài chuỗi
TEMP, khác tên tuyệt đối đã chuẩn hóa trên runner. Test dùng tên từng mục
khi duyệt cây và tái hiện đường dẫn có `.`; không đổi security/runtime hoặc
ZIP đã xác minh để xử lý môi trường. Source/package runtime vẫn cùng hash.

## 2.20.78 — Auto edit dừng trước lớp phục hồi chữ SRT

Project hòn đảo: cue 11 “có một không hai” bị Small ghi “có 102”, chỉ còn
10/12 mốc. Căn sơ bộ đưa mọi cue qua exact omission resolver và báo thêm
cue 1,5,6,7,10,11,12,18,20,21,26,27. Tái hiện đúng danh sách; retry không
prompt riêng câu 11 vẫn trả 102. Đây chưa là bằng chứng voice thiếu các câu.

Trước resolver, dùng selection/projection/identity/retry của subtitle cho
cue chưa hoàn tất; giữ baseline khác. Chỉ nhận khi kiểm đủ lời và span gốc.
Chuỗi tên chữ số và token gộp phải khớp toàn bộ, ngữ cảnh chính xác và đạt
identity cũ; không chia span hoặc cấp DTW. Giữ nhóm quanh cue phục hồi,
chặn cả legacy/acoustic/DTW mở lại hai mép; marker theo mọi caption cuối.
Đường mới không trả omission/source map; partial cue, lời thêm, số sai,
lặp hoặc chưa đủ căn cứ vẫn qua chốt cũ. Không hạ ngưỡng hay đổi Small.

[Test mới](../tests/unit/Test-AutoEditReferenceRecovery.ps1) kiểm nguyên
chữ cuối qua planner thật, 102/4206, array clone/raw bất biến, timing/chapter/
offset, missing/extra/different speech và cả hai planner từ chối cắt tại mép.
Test marker kiểm từng caption chia. Offline đủ pipeline giữ **30/30 → 66
caption**, không omission/cut tại cue phục hồi; source project/SRT/MP3 bất biến.
64 nhóm / 140 PS đạt; lịch sử 27/199 giữ nguyên. Full Small Nam Cực 255/255 →
468 caption, SRT byte-identical 77, 113 ASR cache hit/0 miss. Sáu nhóm Windows
integration bỏ qua, native Premiere vẫn pending. [Phạm vi](releases/notes/EDITED_VOICE_2.20.78.md).

## Những điều cần giữ khi sửa

| Nhóm lỗi đã sửa | Điều không được làm mất | Bằng chứng hồi quy chính |
|---|---|---|
| SRT có nhưng đầu ra dùng chữ ASR | Câu đã xác định trong voice giữ chữ SRT tới caption cuối; số selected không thay kiểm đầu ra | [Partial reference](../tests/unit/Test-SubtitlePartialReference.ps1), [sentence identity](../tests/unit/Test-SubtitleSentenceIdentity.ps1), [2.20.64](releases/notes/SUBTITLE_TIMING_2.20.64.md) |
| Short kéo theo câu tương lai hoặc phục hồi lời đã cắt | Phục hồi có giới hạn và ngữ cảnh; giữ nguyên bằng chứng omission nghiêm ngặt của Auto edit | [Short reference](../tests/unit/Test-SubtitleShortReference.ps1), [edited reference](../tests/unit/Test-EditedReference.ps1) |
| Cửa sổ lớn sai làm mất câu nhận ra được | Thử câu riêng giữa hai hàng xóm đã xác định, kiểm raw ASR/timing; không nuốt lời thêm trước/sau | [Local retry](../tests/unit/Test-SubtitleRetryReference.ps1), [2.20.72](releases/notes/SUBTITLE_TIMING_2.20.72.md) |
| Căn sai dấu, mét/m và phân số | Thử projection thay thế khi đường cũ bị từ chối; giữ ASR gốc, không thay ngưỡng nhận câu hoặc đường ngôn ngữ khác | [Projection](../tests/unit/Test-SubtitleProjection.ps1), [2.20.73](releases/notes/SUBTITLE_TIMING_2.20.73.md) |
| Nhãn A/C ngắn bị bỏ | Chỉ giữ khi chữ đã quan sát nằm giữa đúng hai câu kề; không điền nhãn vào khoảng trống | [Letter reference](../tests/unit/Test-SubtitleLetterReference.ps1) |
| Lặp đuôi/ngữ cảnh hoặc mất lời thêm thật | Chỉ bỏ phần đã chứng minh thuộc hàng xóm; giữ lời thêm, CTA và phát hiện lặp mơ hồ | [Context boundary](../tests/unit/Test-SubtitleContextBoundary.ps1), [supplement](../tests/unit/Test-SubtitleSupplement.ps1), [recognition safety](../tests/unit/Test-SubtitleRecognitionSafety.ps1) |
| Timing sai hoặc overlap | Giữ vùng DTW đã kiểm, retry cục bộ vùng lỗi; phục hồi mép caption trước khi bổ sung ASR; timing ước lượng không cho phép cắt hình | [Local timing](../tests/unit/Test-SubtitleLocalTiming.ps1), [range fallback](../tests/unit/Test-SubtitleRangeFallback.ps1), [numeric timing](../tests/unit/Test-NumericCaptionTiming.ps1) |
| Marker che nhiều lỗi hoặc xóa marker người dùng | Marker chỉ đúng caption cuối; đối soát có xác minh/khôi phục, giữ marker thủ công và ngoài phạm vi | [Review markers](../tests/unit/Test-ReviewMarkers.ps1), [source mapping](../tests/unit/Test-MarkerSourceMapping.ps1) |
| Marker đối chiếu cách đọc số đã bỏ lại xuất hiện | Không bật lại chỉ vì ASR ghi số khác dạng; timing số là năng lực độc lập | [Numeric timing](../tests/unit/Test-NumericCaptionTiming.ps1), [review markers](../tests/unit/Test-ReviewMarkers.ps1), CHANGELOG 2.20.62 |
| Join SRT/ngôn ngữ voice gây ảnh hưởng luồng khác | Join giữ nguồn và cách chọn lại; ngôn ngữ voice rõ ràng, độc lập ngôn ngữ SRT qua primary/recovery/timing | [SRT join](../tests/unit/Test-SrtJoin.ps1), [voice language](../tests/unit/Test-VoiceLanguage.ps1) |

## Đợt sửa 2.20.74 — 2026-10-18

**Số/đơn vị viết gộp trong ASR:** Medium có `19 triệu km2` và
`480 000km2`, trong khi SRT ghi số đầy đủ và “kilomet vuông”. Mapper có thể
chạy sang câu kế, làm mất chữ SRT; ở ranh giới còn thấy lặp “chiếm”.

- Ca tái hiện mới: [Test-SubtitleUnitProjection.ps1](../tests/unit/Test-SubtitleUnitProjection.ps1).
  Đã thất bại trên source 2.20.73 trước sửa; bản sửa qua ca số/đơn vị, khác
  chiều đơn vị, lời thêm, raw ASR bất biến, offset và timing không hợp lệ.
- Cách sửa đang kiểm: lexical view chỉ dùng để so khớp số/đơn vị. Không chia
  một raw span thành nhiều điểm DTW; giữ provenance, đánh dấu phần chiếu gộp
  là ước lượng. Kiểm chiều đơn vị riêng để không nhận km thành km2 hay m2.
- Kiểm toàn engine: Medium tăng 252 → 254/255, phục hồi 43/232 và không còn
  lặp “chiếm”. Đã kiểm chuỗi chữ SRT trong output, không chỉ unit test/count.
  Bộ hồi quy local đạt 57 nhóm. Trạng thái phát hành/cài theo metadata 2.20.74.
- Theo dõi: issue #16 (repo cũ).

**Nam Cực baseline:** bản 2.20.73 trên audio dựng lại giữ 253/255 cue. Bản
2.20.74 giữ đủ **255/255** nhờ retry có ngữ cảnh đã xác minh, khôi phục 138
“nước hồ giàu sắt” và 207 chứa “Gamburtsev”, không hạ ngưỡng chung. Test:
[context retry](../tests/unit/Test-SubtitleContextRetry.ps1). Hàng xóm ngắn
cần câu liền kề mạnh hỗ trợ, không đủ điều kiện một mình; cả hai phía phải
khớp duy nhất, phần lời thêm vẫn phải được bảo toàn. Medium còn 138 và đầu
outro bị cụt nên chưa thay model. Sáu cue thiếu ở lượt native cũ không trùng bộ thiếu của audio
dựng lại; issue #14 (repo cũ)
được bổ sung bằng [xác nhận chạy lại của người dùng](acceptance/2.20.74_USER_RERUN_2026-10-18.md):
đã hết lỗi thay chữ SRT bằng ASR ở lượt thực tế. Voice ngoài SRT còn sai
từ/chính tả; timing/marker và các workflow khác chưa có xác nhận chi tiết
mới, nên không đổi toàn bộ nativeAcceptance thành accepted.

## Adapter nhận diện — 2.20.75

Tách lời gọi Whisper khỏi lớp căn timing/SRT qua `RecognitionBackend.ps1`.
`Json` giữ nguyên raw JSON cho lõi cũ; kết quả chuẩn khai báo giây tương đối
trong cửa sổ, ngôn ngữ yêu cầu/nhận diện, raw output và timing chưa xác minh.
Không coi SOW/DTW thô là word timing đã đạt. Cache key/tham số và CPU fallback
phải giữ như baseline; Auto edit vẫn giữ quyết định fallback/omission riêng.

Test [RecognitionBackend](../tests/unit/Test-RecognitionBackend.ps1) so với
mã gọi đóng băng từ 2.20.74: CPU/CUDA, cache, fallback, ngôn ngữ, Unicode
prompt, preset DTW, lỗi và dữ liệu thô. Test
[VoiceLanguage](../tests/unit/Test-VoiceLanguage.ps1) kiểm toàn bộ argv của
các đường Auto edit với hợp đồng 2.20.74. Thư viện mới phải có trong gói và
các fixture mini, không bỏ kiểm timing để làm fixture đạt.

Lượt toàn engine Small qua adapter cho SRT **giống từng byte** với 2.20.74:
255/255 cue nguồn, 468 caption. Đây là kiểm bảo toàn hành vi; chưa cải thiện
chất lượng chữ ngoài SRT vì weights/model production chưa đổi.
Chi tiết [adapter và probe timing](releases/notes/SUBTITLE_TIMING_2.20.75.md); kết quả probe
CTC chỉ là candidate chưa xác minh, không mở quyền cắt hình.

## Kiểm mỗi đợt sửa và phát hành

1. Chạy ca tái hiện trước/sau, kiểm chữ SRT ở caption cuối và các ca lân cận.
2. Chạy `tests/Run-Tests.ps1 -NoWindowsIntegration`; phát lại lịch sử khi thay
   lớp alignment/recovery/supplement. Các lỗi môi trường temp/quyền phải được
   tách khỏi lỗi runtime. CI hiện chạy bộ này cùng kiểm script và metadata.
3. Runtime đổi thì kiểm source/package/install parity và dữ liệu bảo toàn
   theo [quy trình GitHub](GITHUB_DISTRIBUTION.md). Không sửa/bỏ cache để làm
   test đạt hoặc ghi đè asset cùng version.
4. Báo riêng test tự động, package/install và nghiệm thu native; ghi rõ phần
   còn mở và liên kết issue/PR/CI. Giữ ca lỗi cũ trong suite cho lần sửa sau.

2.20.75: bộ hồi quy đạt 58 nhóm/131 script parse local; replay lịch sử giữ
đúng 27 cue Short và 199 cue có nhãn A/C. Gói có 72 payload/73 ZIP entry
đúng hash, 20 Node suite chạy trên byte runtime đóng gói. Các file lõi SRT,
omission, timing và host ngoài phạm vi adapter vẫn giữ hash bản 2.20.74.

## Kiểm lại Whisper trên 2.20.75 — 2026-10-18

Không bỏ Medium/Turbo/Large-v3 từ kết quả engine 2.20.73. Đã chạy mới ba
checkpoint trên engine/adapter 2.20.75, giữ weights/hash/preset/guard; kiểm
chuỗi SRT ở caption cuối: Medium 254/255, Turbo 254/255, Large-v3 255/255.
Small 255/255 từ replay75 đã xác minh. Medium còn 138 và cụt đầu outro;
Turbo còn 138/lời quảng bá sai; Large giữ đủ SRT nhưng mất caption outro.
Không nâng model từ số giữ SRT hoặc số vùng timing ước lượng.

Người dùng cung cấp lời chuẩn outro 77 token. Cùng WAV16,6 s: Small 6 lỗi,
Medium/Turbo/Large-v3 và cả hai Qwen đều 3 lỗi; toàn bộ vẫn sai Null Seek.
Cửa sổ thêm 3,838688 s phía trước làm Turbo sinh lời khác và Large-v3 bỏ
outro.8/8cặp bật/tắt word timing có cùng bản chép, giữ -nfa. Đây là độ nhạy
cửa sổ/cấu hình thử, không kết luận model-family kém hoặc Qwen thắng mọi ca.
Không đưa lời chuẩn làm prompt, không sửa raw ASR hoặc hardcode mốc outro
để cải thiện điểm. Bước tiếp kiểm recipe chia đoạn/VAD chung trên toàn corpus
và mẫu mới, giữ các model Whisper trong danh sách đo.

Bằng chứng kiểm lại Whisper
và JSON tổng hợp. Tool scoring kiểm WAV/ref/result hash; tool caption replay
phải phát hiện thiếu/lặp/token ASR chen giữa các cue giữ lại. Native timing
và model integration vẫn pending; đợt này không đổi runtime/bản cài.

## 2.20.76 — primary nghe được nhưng lượt bổ sung làm mất outro

Trace Large-v3 xác nhận primary raw và kết quả acoustic đều còn 75 từ DTW
ngay trước Complete-PvsSubtitleReference. Local supplement chỉ nhận câu SRT
trước đó; sau lọc ngữ cảnh không còn chữ mới. Lõi cũ không dùng lại primary,
báo recognition-unverified và bỏ cả outro. Không kết luận model không đọc
voice ngoài SRT từ caption cuối; phải lần cả raw, converted words và bước
supplement. Không đổi lịch sử đo trước sửa thành kết quả của bản mới.

Fix: snapshot primary trước SRT projection; đường lui chỉ cho đuôi source
khi lượt bổ sung rỗng, mốc SRT trái duy nhất và toàn bộ từ/anchor DTW/energy
hợp lệ. Không estimated/interior/unresolved, không cắt ngang từ, không ghi đè
nonempty, không nuốt lỗi native. Ghi primarySupplementReuseRanges.
[Test](../tests/unit/Test-SubtitlePrimarySupplement.ps1) thất bại trên 75 rồi
đạt trên 76, gồm source/chapter/offset, raw bất biến, im lặng/lặp/NaN/anchor
và bất biến nonempty. 59 nhóm hồi quy đạt; replay Small/Medium/Turbo SRT
byte-identical 75, Large giữ 255/255 + 75 từ outro, hết vùng thiếu. Lịch sử
27/199 giữ nguyên. [Chi tiết](releases/notes/SUBTITLE_TIMING_2.20.76.md). Native pending.

## 2.20.77 — local supplement nonempty nhưng chỉ có estimated

Trace Medium: local nhận 80 từ nhưng crop estimated bỏ “Xin cảm ơn các nhà
khám”, còn 69 từ; Turbo local trả quảng bá sai 13 từ, đều estimated. Primary còn
đuôi 74/75 từ DTW. Không gọi đây đơn thuần là model không nghe được outro.

Mở rộng đường lui 76 khi local accepted words hoàn toàn estimated; vẫn yêu
cầu primary hoàn chỉnh qua mọi guard DTW/bounds/energy/ngữ cảnh trái duy
nhất. Local DTW/mixed giữ nguyên; primary không đạt giữ local/chẩn đoán cũ.
Không đổi ngưỡng, không so confidence, blacklist tên hoặc chép lời chuẩn.
Test mới fail trên 76/pass 77, kiểm reason, invalid-primary/mixed/DTW, raw
bất biến cùng guard 76. 59 nhóm đạt; lịch sử 27/199 giữ nguyên. Small/Large
caption byte-identical 76; Medium 9→5, Turbo 75→3 lỗi/77 token outro. SRT vẫn
255/254/254/255, cue 138 chưa khép. Native timing chưa được nghiệm thu, mốc
cuối reference Medium 750,26s chưa sửa riêng. [Chi tiết](releases/notes/SUBTITLE_TIMING_2.20.77.md).
