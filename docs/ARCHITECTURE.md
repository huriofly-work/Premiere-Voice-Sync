# Kiến trúc hiện tại

Tài liệu này mô tả runtime 2.20.x (bản mới nhất 2.20.90, Whisper large-v3-turbo)
và lịch sử thiết kế của nó. Big update phát triển từng bước trên chính kiến trúc
này; kiến trúc cue-first riêng đã đóng ngày 13/11/2026.

2.20.64: Subtitle truyền MinimumAnchorWords=4 cho bộ đối chiếu edited-reference; mặc định core bằng 0, Auto edit giữ hành vi cũ. Xét lại câu chưa nhận ra khi phục hồi câu sau tạo đủ hai neo, dùng chung ngân sách chiếu. Ngữ cảnh dài cho phép một sai khác chính tả cục bộ để không thêm lặp đuôi câu SRT đã giữ. Marker ASR trỏ từng caption cuối. Xem [kiểm project](releases/notes/SUBTITLE_TIMING_2.20.64.md).

2.20.59: `CaptionOnly.ps1` thêm tiêu chí nhận ra câu SRT từ nhiều từ neo, dấu thanh và độ gần chính tả. Nhận ra câu thì giữ chữ SRT dù ASR sai/thiếu/thừa vài từ hoặc khác mép câu; timing quan sát được giữ riêng và không nâng thành DTW đã xác minh. Cue lặp được phân biệt trong vùng có câu hàng xóm xác định; xét cả cue recovery đã nhận đủ nhưng bị bộ dò exact bỏ lại do trùng văn bản toàn SRT. Bằng chứng shared core cho Auto edit bỏ hình giữ nguyên. Xem [chi tiết và kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.59.md).

2.20.50 — nguồn/phạm vi subtitle: `js/caption-input.js` là resolver ES3 dùng chung CEP và host, trả kế hoạch nguồn, track/clip được chọn, phạm vi chuẩn hóa, vùng bỏ qua và key đối chiếu. Quét metadata riêng khỏi lựa chọn; UI lưu cấu hình theo project/sequence, checkbox thủ công khóa tập nguồn. `runCaptions()` so kế hoạch đã hiển thị với lượt đọc trước chạy; job mang `audioInput`, `audioInputKey` và tọa độ timeline. Host kiểm lại resolver, đóng băng selection/range theo job, giữ staged native export. Mix không đổi mute/enable; track mode cô lập tập track; clip mode còn disable các clip không chọn giao phạm vi trên cùng track. Journal UTF-8 `job.json.audio-recovery.json` được ghi/đọc xác minh trước mutation, chỉ xóa khi khôi phục baseline đạt; cleanup giữ journal và phát hiện để khóa chạy sau reload. Khôi phục có kiểm project/sequence/cấu trúc và từng clip, độc lập mute/enable/In/Out. Snapshot thêm track/source identity và disabled; chưa bao phủ mọi tham số effect/mixer. Xem [thiết kế và kiểm chứng](reviews/AUDIO_SOURCE_SCOPE_REVIEW_2026-10-16.md).

2.20.43: luồng subtitle thêm `SubtitleTiming.ps1` và `SubtitleEnergy.ps1`. Kiểm DTW theo cửa sổ có mép ở khoảng nghỉ, giữ từ/timing hợp lệ ngoài vùng lỗi và retry riêng vùng lỗi. Envelope PCM mono 16 kHz/16 bit, RMS 5 ms, tìm đáy tương đối trong lân cận token của từ đứng trước; không dùng một offset cố định hoặc đỉnh attention của số làm ranh giới. Đầu ra ghi vùng retry/ước lượng và số ranh giới đo được; metrics chỉ giữ các số đếm. Các hàm timing/planner Auto edit không đổi. Xem [kiểm chứng](releases/notes/SUBTITLE_TIMING_2.20.43.md).

2.20.42: kiểm `Test-PvsReferenceCueTiming` dùng chung cho bounded recovery và xác nhận subtitle. `AllowUnmatchedRanges` giữ lỗi scope ở từng nguồn trong `FallbackRanges`/`UnverifiedRanges`; completion nhận diện lại riêng nguồn đó. Lượt ASR rỗng khi có tham chiếu vẫn đi qua retry, không chặn toàn job trước completion. Caller strict giữ nguyên hợp đồng lỗi; lỗi resource/native không bị coi là mismatch. Nội suy chỉ ở planner Auto edit. Xem [rà soát](reviews/ALIGNMENT_REVIEW_2026-10-15.md).

2.20.41: `ReferenceAlignment.ps1` là lõi chung (parser với chính sách Edit/Subtitle, lexical layout, sequential mapper, map-to-cue và bounded missing-cue recovery). `Alignment.ps1` giữ adapter/các hàm số; `CaptionOnly.ps1` giữ scope validation và completion policy. Hai luồng cùng dùng core projection; subtitle gọi cùng recovery trước ASR supplementation. Edit giữ legacy timing/global mapping và planner interpolation; subtitle giữ interval-bound timing/semiglobal scope, không dùng planner hoặc executor Auto edit. Package allowlist/checksum bắt buộc có core.

2.20.40: `Select-PvsSubtitleReference` dùng DP bán toàn cục với checkpoint hàng chi phí và tính lại traceback từng khối. Recurrence, tie order và near-best endpoints giữ nguyên; bộ nhớ chính O(m×√n), có kiểm ngân sách 128 MiB trước cấp phát thay giới hạn 25 triệu ô. `Complete-PvsSubtitleReference` giữ cue đã xác nhận và nhận diện khoảng thiếu/khác cùng lời nói ngoài SRT, gồm CTA. Lỗi DTW đầu vào nhận diện lại theo đoạn câu; supplement không dùng DTW/SOW hoặc prompt SRT. Không tìm được scope an toàn thì dùng ASR cho audio được chọn. Không đổi mapper/edit planner. Hàm `Align-PvsSubtitleReference` cũ vẫn giữ guard cũ.

2.20.39: pause là Promise chờ tại ranh giới an toàn, không suspend tiến trình. `runPowerShell` kiểm pause trước/sau script; executor kiểm trước begin và giữa các lượt; export chỉ pause trước phiên hoặc sau toàn phiên đã restore. Host `workflowPauseState` chỉ đọc, không dùng playhead/selection, so sánh lại khi tiếp tục; lỗi/khác biệt giữ recovery. Stop/fatal giải phóng waiter, giữ abort/cleanup cũ. Không tự resume từ journal sau reload. Metrics ghi riêng thời gian pause; native editing-call parity và no-delay giữ nguyên khi không yêu cầu pause.

2.20.38: nút dừng đặt cờ riêng của run, chặn host/engine kế tiếp nhưng vẫn cho abort kết thúc phiên/khôi phục audio. `run-workflow.ps1` gán worker đang chờ stdin vào Windows Job Object riêng rồi mới chạy script; theo dõi file cancel, kết thúc nhóm và chờ active process bằng 0 trước trả kết quả. Đóng wrapper cũng kết thúc nhóm. Lệnh native Premiere đang chạy không bị cưỡng bức ngắt. Giữ impact/recovery sau hủy và outcome cancelled riêng; không Undo/Save hoặc mở khóa sớm.

Baseline hiện tại đã được người dùng kiểm thử: 2.20.25. Chi tiết thay đổi và phạm vi nghiệm thu xem [báo cáo rà soát](reviews/AUDIT_2026-10-08.md).

Từ 2.20.23: `Alignment.ps1` giữ mapper PowerShell tham chiếu, dùng `WordMapper.ps1` cho ma trận từ đủ lớn (từ 100.000 ô). Lõi compiled dùng hai hàng cost và byte traceback, cùng recurrence/tie rules và so sánh InvariantCultureIgnoreCase. Cửa sổ nhỏ hoặc dữ liệu Text không phải string giữ đường cũ; lỗi compiler/runtime cũng fallback và không thử lại liên tục trong process đó. Không thay Whisper/DTW hoặc thêm setting người dùng.

Từ 2.20.24: đọc SRT Project chia begin/advance, có hạn thời gian riêng, không dùng filesystem để lọc danh sách. Chỉ timeout thao tác đọc, không áp dụng cho native edit/import. Planner giữ phần dựng cũ và chuyển riêng mốc caption âm học qua các interval A2 bằng frame; xung đột với cue legacy giữ cách cũ và báo review. Caption-only không dời/cắt A2 nên không cần phép chuyển này; lõi nhận diện/split/padding chung không đổi.

2.20.25: startup/Đọc lại quét SRT Project trước, kiểm tra sequence độc lập sau đó. Sequence đã dựng/không hợp lệ không ngăn liệt kê SRT; preflight Auto edit giữ nguyên.

2.20.26 (chờ nghiệm thu): chỉ đổi giao diện và cập nhật đầu vào. Hai chế độ dùng chung nút cập nhật, một promise đang chạy và chỉ đọc phạm vi của chế độ hiện tại. Chuyển tab trong lúc đọc chỉ bổ sung dữ liệu chế độ mới, không quét Project thêm. Chẩn đoán đầu vào giữ trong phần hỗ trợ thu gọn. Không đổi engine/JSX hoặc thêm polling.

2.20.27 (chờ nghiệm thu): planner loại điểm cắt nếu frame đó không lớn hơn đầu nhóm hiện tại hoặc không nhỏ hơn cuối câu kế tiếp. Không tự thêm một frame cho voice có range rỗng; range không hợp lệ và lỗi nối voice cùng chapter bị chặn ngay tại planner. Guard DTW bảo toàn voice và executor giữ nguyên.

## Cấu trúc và trách nhiệm

| Thư mục | Vai trò | Có trong panel được cài? |
| --- | --- | --- |
| `extension/js` và `extension/index.html` | Giao diện CEP, xác nhận, tác vụ, nhật ký, cleanup | Có |
| `extension/jsx` | Đọc Premiere, xuất audio, sửa timeline, caption, marker, hậu kiểm | Có |
| `extension/engine` | Whisper/FFmpeg, căn lời, kế hoạch theo frame, caption | Có |
| `installer` | Đóng gói, checksum, thiết lập/gỡ đúng extension ID | Chỉ script cần thiết trong ZIP |
| `tests` | Test tự động và harness media/native riêng | Không |
| `tools` | Sinh executor, từ vựng và bootstrap runtime máy build | Không |
| `docs/history` | Quyết định và kiến trúc phiên bản cũ | Không |
| `dist` | ZIP và staging phát hành, không theo dõi trong Git | Không |

## Hai quy trình

**Dựng theo voice:** đọc template → kiểm đầu vào/DTW/gộp trước ASR → `run-alignment.ps1` → `build-sentence-plan.ps1` → `build-dtw-trial-plan.ps1` → `build-speed-merge-trial-plan.ps1` → kiểm template còn nguyên → executor chia stage → hậu kiểm → cleanup. Tên `Trial` còn giữ để tương thích protocol; DTW và gộp một cặp là mặc định, không phải tùy chọn thử nghiệm.

SRT tiếng Việt dùng để căn chữ với A2 và mốc nguồn video. Không cần SRT ngôn ngữ gốc hoặc XML. Template có một nest chính V1/A1 linked và các chapter A2. Ngưỡng speed mặc định 70–130% là ngưỡng cảnh báo/gộp, không giới hạn retime. Gộp chỉ một lần với hàng xóm liền kề; cặp đã gộp không được dùng lại. Đoạn không lời được giữ nguyên; điểm cắt voice không đủ an toàn thì không cắt.

**Chỉ tạo subtitle:** đọc clip chọn hoặc toàn sequence + track voice (mặc định A2, A1 nếu chỉ một track) → lưu mute mọi track audio → tạm mute các track khác/bật voice → đặt In/Out, trả về từ host → nhường CEP 100 ms → advance xuất một vùng (vùng sau cũng chuẩn bị rồi nhường) → khôi phục và xác minh mute/In/Out khi xong/lỗi/abort → `run-captions.ps1` → kiểm snapshot → thêm Caption Track → cleanup. Thiếu track, không cô lập được hoặc khôi phục lỗi thì dừng. Không yêu cầu template V1/A1/A2, không razor/move/setSpeed. SRT tùy chọn cung cấp chữ; tool tìm phần khớp audio, không dùng timecode SRT để đoán timestamp.

## Timing và caption dùng chung

`CaptionTiming.ps1`, `Srt.ps1` và `Alignment.ps1` dùng chung giữa hai quy trình. DTW/token và khoảng nghỉ thực hỗ trợ mốc từ; splitter ưu tiên dấu câu có phần đọc đủ dài, nghỉ hơi đã xác minh, rồi ranh giới từ. Từ vựng offline bảo vệ cụm từ/tên viết tắt. Caption mặc định tối đa 42 ký tự, không padding mép từ 2.20.89 (bản trước nới tối đa 5 frame), không chồng caption kề bên; `Add-PvsCaptionEdgePadding` vẫn chạy với 0 frame để gỡ chồng lấn 1 frame và từ chối chồng lấn lớn hơn. Có fallback được báo rõ khi DTW không xác minh được; không bảo đảm chính xác âm vị tuyệt đối.

Từ 2.20.45, `Convert-PvsAcousticRecognition` dùng chung cửa sổ DTW, phục hồi cục bộ và đáy RMS cho cả hai workflow. Auto edit đo trên PCM nguồn rồi quy đổi speed/offset. Cue có đủ mapping chữ, neo hai mép và thời gian hợp lệ cập nhật cả caption lẫn Start/End/WordTimings trước planner; các điểm cắt và speed video có thể đổi theo đó. Cue ước lượng hoặc xung đột với cue chưa xác minh giữ mốc dựng dự phòng cục bộ. Phạm vi voice ngoài cùng của chapter được giữ hoặc mở rộng theo bằng chứng mới để không bỏ phần đệm đã có.

Planner vẫn yêu cầu khoảng nghỉ và bằng chứng hai phía để cắt voice; một đáy RMS ngắn chỉ tinh chỉnh mốc từ. DTW edit bổ sung điểm cắt trên baseline mới và kiểm bảo toàn nguồn/thời lượng/chữ. Speed voice do người dùng đặt được giữ; voice có media In khác 0 vẫn bị từ chối trước nhận diện vì chưa hỗ trợ offset trim đầu.

## Ghi timeline và chống lỗi

`host.jsx` là executor tham chiếu; `diagnostic-executor.jsx` được sinh từ đó bằng `tools/Build-DiagnosticExecutor.js`, không sửa file sinh bằng tay. Guard hash/freshness, sequence/snapshot, session/token/thứ tự call, source/duration/link và audit cuối vẫn bắt buộc.

Auto edit runtime mặc định profile `no-delay`: không timer chờ nhưng từ2.20.87 native retime được chia batch có giới hạn count/time, tối đa4 cặp mỗi lượt; rebind và kiểm invariant giữa các lượt. Các stage vẫn gọi nối tiếp qua CEP. Không chạy nhiều worker cùng ghi timeline, không tự Play/Save/Undo/xóa History. Baseline/fast/checkpoint chỉ giữ cho harness hồi quy, không có nút trên giao diện.

Marker thuộc ProjectItem/source, ánh xạ vào đoạn cần chú ý. `_markerTools` dùng chung cơ chế snapshot/đối chiếu/ghi/đọc lại/dọn/kiểm chứng cho clip và sequence marker; hai adapter giữ riêng hệ tọa độ và ownership. Auto edit chuẩn bị snapshot chỉ đọc trước dựng, thu thập yêu cầu sau khi biết mép clip thật, commit một nhóm ProjectItem trong một lần gọi host. Kể cả no-delay cũng trả quyền điều khiển giữa các nguồn. Nhóm yêu cầu lỗi không được dọn; dữ liệu marker bị đổi sau snapshot bị chặn trước commit. Compensate riêng dữ liệu marker đã đụng khi lỗi; báo rõ khôi phục không đầy đủ, không tự Undo timeline hoặc Save. Chỉ dọn marker nhận diện đúng tool trong vùng chỉnh; giữ marker thủ công/ngoài vùng và marker không phải Comment. Các instance cùng ProjectItem có thể thấy cùng marker; tag ownership không phải chữ ký chống sao chép. Xem [thiết kế và kiểm chứng](reviews/MARKER_RECONCILIATION_2026-10-17.md).

## Dữ liệu, cache và đóng gói

Chỉ cây `extension` được chép vào `%APPDATA%\Adobe\CEP\extensions\com.premierevoicesync.local`. ZIP có Setup/Remove, không đăng ký Installed apps. Whisper CPU/FFmpeg/model đi kèm; CUDA chỉ tải theo consent và pinned checksum. Runtime binary không theo dõi trong Git.

`%LOCALAPPDATA%\PremiereVoiceSync` gom Jobs, Logs, Cache, Models và Backends. Jobs/audio/plan/SRT tạm được dọn sau tác vụ; cache/model/backend giữ để dùng lại. Không sinh file cạnh project/SRT người dùng.

`AudioCache.ps1` chỉ lưu recognition/quiet thành công theo SHA256 bytes audio, model, executable, runtime và argv; không lưu kế hoạch timeline/PCM. Timestamp và kế hoạch tính lại theo đầu vào. Cache hỏng là miss, GPU fallback không lưu dưới khóa CUDA. Cache có retention dung lượng/thời gian. Lỗi lưu cache/log không biến tác vụ thành thất bại; path/link security vẫn phải kiểm.

Nhật ký hiệu năng/workflow chỉ lưu trường cho phép, không media/transcript; không tự gửi mạng. Log lỗi xuất ra được redaction nhưng cần đọc lại trước chia sẻ. Raw dump và dữ liệu `_local` không vào ZIP/GitHub.

## Kiểm chứng

Chạy `tests/Run-Tests.ps1`, kiểm JS trong CI và generator `--check`. Mock không thay thế nghe voice/caption và native Preview/Play/Save trên template sạch. Không promote tối ưu thuật toán chỉ vì test tự động đạt.

Chi tiết: [kiểm thử](TESTING.md), [bảo mật](SECURITY.md), [đánh giá hiệu năng](PERFORMANCE_REVIEW.md), [lịch sử kiến trúc](history/ARCHITECTURE_THROUGH_2.20.22.md).
