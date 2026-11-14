# Changelog

Từ 14/11/2026 chỉ mục "Chưa phát hành" đầu tiên là thay đổi đang chờ bản kế tiếp. Các mục "Chưa phát hành" cũ hơn bên dưới đã nằm trong bản phát hành gần nhất phía trên chúng và được giữ nguyên làm lịch sử.

## Chưa phát hành — dọn các hướng đã đóng, 2026-11-13

- Gỡ nghiên cứu cue-first (`experiments/`, khoảng 100 test, tài liệu và receipt), 13 tool Python chọn model ASR cùng báo cáo/benchmark ASR/CTC, sau khi chốt Whisper large-v3-turbo. Chi tiết trong [bộ nhớ hồi quy](docs/REGRESSION_MEMORY.md).
- Panel bỏ các hook dự phòng cho cue-first và năm file `extension/ui/`; gói cài bỏ payload `big-update/`. Hai nút Dựng theo voice và Chỉ tạo subtitle không dùng các hook này nên hành vi không đổi; thay đổi tới bản cài ở lần phát hành sau. Chưa kiểm trên Premiere thật.
- CI chỉ chạy trên pull request có đổi code, bỏ qua thay đổi chỉ ở Markdown/`docs/` và hủy lượt cũ khi có push mới; nhóm test cue-first từng chiếm khoảng 15 trong 20 phút của mỗi lượt CI.
- CI chuyển bộ lọc "chỉ đổi tài liệu" từ cấp workflow xuống job `changes`, để `regression-tests` bị bỏ qua vẫn được tính là đạt và có thể đặt làm check bắt buộc cho `main` (14/11/2026).
- Gói phát hành kèm toàn văn giấy phép GPL v3 của FFmpeg ở `licenses/GPL-3.0.txt` thay vì chỉ có link; `THIRD_PARTY_NOTICES.md` trỏ tới file này và ghi nơi lấy mã nguồn FFmpeg 8.1.2. Test kiểm file có trong allowlist của gói và đúng SHA-256 (14/11/2026).

## 2.20.90 — 2026-11-13

- Model nhận diện đổi từ Whisper Small sang Whisper large-v3-turbo, model duy nhất trong gói (người dùng bỏ Qwen, chọn chỉ dùng Turbo). Khóa runtime từ chối mọi model khác, kể cả Small đã pin hash. CPU dùng cùng Turbo.
- Kiểm GPU được cache theo cả model, nên lần đầu sau cập nhật sẽ kiểm lại CUDA với Turbo.
- Replay Nam Cực ngoại tuyến: giữ 254/255 câu SRT (cue 138 chuyển sửa tay), outro sai 3/77 từ. ZIP khoảng 1,6 GB; CPU chậm hơn Small khoảng 2 lần. Chưa kiểm trên Premiere thật.

## Chưa phát hành — gỡ Qwen, 2026-11-13

- Gỡ toàn bộ code, test, tool và báo cáo nghiên cứu Qwen theo quyết định của user. Panel và engine sản phẩm không dùng Qwen nên không đổi hành vi. Chi tiết trong [bộ nhớ hồi quy](docs/REGRESSION_MEMORY.md).

## 2.20.89 — 2026-11-13

- Big update chuyển sang xây trên bản 2.20.x. Phần đầu tiên: caption giữ đúng mốc đã căn, không còn nới 5 frame mỗi mép (quyết định S6 ngày 25/10). Áp cho cả Dựng theo voice và Chỉ tạo subtitle. Bước gỡ chồng lấn 1 frame giữa hai phần caption vẫn chạy; chồng lấn lớn hơn vẫn bị từ chối.
- Gia cố S8 T1 (đường dẫn UNC/link, Python đọc lại có khóa) nằm trong cùng nhánh; phần kiểm link dùng chung với panel giờ đi từ gốc ổ xuống.
- Bộ hồi quy 75 nhóm đạt, bỏ qua 6 nhóm Windows integration. Chưa kiểm trên Premiere thật: caption hiện ngắn hơn bản trước khoảng 5 frame mỗi mép.

## Chưa phát hành — S8/C01 recorded input/freshness, 2026-10-26

- Nối receipt/kết quả nhận dạng vào job: kiểm bounded PCM/raw/canonical/model/recipe/text/window và case→asset, pin nguồn tới completion/resume/final SRT; không execute receipt. Raw đổi giữ audio reuse nếu PCM không đổi, layout-only giữ analysis.
- 185 checks/ba final workflows/full75 nhóm169 parse đạt; hai C01 outputs thật match scope/tám pins/SRT byte exact,0 ASR/native mới. Giữ timing/CPS/default routes/legacy guards và global cut/native=false; full SourceMap/C06/C08/native S8 pending, không VERSION/model/runtime/install/release mới.

## Chưa phát hành — S8/C01 nguồn nhận dạng, 2026-10-26

- Proof hai WAV → Qwen → SRT đã chạy trong scope riêng:2 ASR/16s,2 PCM riêng,0 Premiere calls/retry/install. Source/PCM/raw/model/canonical/text/origins được kiểm tới SRT; không suy accuracy/word timing/cut.
- Chỉ docs/receipt, source/tests giữ PR44; reuse146/75 nhóm169 parse và CI hồ sơ riêng. Tiếp adapter receipt cho file input/JobSpec từ kết quả cũ; product envelope vẫn content=false, full SourceMap/native S8 pending. Không ASR/native thêm hoặc đổi VERSION/default/model/runtime/install/release.

## Chưa phát hành — S8 observations/audio tọa độ, 2026-10-26

- Liên kết lời thoại/timing với WAV ngoại tuyến: explicit asset/basis, relative origin cộng một lần, absolute giữ; speech/word/quiet/review seal tới JobSpec/final SRT. Stale source/manifest chặn reuse/export, layout-only giữ analysis.
- 146 checks/ba actual final workflows và full75 nhóm169 parse đạt. Giữ timing/CPS và nguồn/output cũ. Chỉ coordinate consistency khai báo; recognizer provenance/full SourceMap/native S8 còn pending. Hai WAV thật chỉ replay input với speech rỗng, không ASR/native/model/runtime/install/release mới.

## Chưa phát hành — S8 dependency S3 WAV binding, 2026-10-26

- Nối AudioAsset metadata vào job: WAV bytes/hash/PCM format/sample count, requested timeline ranges và provenance/freshness được seal tới final SRT. WAV/origin đổi chặn stale và invalidate downstream; layout-only giữ analysis.
- 134 checks/ba final workflows, replay hai WAV native chỉ đọc tới input checkpoint và full75 nhóm169 parse đạt. Giữ prepared speech/nests/timing/CPS và cut=false; chưa observations/audio mapping/full SourceMap/native S8. Không ASR/native/model/runtime/install/release mới.

## Chưa phát hành — S8 audio A2 feasibility, 2026-10-26

- Năm calls/hai WAV8s qua helper đang cài trên Premiere26.2.2 build3; WAV thực48kHz/stereo16-bit/384000 sample frames mỗi tệp. User nghe và xác nhận đúng đầu voice110% đã trim, chỗ nối, tốc độ và không lẫn track khác.
- Geometry/clip state/mute/In/Out/project/SRT giữ; debug gỡ/query verified9433=0, không ASR/clip edit/Save/Undo hoặc code/runtime mới. Tiếp S3 AudioAsset binding cho S8; full SourceMap/media/native recovery còn pending. Quota audio2 và F02 3+1 đều hết; không suy sample-exact content hoặc full native acceptance.

## Chưa phát hành — S8 dependency S3 geometry/binding, 2026-10-26

- Nối metadata geometry vào đầu vào job ngoại tuyến: giữ raw ticks, rational frames và source estimates approximate-unverified/residual; kiểm project/sequence/track/FPS, pin/freshness và invalidation tới SRT cuối. Không thay prepared speech/nests hoặc cấp cut/native authority.
- 127 checks/ba final pipelines, replay4 F02 packets và full75 nhóm/169 PS parse đạt. S8 đang hoàn thiện dependency S3, full SourceMap/audio vẫn thiếu capability; không gọi thêm native/ASR hoặc đổi runtime/VERSION/install/release. Quota F02 3+1 đã hết, legacy nonzero-In/nest-speed guards giữ.

## Chưa phát hành — F02 source coordinates, 2026-10-26

- Một lượt F02 bổ sung theo quyền riêng, hai scans giống nhau trên voice110%/In>0. Hai endpoints API rate-scaled được phân biệt theo mẫu, residual tối đa1.1tick giữ; không threshold/rounding để ép exact PASS, không ghi đè literal35/43 hoặc40/43 cũ.
- Phạm vi F02 chỉ đọc đã xong; tiếp phần S3 chuẩn hóa geometry/input binding đã có trong kế hoạch, giữ raw/provenance/precision/unknown. Chưa code/test/adapter hoặc runtime mới, không nới legacy nonzero-In guard/cut authority. Prepared project/SRT giữ byte, debug gỡ/query verified9433=0; quota3+1 đã hết. Full SourceMap/audio/native apply và S8/S9 chưa nghiệm thu.

## Chưa phát hành — F02 native chỉ đọc, 2026-10-26

- Chạy đúng3 lượt F02/hai scans trên Premiere26.2.2 build3: Auto edit3 nest/3 voice, hai caption modes0/3; voice observations giống nhau và ASR-only không reference. Không sửa code/runtime hoặc gọi ASR/native mutation.
- Source-out voice110% còn needs-review: giữ comparison literal35/43; so năm cặp ID decimal/hex lossless thành40/43, vẫn chưa PASS ba out-points. Không đổi oracle/cấp cut authority; chưa khép full F02/S8/S9. Project/SRT/source giữ byte, debug gỡ theo hash và query verified cổng9433=0; quota native đã dùng hết.

## Chưa phát hành — S8 readiness ngoại tuyến, 2026-10-25

- Rà C01–C08, đối chiếu source hashes với clone/import V2/conditional receipts; phân biệt content drift và LF/CRLF, giữ scope native cũ/FAIL/needs-review. S7 UUID/checkpoint không cấp native apply; QA SRT không tự thành import transport.
- S8 còn mở tại native gate: tái dùng F02 protocol3 read-only calls/hai scans, vẫn deferred theo lựa chọn chỉ ngoại tuyến. Chỉ docs/receipt, không code/test/ASR/native/runtime/install/release mới; reuse validation S7 cùng code, CI nhánh kiểm riêng.

## Chưa phát hành — S7 JobSpec/lifecycle ngoại tuyến, 2026-10-25

- Nối JobSpec/controller/store/CLI cho prepared observations + file SRT: pin settings/profile/source/code, candidate UUID riêng, owner/revision/checkpoint, safe-boundary pause/cancel và explicit resume. Layout-only reconfigure giữ analysis/saved values; source/profile/artifact stale bị chặn; schema lạ/abandoned owner/native impact không tự replay.
- Proof Windows12 trước code,126 checks ba actual workflows tới SRT và full75 nhóm/169 parse đạt. Phạm vi/bước tiếp S8. Chỉ analysis-only; product UI/full media/native lifecycle/legacy converter còn gate. Không ASR/native/runtime/install/release mới.

## Chưa phát hành — S6-v1 caption/SRT/review, 2026-10-25

- Theo lựa chọn user, giữ timing/không padding, chỉ thêm số ký tự/giây từng caption và tổng hợp vào final review; không tự đặt ngưỡng, retime hoặc sinh cảnh báo CPS. Tái dùng splitter/word+quiet/review ba workflows, giữ nguyên QA SRT.
- Timing/CPS63 và actual file/SRT189 checks đạt; full75 nhóm/169 parse đạt. Bước tiếp S7 lifecycle. Phạm vi/quyết định. Native/style/collision giữ gate riêng; không đổi runtime/model/VERSION, cài/phát hành hoặc gọi Premiere/ASR.

## Chưa phát hành — S5-v1 bốn oracle bảo toàn, 2026-10-25

- Kiểm missing B/source silence/extra D/order conflict qua independent frame oracle, domain validator và actual CLI/PS5/final SRT.399 checks giữ720 picture/570 speech-fixture frames,810 output frames/10 captions; không cần sửa planner/validator hoặc thêm family.
- Lưu oracle vào hồi quy;75 nhóm/169 parse đạt, gap/trim/composite chưa đo vẫn protected/manual. Phạm vi/bước tiếp S6. Không renderer/model/ASR/native/install/release mới; giữ rule bám kế hoạch đã được user yêu cầu.

## Chưa phát hành — chốt S4-v1 ngoại tuyến và sửa thứ tự kế hoạch, 2026-10-25

- Chốt điều kiện hữu hạn cho corpus/identity/caption baseline; Qwen1.7B/energy25 là ứng viên caption-only tích hợp thử có review theo số đo đã có, chưa chứng minh hơn Small cùng100 câu hoặc đổi default. Timing/cut/source/primary guards giữ.
- Chuyển composition recovery/tối ưu thêm vào backlog và product/native/acceptance về đúng gate; bước tiếp S5 với bốn oracle bảo toàn cố định. Exit review. Chỉ tài liệu/receipt, không đổi code/runtime/install/release hoặc chạy nghiên cứu ASR/corpus mới; CI nhánh kiểm riêng.

## Chưa phát hành — H05 local context application stage, 2026-10-25

- Nối opt-in một original target/cache vào main CLI qua pure policy và one-use port. Tính lại proposal/derived trước áp dụng; pin nguồn/profile/policy/context/receipt/implementation qua payload/layout tới SRT. Giới hạn công việc riêng recognition32/180, hủy ở boundary; không bật mặc định hoặc ghép retry/tail/chaining.
- 213 checks trước promotion,9 prototype +3 v2 +3 promoted real-data final pipelines giữ domain/SRT và default whole report/file packet. Repro API/null-port silently fallback được chặn, stale source/receipt/code/missing binding không export. Phạm vi/bước tiếp. Không ASR mới, đổi model/runtime/cài/phát hành hoặc nghiệm thu Premiere.

## Chưa phát hành — H05 local context proof, 2026-10-25

- Proof ngoại tuyến dùng hai retained exact primary anchors đã khóa trước proposal để giới hạn2–4 cue lặp quanh một observation. Tái dùng conservative candidate/word-map, giữ raw/words/frame/extras và mọi match cũ; lineage và generic-score coverage bypass bị chặn trước promotion.
- Thêm evaluation helper/CLI,250 checks và receipt freshness API.6 windows cố định qua18 proposals:4 windows nhận thêm2–3 cue mỗi call,2 giữ parent/review, ASR-only không đổi.8 final pipelines trước promotion,4 sau giữ SRT bytes/domain JSON;75 nhóm/parse169 đạt. Không ASR mới hoặc bật application/default recovery. Phạm vi/bước tiếp.

## Chưa phát hành — H05/H06 long cache và application resource, 2026-10-25

- Kiểm primary lịch sử766,5s/3.025 từ cùng255 cue, ca gộp ba observations và lặp hai lượt qua9 CLI/layout/final SRT pipelines. Giữ primary, raw extras và toàn SRT theo từng policy; cue lặp chưa đủ unique anchors giữ review, không hòa hypothesis hoặc nới guard.
- Thêm evaluator đo full Node application và315 checks sau proof.16 balanced resource samples giữ full report/binding với dense oracle; RSS không giảm nhất quán trên ca dài, không kết luận speedup/project winner. Budget32/180 và caps giữ;75 nhóm/parse169 đạt. Phạm vi/bước tiếp. Không ASR mới, đổi runtime/cài/phát hành hoặc nghiệm thu Premiere.

## Chưa phát hành — H05 live/cache main CLI, 2026-10-25

- Thêm `--tail-mode live|cache` tường minh qua cùng composition root; generic cache cũ giữ tương thích, execution cache kiểm receipt riêng. Mode/resource được seal tới SRT; không suy live từ JSON hoặc fallback model. Identity Small CPU và tail Large-v3 không được ghép ngầm; signal handlers gỡ cả khi lỗi/hủy.
- Một ASR thật qua main CLI trước promotion,9 final pipelines và9 promoted replays giữ SRT bytes.189 checks mới,6 cặp default/legacy CLI giữ toàn output bytes,600 corpus comparisons và75 nhóm/parse169 đạt. Phạm vi/bước tiếp; chưa đổi runtime/bản cài hoặc khép H05/H06/S4/native.

## Chưa phát hành — H05 live tail proof, 2026-10-25

- Proof ngoại tuyến bằng3 ASR thật cùng profile: giữ75 từ đuôi tới SRT, chặn15 từ trên silence và hủy sau spawn với process tự kết thúc/không công bố output. Sau proof mới thêm adapter/evaluation command riêng; main CLI tại mốc này vẫn cache-only, chưa đổi model mặc định/bản cài.
- Sửa reservation tail dùng cả frame và exact PCM samples sau repro undercount; giữ epsilon/budget32/180. Phân biệt live1 với cache0/origin1, pin runtime/dispatch/receipt tới export.123 checks mới và75 nhóm/parse169 đạt;9 final replay không ASR giữ SRT bytes,600 default comparisons giữ report/binding. Phạm vi/bước tiếp.

## Chưa phát hành — H05 tail stage ngoại tuyến, 2026-10-25

- Nối TailSupplement qua port cache dạng opt-in trong application/CLI, giữ primary và ba policies. Dùng chung ledger32/180 với identity retry, kể cả cached work; hết ngân sách/no-op không đọc candidate. Port dùng một lần, kiểm hủy ở boundary, giữ artifacts khi lỗi.
- Seal nguồn/cache/observations và tail/work metadata tới layout/SRT cuối; thay file sau analysis chặn export. Probe/extractor cũ dùng chung adapter, không nhân đôi policy.175 assertions mới,75 nhóm/parse169 đạt;9 prototype/9 final cached pipelines giữ SRT như proof,600 default report comparisons giữ toàn JSON/binding. Không ASR mới, đổi model mặc định, VERSION, runtime/cài/phát hành hoặc nghiệm thu Premiere. Phạm vi/bước tiếp.

## Chưa phát hành — proof H05 tail supplement, 2026-10-25

- Hai ASR thật trên đuôi bị primary bỏ sót và silence control chứng minh đường thử ngoại tuyến tới SRT cuối: giữ đủ75 từ raw đuôi, primary bất biến;15 từ hallucination từ silence bị support guard hiện có chặn. Sửa lỗi mất3 từ zero-duration trong prototype trước khi thêm evaluation tool; không sửa shared parser/threshold.
- Thêm probe cached candidate riêng và129 assertions; cả ba policies qua selected-file/CLI/PS5/layout/SRT,75 nhóm hồi quy đạt. Application/default CLI chưa tự gọi supplement; còn tích hợp budget/cache/cancel/lifecycle. Chưa đổi model mặc định, runtime, VERSION, cài/phát hành hoặc nghiệm thu Premiere. Phạm vi và bước tiếp.

## Chưa phát hành — nghiên cứu H05, 2026-10-25

- Preparation nghiên cứu tách hai câu fuzzy liền kề khi cùng coverage, đủ unique observed edge anchors và đạt nguyên profile identity/semantic guards. Giữ raw/word/frame, mixed exact/fuzzy và extras đầu/cuối; thêm/mất từ/lặp/ambiguous giữ observation để review. Có proof trước sửa, regression FAIL→PASS và kiểm file→CLI→layout→SRT cả ba policies.
- Kiểm lại cached Large-v3 context/local bằng đúng parent PCM và lời chuẩn lịch sử. Cơ chế automatic supplement còn mở; primary/outro, retry guard, timing/cut/native authority giữ nguyên. Corpus600 analysis comparisons giữ toàn JSON và SHA600 SRT cũ; chưa cài/phát hành hoặc chốt backend. Phạm vi.

## Chưa phát hành — nghiên cứu S4, 2026-10-24

- Matcher nghiên cứu dùng hai hàng suffix và ring index thay ma trận suffix toàn phần; giữ recurrence/tie/first10k optimal edges, ambiguity và caps. Có dense oracle, resource regression trước/sau và H05 primary/outro/retry-preservation tới SRT cuối; chưa thêm merged-fuzzy/retry-only recovery. Phạm vi.
- Khảo sát nguồn nhãn và thêm evaluator đọc SRT đã ghi:16 literal targets/17 lần tên-số-ký hiệu trên prefix12 case, kiểm lại600 SRT cùng hash/scores; không coi count matches là word/audio gold hoặc chọn backend. Ba mốc nghe lịch sử được tái xác minh, không tạo annotation/timing/native mới. Phạm vi.
- Phân loại review thành policy/timing/mapping rồi thử chọn lại mép caption bằng existing anchors;184→116 pending trên600 lượt giữ nguyên analysis/chữ. Tách shared H01 token/protected-boundary map, default splitter giữ2.400 parity cases; phần chọn mép mới chỉ trong research harness. Phạm vi.
- Sửa helper timing dùng chung khi kết quả parser không có từ: PS5 không còn gọi Copy trên null. Primary/acoustic-window/retry/local fallback dùng cùng helper; không tạo timing, speech hoặc quyền cắt mới.
- Giữ dấu câu gốc ở research local fallback, kể cả khi thay timing qua nhiều vòng overlap cascade; thêm kiểm thử tái hiện trước/sau. Phép thử corpus dùng retained Turbo DTW và Qwen text alignment để kiểm SRT cuối; mọi timing vẫn chưa xác minh, chưa là nghiệm thu Premiere.
- Chỉ sửa source/thử ngoại tuyến trong PR nháp; chưa đóng gói/cài, đổi VERSION hoặc thay assets đã phát hành. Chi tiết ở báo cáo S4 timing.

## 2.20.88 — 2026-10-22

- Đổi kiểm chứng nhiều điểm cắt từ chuẩn hóa/quét lại toàn bộ SRT cho từng proof sang bảng đếm xây một lần từ reference hiện tại trong mỗi lượt kiểm. Đường kiểm từng proof vẫn giữ được; không nhận bảng đếm từ plan, không lưu quyền cut/omission hoặc bỏ chốt DTW/uniqueness/quiet/chapter/frame.
- Chuẩn hóa chữ dùng bảng nhớ trong process có giới hạn, khóa theo chuỗi gốc chính xác; Unicode/số/chữ thay đổi và caller mutation được kiểm hồi quy. Dùng chung ở Auto edit/caption-only và các đường retry/fallback.
- Tách số vòng quét plan khỏi số cặp đổi speed thực sự: tối đa4 cặp V1–A1/đợt, iteration/time cap và guard/snapshot/rebind/hậu kiểm giữ nguyên trên baseline/fast/no-delay. Mock302 đoạn giảm152→52 đợt speed, chưa phải số đo thời gian Premiere.
- Số đo offline, so toàn bộ đầu ra, hồi quy và giới hạn được ghi trong [báo cáo](docs/releases/notes/AUTO_EDIT_ACOUSTIC_2.20.88.md). Native acceptance và cài đặt khi Premiere còn mở vẫn pending; không tự Save/Undo/ép đóng.

## 2.20.87 — 2026-10-21

- Sửa chế độ không-delay đã vô hiệu giới hạn đợt, gom hàng trăm lần đổi tốc độ vào một lệnh Premiere. Giữ giới hạn thời gian/số clip cho mọi profile, tối đa4 cặp V1–A1 khi đổi speed; dừng/hủy được kiểm ở ranh giới cặp.
- Tách gói dữ liệu native khỏi đồ thị nhận diện: Alien3874932→889562 byte,12208→1212 object; giữ chính xác geometry, voice, marker, identity, omission map và hậu kiểm. Caption-only dùng cùng nguyên tắc, giữ snapshot/import/marker; dữ liệu đầy đủ vẫn trong job.
- Ghi trước/sau QE lookup, setSpeed, move và razor; panel có thể chỉ ra lệnh chưa trả về. Không timeout bỏ lệnh, không retry chỉnh timeline hoặc tự Save/Undo. Một lệnh native đơn lẻ bị kẹt vẫn không thể bị ngắt an toàn bởi nút Dừng. Native nghiệm thu còn pending. [Chi tiết](docs/releases/notes/AUTO_EDIT_ACOUSTIC_2.20.87.md).

## 2.20.86 — 2026-10-21

- Khôi phục cue SRT làm đơn vị dựng hình. Hình/A1 có thể chia tại mép lời đã đo trong khi A2 giữ liền; khối review, dấu câu và khoảng lặng voice không còn bắt hình phải dùng chung mọi ranh giới.
- Tận dụng bằng chứng DTW nguyên cue đã đạt điều kiện hiện có, thay vì chỉ tám từ quanh mép. Cắt voice vẫn cần khoảng lặng thật và biên bảo vệ; không thêm omission, không dùng timing ước lượng để cấp quyền cắt.
- Alien replay: 158 → 302 đoạn hình, 234 đoạn voice; phục hồi thêm 6 cue, giữ 695 caption và đủ frame. Review dự kiến 74 → 62 vị trí; retime hình đúng kế hoạch không tạo marker tốc độ dư. Các vùng chữ/timing chưa xác minh vẫn được báo. [Phạm vi, lịch sử và giới hạn](docs/releases/notes/AUTO_EDIT_ACOUSTIC_2.20.86.md).

## 2.20.85 — 2026-10-21

- Sửa khối review dài nuốt điểm cắt, làm hình lệch voice: dùng ngữ cảnh DTW độc lập và khoảng lặng đã đo để chia hình/voice, tách quyền cắt khỏi chữ caption cần rà.
- Tự căn lại các ô lời trong khối, nhận diện lại cục bộ khi chưa đạt; giữ điều kiện DTW hiện có. Chỉ đánh dấu phần timing còn ước lượng. Gộp tốc độ không được đẩy mốc đồng bộ đã xác minh lệch quá một frame.
- Replay Alien: 19 → 158 nhóm dựng, 231/268 ô lời được căn tự động, giữ đủ 695 caption/chữ/frame hình và voice; marker dự kiến 111 → 74. Vẫn giữ các vùng chữ/gap chưa xác minh, không gọi đó là lỗi đã nghe xác nhận. [Phạm vi và số đo](docs/releases/notes/AUTO_EDIT_ACOUSTIC_2.20.85.md).

## 2.20.84 — 2026-10-21

- Sửa 620 marker Alien bị phóng đại: manual proxy confidence=0/thiếu word timing không phải lỗi nhận diện của từng caption; mỗi khối chỉ có một marker timing.
- Chỉ đánh dấu chữ ASR chưa khớp theo cell cuối, giữ cảnh báo DTW/gap/native/tốc độ độc lập. Không tạo marker A2 chỉ từ confidence tổng hợp của manual proxy; giữ marker tay khi reconciliation.
- Giữ chữ SRT cho cell trùng nguyên câu dù timestamp từ chưa đủ bằng chứng; không phục hồi câu thiếu/thừa, số khác hoặc ứng viên mơ hồ, không cấp timing/cut/omission.
- Replay Alien 695 caption, giữ 280/319 câu SRT, 39 pending; 111 marker dự kiến thay 620, cùng kế hoạch frame hình/voice. Không nâng model hoặc tuyên bố nghiệm thu native. [Chi tiết](docs/releases/notes/REVIEW_MARKERS_2.20.84.md).

## 2.20.83 — 2026-10-21

- Lỗi nhận diện khó không hủy tác vụ: giữ nguyên khối hình/voice dài cần review, không cắt nhỏ hoặc cấp omission từ bằng chứng chưa đủ.
- Không ghép được phạm vi thì trả kết quả cần xử lý thủ công, giữ timeline và không gọi executor/import giả; thông báo có vị trí và không nói đã dựng xong.
- Caption-only giữ primary hữu ích khi retry đuôi chưa đạt, đánh dấu phần chưa được phủ; kết quả rỗng cần review và không import Caption Track rỗng. Lỗi IO/runtime/cancel không bị nuốt.
- Alien offline319cue→695 caption, giữ276 cue chữ SRT có bằng chứng/43 cue pending;56 khối review,4 khối dài. Bảo toàn toàn bộ frame hình/voice và các cell chữ; không nghiệm thu native.
- [Phạm vi và kiểm chứng](docs/releases/notes/EDITED_VOICE_2.20.83.md).

## 2.20.82 — 2026-10-21

- Chuẩn hóa mép timestamp primary/retry trước resolver, giữ raw/cache nguyên trạng và không nâng timing ước lượng thành DTW.
- Phục hồi độc lập từng cue đạt kiểm chứng; các cue chưa đạt vẫn qua resolver/giữ vùng cũ, không cấp omission từ caption recovery.
- Phân hoạch vùng sửa tay tại neo nguyên câu duy nhất, sở hữu neo một lần; mép chapter cần câu neo phủ tới từ cuối file. Giữ giới hạn 30 giây/40 cue/800 từ và toàn bộ hình/voice/lời thêm.
- Alien 02 vẫn dừng ở vùng 35–44 dài 41,25 giây chưa có neo đủ chắc bên trong. Chẩn đoán mới nêu vùng/lý do chặn; không tuyên bố ca này đã sửa hoàn tất.
- [Phạm vi và kiểm chứng](docs/releases/notes/EDITED_VOICE_2.20.82.md). Native Premiere pending.

## 2.20.81 — 2026-10-20

- Đặt Khoảng không lời mặc định 0,5 giây ở HTML, thiết lập panel, planner và DTW fallback; giữ nguyên giá trị tùy chỉnh đã lưu.
- Regression kiểm giá trị mặc định đi tới job, trường bị thiếu, thiết lập đã lưu 1/2 giây, tùy chỉnh 1,5 giây, engine thiếu ngưỡng và DTW gọi trực tiếp. Không đổi điều kiện cắt voice, omission hoặc timing.
- [Phạm vi và kiểm chứng](docs/releases/notes/EDITED_VOICE_2.20.81.md). Native Premiere pending.

## 2.20.80 — 2026-10-20

- Xét khoảng không lời SRT nguồn trước gộp dấu câu/nhóm an toàn; nhận đúng ngưỡng tùy chỉnh, kể cả 0,5 giây và khoảng bằng ngưỡng. Giữ gap ở tốc độ gốc khi voice có điểm cắt an toàn.
- Cue phục hồi chỉ được tách tại gap nguồn khi hai mép có ngữ cảnh raw DTW duy nhất và khoảng lặng đo được đủ biên an toàn; giữ nguyên timing từ ước lượng và chốt cắt thông thường. Manual block vẫn không chia bên trong.
- Khoảng chưa thể tách được liệt kê và có marker theo tọa độ hình cuối, kèm thông báo cần rà tay. Lưu năm thông số đã áp dụng vào workflow log sau bước planner, không lưu lời/media.
- Regression và replay đảo giữ30/30→66caption, bảo vệ27/28gap đạt0,5s; khoảng4,16s được giữ125frame, khoảng0,72s còn review. [Chi tiết và giới hạn](docs/releases/notes/EDITED_VOICE_2.20.80.md). Native Premiere pending.

## 2.20.79 — 2026-10-20

- Auto edit có thể tiếp tục qua vùng chưa phân biệt được ASR sai và voice bị cắt khi xác định được khối bằng câu neo đủ chắc. Giữ đủ hình/voice, không cho omission hoặc điểm cắt bên trong khối.
- Caption giữ SRT đã xác minh độc lập và chữ ASR gốc cho phần còn lại; chia caption ước lượng có nhãn, không giả word timing/DTW. Marker theo caption cuối và thông báo hoàn tất nêu rõ số vùng cần sửa tay.
- Vùng không có neo, sai thứ tự/chapter/bounds hoặc quá giới hạn vẫn dừng trước sửa timeline. Luồng omission đã xác minh và subtitle-only giữ chính sách riêng. Mặc định vẫn Small.
- [Phạm vi, kiểm chứng và giới hạn](docs/releases/notes/EDITED_VOICE_2.20.79.md). Native Premiere pending.

## 2.20.78 — 2026-10-20

- Auto edit thử phục hồi SRT bằng lớp đối chiếu dùng chung trước khi kiểm voice đã cắt; giữ các câu đã căn được.
- Đối chiếu span chữ số viết gộp với chuỗi tên chữ số chỉ khi ngữ cảnh và toàn bộ chuỗi khớp; giữ timing nhóm là estimated, không bịa mốc từ.
- Gộp hai mép cue phục hồi để kiểm tra, chặn acoustic/DTW tạo lại điểm cắt và ánh xạ marker theo caption cuối. Giữ nguyên bằng chứng omission/source map và model Small.
- Ca tái hiện, điều kiện và giới hạn: [Auto edit 2.20.78](docs/releases/notes/EDITED_VOICE_2.20.78.md). Native Premiere pending.

## 2.20.77 — 2026-10-18

- Dùng lại primary tail hoàn chỉnh qua DTW/nguồn/bounds/energy/ngữ cảnh khi local supplement chỉ còn estimated; giữ mọi guard của 76, không thay local có DTW/mixed, không lấp cue unresolved hay nuốt lỗi native. Snapshot chỉ cho luồng có SRT.
- Lượt Nam Cực giữ SRT 255/254/254/255 qua Small/Medium/Turbo/Large-v3; Medium outro giảm 9→5/77 lỗi, Turbo 75→3/77; Small/Large caption byte-identical 76. Thêm ca tái hiện fail trên 76/pass 77;59nhóm đạt. Mặc định vẫn Small; cue 138/tên riêng/timing native còn mở.

## 2.20.76 — 2026-10-18

- Sửa mất outro dù ASR ban đầu có chữ và word timing hợp lệ: khi lượt bổ sung chỉ còn ngữ cảnh, giữ đuôi primary DTW có bounds/source/chapter/energy và ngữ cảnh trái duy nhất. Không dùng estimated, không lấp khoảng giữa/unresolved SRT, không thay bản chép nonempty hoặc nuốt lỗi native.
- Large-v3 ngoại tuyến giữ 255/255 SRT, khôi phục 75 từ outro; lỗi caption outro từ 77/77 xuống 3/77 theo lời chuẩn người dùng. Small/Medium/Turbo caption giống từng byte bản 2.20.75. Thêm ca tái hiện và guard regression; 59 nhóm đạt. Model production vẫn Small, nghiệm thu Premiere còn chờ.

## 2.20.75 — 2026-10-18

- Tách adapter Whisper: profile, argv, CPU fallback và kết quả chuẩn với raw JSON bất biến, timing chưa xác minh. Auto edit mới dùng chung argv; thuật toán SRT/timing/omission giữ nguyên.
- So sánh 11 tình huống với mã gốc 2.20.74; toàn engine Small cho caption giống từng byte, giữ 255/255 cue. Model phát hành vẫn Small, chưa cải thiện chữ ngoài SRT.
- Ghi nhận người dùng đã kiểm hết lỗi thay chữ SRT ở 2.20.74. Thêm probe CTC tiếng Việt riêng cho Qwen: 3/4 ca tạo candidate, ca No6 bị từ chối; chưa có timing gold/native acceptance. Xem tài liệu 2.20.75.

## 2.20.74 — 2026-10-18

- Giữ chữ SRT khi ASR gộp số/đơn vị như `000km2`; kiểm chiều đơn vị, giữ raw ASR và không tạo word timing giả. Lượt Medium phục hồi cue 43/232 và bỏ lỗi lặp “chiếm” tại ranh giới.
- Retry tiếng Việt với ngữ cảnh audio hai bên sau khi câu riêng thất bại, giữ ngưỡng nhận câu và khoảng gốc; yêu cầu hai hàng xóm khớp duy nhất. Connector ngắn cần câu liền kề mạnh hỗ trợ. Bản dựng Nam Cực với Small giữ 255/255 SRT, không mất lời cảm ơn ngoài SRT.
- Thêm sổ bộ nhớ hồi quy trong project và hướng dẫn cho lượt sửa sau, cùng hai nhóm regression mới; 57 nhóm đạt, lịch sử Short/nhãn A–C được giữ. Nghiệm thu Premiere còn chờ; Small vẫn là model phát hành.

## 2.20.73 — 2026-10-18

- Sửa căn từ khi giữ SRT: nếu căn chính xác từng chữ thất bại, thử lại vị trí từ với các biến thể dấu/đơn vị tiếng Việt đã được chính sách nhận câu chấp nhận. Xét bằng ASR và timestamp gốc; không đổi chữ nguồn hay hạ ngưỡng nhận câu.
- Nhận số dạng phân số trong ngữ cảnh câu; không nuốt chữ thường nằm giữa hai số. Giữ nguyên bước chứng minh bỏ nội dung của Auto edit và đường xử lý ngôn ngữ khác.
- Hồi quy cho “hấp thụ ô xy” và hai câu số liền nhau. Bản dựng ngoại tuyến Nam Cực giữ 253/255 câu, tăng từ 250/255; câu 138 và 207 vẫn chưa giải quyết. Chưa nghiệm thu trong Premiere.

## 2.20.72 — 2026-10-18

- Tạo phụ đề thử nhận diện lại từng câu SRT chưa giải quyết khi hai câu liền kề đã xác định được khoảng audio; xét đúng câu thay vì đòi toàn cửa sổ/hàng xóm khớp tuyệt đối. Không phục hồi câu đã bỏ, câu tương lai hoặc câu lặp mơ hồ.
- Giữ SRT khi nhận ra câu chứa số dạng khoảng và đơn vị m/km; không thay giá trị nguồn bằng ASR. Mở rộng ngữ cảnh tám từ cho vài sai khác chính tả gần nhau quanh tên riêng, vẫn giữ chặn chữ không liên quan, số mơ hồ, ngữ cảnh lặp và lời thêm thật.
- Thêm hồi quy từ sáu câu bị bỏ trong lượt Nam Cực và tên Gamburtsev bị chèn lặp; giữ riêng nghiệm thu ngoại tuyến/gói/cài đặt với chạy và nghe thực trong Premiere.

## 2.20.71 — 2026-10-18

- Thêm tùy chọn Phát âm thanh khi hoàn tất hoặc cần xử lý, mặc định bật; giữ lựa chọn tắt đã lưu. Tắt nhắc Windows thì vô hiệu hóa mục âm thanh, không xóa lựa chọn riêng.
- Dùng âm thông báo mặc định của Windows, không lặp, đi cùng toast hiện có. Không có sound player/tiến trình hoặc cửa sổ thông báo thứ hai; tôn trọng âm lượng/quyền thông báo/Không làm phiền của Windows.
- Kiểm lại tùy chọn mới nhất khi helper ready, giữ chống gửi trùng/sự kiện đã xem/callback cũ. Phép thử trong Hỗ trợ dùng thiết lập âm thanh hiện tại.

## 2.20.70 — 2026-10-18

- Bỏ cửa sổ xem riêng, nút/API/lệnh review và lựa chọn tự đưa Premiere lên trước. Chỉ giữ một tùy chọn nhắc Windows; giữ quyền bật/tắt đã lưu, không lấy focus/nháy taskbar tự động.
- Tiến trình và kết quả thay nhau trong cùng vùng panel; phê duyệt là khung trong luồng, không overlay. Sai đầu vào ở đúng trường, cảnh báo/kết quả chỉ có một bản để xem/xử lý.
- Nhắc một lần cho hoàn tất, lỗi, chờ quyết định hoặc dừng xong ở nền. Kết hợp khả năng hiển thị thẻ với cửa sổ Premiere của đúng phiên; đọc kết quả thì dọn toast, ngăn gửi muộn/trùng và callback cũ.
- Helper chỉ nhận loại sự kiện/ngữ cảnh có giới hạn, không nhận bản sao nội dung panel. Bấm toast mở đúng panel, không phê duyệt/chạy lại/Save/Undo. Có phép thử thông báo độc lập trong Hỗ trợ.

## 2.20.69 — 2026-10-18

- Hoàn tất ở nền tuân theo lựa chọn đưa Premiere lên trước. Nếu Windows không cho lấy focus, dùng nháy taskbar có giới hạn và toast; khi tắt tùy chọn focus, vẫn nháy taskbar và gửi toast nếu thông báo ngoài đang bật.
- Toast dùng thời lượng dài; không dùng alarm/reminder hoặc ép topmost. Giữ chốt sự kiện cũ, gửi trùng, chỉ mở panel và không phê duyệt/chạy lại từ thông báo.
- Ghi trạng thái định tuyến, yêu cầu focus và giao nhận native vào log workflow với trường cho phép, không chứa lời nói/đường dẫn media. Không thay thuật toán engine/host.

## 2.20.68 — 2026-10-17

- Báo hoàn tất qua Windows cho cả Dựng theo voice và Tạo phụ đề khi chạy nền, kể cả không có cảnh báo và không phụ thuộc thời gian chạy. Bấm thông báo để mở panel xem kết quả.
- Mỗi kết quả chỉ gửi một lần, không tự giành focus hoặc yêu cầu xác nhận đã đọc. Giữ thông báo ngắn, im lặng, tôn trọng tùy chọn Windows và Không làm phiền.
- Cập nhật nhãn thiết lập; giữ các phản hồi thao tác nhỏ và nhật ký kỹ thuật tại panel. Không thay engine/host hoặc kết quả dựng/phụ đề.

## 2.20.67 — 2026-10-17

- Giữ nhãn một chữ A–Z từ SRT, gồm khác dấu do ASR, khi hai câu SRT liền kề đã nhận ra và khoảng giữa chỉ có một từ khớp chữ với timestamp hợp lệ. Không chuyển A. thành À, hoặc báo C. là lời ngoài SRT chỉ vì câu có một chữ.
- Không chèn nhãn vào khoảng trống, khác chữ, lời thêm, khoảng lặp mơ hồ, thiếu neo hoặc timing sai. Dùng đúng timestamp quan sát được; giữ nguyên bằng chứng cắt hình của Dựng theo voice.
- Kiểm toàn cache lượt chạy Não có phải bộ thu tín hiệu và audio dựng lại quanh hai nhãn; chạy lại workflow để cập nhật caption/marker đã tạo. Nghiệm thu native vẫn chờ người dùng.

## 2.20.66 — 2026-10-17

- Đưa SRT đơn và nối nhiều file vào cùng khung File SRT. Chọn từng SRT Project bằng checkbox, có tìm kiếm; bỏ tự thêm tất cả khi bật nối. Danh sách đã chọn thu gọn, có sắp xếp/bỏ và giới hạn chiều cao.
- Audio mặc định ưu tiên clip audio đang chọn; chỉ chọn video thì ưu tiên phạm vi selection; không có selection thì gợi ý track trên toàn sequence. Giữ lựa chọn nguồn thủ công và chặn selection trống/disabled không thể xác minh.
- Thu gọn các lựa chọn nguồn/phạm vi và danh sách track, vẫn hiển thị nguồn thực tế. Không thay giao thức job/export hoặc thuật toán engine/host.
- Kiểm lại tự chọn SRT ở cả hai luồng: một file hoặc ứng viên ưu tiên rõ được tự chọn, ngang điểm thì chờ người dùng; giữ lựa chọn ASR-only và SRT thủ công. Sửa luồng dựng để file ngoài được chọn tay không bị Project ghi đè khi quét lại trong phiên.

## 2.20.65 — 2026-10-17

- Tách nhật ký kỹ thuật khỏi vấn đề cần hành động; fallback CPU và cleanup đơn thuần không làm kết quả thành cảnh báo.
- Kết quả/lỗi nằm trong luồng giao diện; chỉ quyết định cần phê duyệt dùng hộp thoại. Phản hồi thiết lập, xuất log và chẩn đoán thành công ở cạnh thao tác.
- Danh sách kiểm tra giữ vị trí đầu ra và lý do, gộp lý do cùng phạm vi, đếm vùng chồng nhau một lần; báo rõ khi thiếu marker. Marker gộp hình thông tin không tạo cảnh báo.
- Windows chỉ nhắc tác vụ nền cần xử lý hoặc xem lại; hoàn tất bình thường luôn im lặng. Người mới mặc định không bị chuyển focus, giữ nguyên lựa chọn đã lưu.
- Giao diện Chọn nguồn → Tùy chọn → Chạy; đưa CPU/GPU, lịch sử và hỗ trợ xuống phần phụ. Giữ mọi chốt dừng/tạm dừng, phục hồi và phê duyệt dựng.
- Nghiệm thu native Premiere/Play/Save còn chờ người dùng; kiểm tự động và mô phỏng không thay thế nghiệm thu thực tế.

## 2.20.64 — giữ chữ SRT trong Short và marker ASR cụ thể

- Không để một cụm ngắn ở phần tương lai của SRT phủ nhận toàn bộ các câu đã nhận ra trong Short. Phục hồi câu còn thiếu khi câu sau tạo đủ hai mép; Auto edit giữ chính sách bỏ hình cũ.
- Tránh thêm lặp đuôi ASR sai chính tả của câu SRT đã giữ; kiểm ngữ cảnh dài, duy nhất và không nuốt lời thêm.
- Marker ASR trỏ từng caption và giữ nguyên trích dẫn. Log/thông báo nói rõ khi không giữ được câu SRT nào.
- Đối chiếu toàn bộ 49 caption/3 marker của project Ý thức đến từ đâu; replay cache và kiểm engine trên voice dựng lại. Xem docs/releases/notes/SUBTITLE_TIMING_2.20.64.md; nghiệm thu native còn chờ.

## 2.20.63 — lựa chọn nguồn SRT và ngôn ngữ voice

- Bật nối SRT thì ẩn/khóa lựa chọn SRT đơn hoặc tự nhận diện không SRT; tắt nối khôi phục lựa chọn trước đó.
- Tự thêm tất cả SRT trong Project theo tên file có thứ tự số; cho phép sắp lại/bỏ bớt và thêm lại toàn bộ. Cập nhật đầu vào không ghi đè thứ tự đã sửa.
- Thêm Ngôn ngữ voice cho Dựng theo voice, lưu riêng với ngôn ngữ subtitle. Truyền qua nhận diện chính, CPU fallback, phục hồi câu và căn DTW; chỉ dùng cách đọc số tiếng Việt khi chọn tiếng Việt.

## 2.20.62 — bỏ marker đối chiếu số đọc

- Khi đã nhận ra câu SRT, khác cách ghi số của ASR chỉ lưu chẩn đoán; không tạo marker hoặc cảnh báo hoàn tất riêng.
- Không báo lại “cue SRT cần nghe lại” chỉ vì giữ câu SRT khớp phần lớn, kể cả câu có số.
- Giữ nguyên engine nhận dạng câu, ưu tiên chữ SRT, căn ranh giới bằng từ đứng trước số/đáy âm thanh và phục hồi câu cuối trong Short.

## 2.20.61 — giữ câu có số và câu cuối SRT trong Short

- Nhận dạng câu bằng ngữ cảnh quanh số; giữ nguyên SRT khi số ASR khác, ghi hai cách ghi số trong marker tại caption chứa số. Chuẩn hóa cách ghi nghìn/số thập phân rõ ràng; không tạo marker timing số.
- Phục hồi từng câu trong cửa sổ audio có giới hạn khi phần còn lại của SRT dài vượt ngân sách chiếu cả khối; giữ câu cuối còn khớp trước phần outro. Không đổi bằng chứng cho phép Auto edit bỏ hình.
- Tái hiện hai lỗi bằng project/cache thực của Final vertical: khôi phục SRT 5 và 20, chỉ bổ sung câu “Phần hay nhất…”; chi tiết `docs/releases/notes/SUBTITLE_TIMING_2.20.61.md`.

## 2.20.60 — bỏ marker timing số, chặn chữ ASR lặp ở biên SRT

- Bỏ marker/cảnh báo hoàn tất chỉ vì bước tinh chỉnh timing số không thay mốc; giữ dữ liệu chẩn đoán trong log.
- Chặn từ nghe sai ở đuôi/đầu câu SRT đã nhận ra lọt vào phần bổ sung; neo ngữ cảnh cho phép một biến thể gần chính tả, giữ lời thêm thật và câu lặp mơ hồ.
- Dùng biên caption đã phục hồi, ghi nhận vùng chỉ chứa ngữ cảnh và đặt marker bổ sung theo caption thực, có trích chữ; bỏ nhãn gán cả nhóm cue SRT ứng viên vào một vùng.

## 2.20.59 — nhận ra câu thì giữ chữ SRT

- Subtitle nhận dạng cả câu từ nhiều dấu hiệu, cho phép ASR sai/thiếu/thừa vài từ, sai dấu hoặc khác đầu/cuối; giữ nguyên chữ SRT khi đã nhận ra câu.
- Câu SRT lặp có ngữ cảnh phân biệt vẫn được giữ, kể cả câu lượt đọc lại đã phục hồi nhưng bị bộ dò exact bỏ sót lần cuối.
- Tách nhận dạng câu khỏi xác minh timing, không tạo mốc DTW giả, không đổi điều kiện Auto edit xóa hình. Giữ luật không báo marker giữ chữ SRT của 2.20.58.
- Đối chiếu cùng cache thật: 281/296 cue được nhận ra thay vì 207 theo tiêu chí cũ; không phải số liệu chạy native mới. Chi tiết `docs/releases/notes/SUBTITLE_TIMING_2.20.59.md`.

## 2.20.58 — bỏ marker giữ chữ SRT khớp phần lớn

- Không tạo marker cho lý do “Giữ chữ SRT khớp phần lớn” theo yêu cầu; giữ thông tin chẩn đoán trong báo cáo/log.
- Cảnh báo timing/số và ASR bổ sung vẫn độc lập. Không đổi xử lý chữ hoặc tự sửa project đã lưu.
- Kiểm tra toàn bộ lần chạy 2.20.57 và ghi lại lỗi biên ngữ cảnh còn tồn tại tại `docs/releases/notes/MARKER_AUDIT_2.20.57.md`.

## 2.20.57 — chặn chữ ASR thiếu bằng chứng và sửa cảnh báo timing

- Nhận diện bổ sung kèm ngữ cảnh, chia vùng dài thành cửa sổ có giới hạn; chỉ lấy phần mới và tránh lặp lời đã thuộc câu SRT bên cạnh. Không dùng blacklist nội dung/CTA.
- Chặn giả thuyết quá dày chữ so với âm thanh; khoảng nghỉ ngắn đã đo không bị coi là mất subtitle. Vùng còn thiếu lời vẫn có marker kiểm tra.
- Giữ nguồn/chất lượng timing qua phục hồi; không nâng timing ước lượng thành DTW. Chỉ báo timing ước lượng thực sự dùng trong caption cuối.
- Giữ thêm cue gần khớp trong cụm dài; hỗ trợ cấp độ La Mã/chữ số tương đương và bằng chứng định dạng số thập phân. Không thay điều kiện Auto edit xóa hình hoặc tạo timestamp cho từ thiếu.
- Nhật ký tự lưu bổ sung thống kê và vị trí cảnh báo, không lưu lời nói/đường dẫn media. Chi tiết: `docs/releases/notes/SUBTITLE_TIMING_2.20.57.md`.

## 2.20.56 — giảm chuyển nhầm câu SRT sang tự nhận diện

- Chỉ tạo subtitle giữ chữ SRT khi khớp phần lớn, chỉ thiếu/khác một vài từ và có mốc đầu/cuối đáng tin cậy; đánh dấu cần nghe lại chữ/timing thay vì thay cả câu bằng ASR.
- Chặn câu lặp mơ hồ, mất đầu/đuôi, chỗ nối sát sau cắt, lời nói thêm và timing hỏng. Giữ nguyên bằng chứng/điều kiện Auto edit xóa hình.
- Phân biệt marker cue SRT chưa xác minh với lời nói ở vùng chưa có SRT khớp. Chi tiết và giới hạn tại `docs/reviews/SUBTITLE_REFERENCE_TOLERANCE_2026-10-17.md`.

## 2.20.55 — đối chiếu marker an toàn theo từng nguồn

- Giữ marker clip cũ trong lúc dựng; chỉ dọn phần thừa sau khi cập nhật và đọc lại phần thay thế thành công. Clip và timeline marker dùng chung lõi đối chiếu, giữ marker còn đúng và không ghi lại khi chạy cùng dữ liệu.
- Kiểm chứng kết quả xóa, phát hiện marker nguồn bị sửa trong lúc tạm dừng, thử phục hồi riêng dữ liệu marker khi ghi/xóa lỗi và hiển thị chi tiết phục hồi không đầy đủ.
- Giữ ranh giới hủy giữa các nhóm nguồn trong cả baseline/fast/no-delay; nhóm chưa cập nhật còn marker cũ. Giữ tính dùng chung của marker ProjectItem, không tự Undo, Save hoặc thao tác Premiere.
- Kiểm tự động đạt 46 nhóm, parse 115 script PowerShell; chưa nghiệm thu Premiere. Xem `docs/releases/notes/REVIEW_MARKERS_2.20.55.md` và `docs/reviews/MARKER_RECONCILIATION_2026-10-17.md`.

## 2.20.54 — nối nhiều SRT để nhận diện chung

- Chọn nhiều SRT ngoài hoặc thêm từng SRT trong Project; sắp thứ tự và bỏ file trong panel.
- Nối thành một SRT tạm, đánh lại số cue, giữ nguyên chữ; giữ timestamp gốc hoặc nối tiếp thời gian file sau. Báo file/cue lỗi và mốc chồng nhau trước khi xuất audio/dựng.
- Cả hai chế độ dùng một SRT qua engine hiện có. File gốc giữ nguyên; SRT nối được dọn cùng job.

## 2.20.53 — đối chiếu nguồn audio giữa hai runtime

- Thay so nguyên chuỗi JSON bằng so dữ liệu và frame; tránh từ chối cùng nguồn/phạm vi chỉ vì số thập phân hoặc thứ tự thuộc tính được serialize khác nhau giữa CEP và ExtendScript.
- Giữ kiểm danh tính project/sequence, snapshot, nguồn/track/clip và trạng thái; vùng lệch frame hoặc thay đổi thật vẫn bị chặn trước mutation. Bootstrap kiểm thêm bộ so mới.
- Hồi quy dùng planner CEP riêng với serializer host khác độ chính xác tại 30/29,97/23,976 fps; kiểm nguồn mix/tracks/clips và ca thay đổi thật. Chưa nghiệm thu native.

## 2.20.52 — nạp planner audio và UTF-8 trong Premiere

- Giữ planner trên `$._PVS` qua các lần gọi CEP, không phụ thuộc `this` tạm của eval. Xác minh đủ module/hàm host trước khi báo sẵn sàng; nạp lại host cũ trong phiên.
- Đọc planner/host bằng UTF-8 tường minh để giữ nguyên thông báo tiếng Việt. Chỉ gợi ý đối chiếu Encoding 0% khi lỗi ở bước native export.
- Bổ sung hồi quy bootstrap thực thi mã nguồn với nhiều lượt gọi, thiếu module, lỗi đọc, retry và thông báo tiếng Việt. Nghiệm thu native trong Premiere còn chờ.

## 2.20.51 — voice đã lược bỏ nội dung so với SRT

- Dùng chung đối chiếu trọn cue và nhận diện lại vùng nối; phân biệt cue giữ lại, ASR bỏ sót, vùng đã lược bỏ và vùng chưa chắc. Không đưa SRT vào prompt kiểm tra vùng nối.
- Subtitle giữ chữ phần khớp, bỏ cue không còn đọc; phần câu chưa khớp dùng ASR thực tế, tránh khôi phục cả câu từ ít từ còn lại.
- Auto edit bỏ đúng vùng V1/A1 theo timestamp SRT đã xác minh, bảo toàn hình còn lại và voice. Map nguồn được kiểm trước mutation; cắt hình không bắt buộc tạo thêm điểm cắt A2. Giữ DTW, cân bằng speed và các kiểm tra theo frame.
- Có bước bỏ cặp V1/A1 theo đợt, hỗ trợ Cancel giữ trạng thái đang có. Cue lặp, phần cắt giữa cue và vùng không đủ bằng chứng không tự cho phép bỏ hình. Đã cài bản 2.20.51, chưa nghiệm thu Premiere; xem `docs/releases/notes/EDITED_VOICE_2.20.51.md`.

## 2.20.50 — nguồn audio và phạm vi subtitle tường minh

- Ba nguồn: tất cả track đang bật, một/nhiều track chỉ định hoặc đúng các clip audio được chọn. Phạm vi toàn sequence, thời gian clip được chọn hoặc In/Out; clip mode dùng chính thời gian của các clip audio.
- Gợi ý A2 theo clip enabled giao phạm vi, sau đó track đầu tiên phù hợp. Khi người dùng sửa checkbox, không tự đổi nguồn dù nguồn rỗng/bị xóa; giữ cấu hình theo project/sequence trong phiên.
- Dùng chung resolver cho tóm tắt, job và preflight host; kế hoạch đổi trước chạy được trình bày lại. Selection sau khi chốt job không thay nguồn/phạm vi của job. Bỏ qua và báo riêng vùng không có clip từ nguồn đã chọn.
- Phối nhiều track tại đúng vị trí timeline; clip mode tạm disable clip không chọn trên cùng track và xác minh trước/sau xuất. Không đọc được/không cô lập được thì dừng, không rơi về lấy cả track.
- Lưu nhật ký khôi phục mute/enable/In/Out trước mutation, giữ lại khi khôi phục chưa đạt; có đường phục hồi khi mất phiên trong bộ nhớ và kiểm danh tính/cấu trúc timeline. Bổ sung disabled/source identity vào snapshot pause/export. Kế thừa ưu tiên SRT 2.20.49 và sửa marker 2.20.48; chưa nghiệm thu native trong Premiere.

## 2.20.49 — ưu tiên SRT cho Chỉ tạo subtitle

- Tự chọn SRT trong Project khi chỉ có một file hoặc một ứng viên được xếp hạng cao hơn, dùng cùng danh sách và quy tắc ưu tiên với Dựng theo voice. Nhiều file ngang nhau thì hiển thị hướng dẫn chọn.
- Giữ lựa chọn thủ công, kể cả không dùng SRT, qua cập nhật đầu vào/chuyển chế độ và khi lượt quét đang chờ. SRT tự chọn đã rời Project được xét lại ở lần quét sau.

## 2.20.48 — marker số bám caption chứa số

- Sửa lỗi marker cảnh báo số đặt tại đầu cả đoạn phân tích dài; chỉ đánh dấu các caption đầu ra thực sự chứa chữ số và thuộc đoạn cần kiểm tra. Ghi số, nguyên văn caption, số caption đầu ra và cue SRT nguồn khi có.
- Giữ ánh xạ đoạn phân tích sang caption sau chia nhỏ. Không coi thất bại của bước xác minh timing là kết luận đọc sai số; không đặt marker nếu không ánh xạ được caption chứa số.
- Gói cập nhật kế thừa 2.20.47 và chỉ đưa sửa marker vào; các thay đổi chưa phát hành về nguồn audio/phạm vi và tự chọn SRT vẫn ở working tree, không đưa vào gói.

## 2.20.47 — marker dùng chung tại các mốc cần kiểm tra

- Gắn marker sequence cho cảnh báo đọc số/DTW/timing ước lượng, xung đột căn voice/caption, độ tin cậy thấp, SRT khác nhận diện, vùng lời nói bổ sung/dự phòng/trống và lỗi hậu kiểm có vị trí xác định.
- Dùng vị trí timeline cuối sau DTW/gộp hình; áp dụng cho Auto edit, cả ba profile dựng chẩn đoán và Chỉ tạo subtitle. Giữ marker người dùng, phân biệt workflow/phạm vi, gộp lý do cùng frame và báo lỗi tạo marker riêng.
- Sửa cue trùng số khi nhận diện nhiều vùng rời nhau. Thêm kiểm mô phỏng mapping/ownership/API và marker trong các workflow host. Xem `docs/releases/notes/REVIEW_MARKERS_2.20.47.md`; chưa nghiệm thu trong Premiere thật.

## 2.20.46 — phục hồi mép câu trước khi nhận diện subtitle bổ sung

- Sửa lỗi `CAPTION_OVERLAP_TIMING_UNSAFE:240:9` khi cue tham chiếu thiếu từ cuối, nhận diện bổ sung chạy trước rồi DTW phục hồi cùng đoạn lời nói.
- Hoàn tất timing DTW của cue tham chiếu trước khi tìm vùng bổ sung; dùng chính mép caption đã phục hồi để xác định vùng chưa có subtitle. Giữ lời ngoài SRT/CTA, chữ và timecode SRT nguồn.
- Quy đổi chỉ số cue trong báo cáo DTW sau khi chèn phần bổ sung; tiếp tục chặn timing không hợp lệ và caption chồng nhau, không nới ngưỡng an toàn.


## 2.20.45 — dùng timing âm học cho Auto edit

- Dùng chung DTW theo cửa sổ, phục hồi cục bộ và RMS đáy sóng âm với Chỉ tạo subtitle; áp dụng cho nhận diện caption chính và retry mép/số của Auto edit.
- Cue có mapping đầy đủ, đủ khớp chữ, mép có neo và timing hợp lệ được cập nhật Start/End/WordTimings trước planner. Điểm cắt và speed dựng có thể đổi theo mốc mới; không khóa điểm cắt của bản cũ.
- Giữ nguyên chữ và timecode SRT nguồn video. Cue ước lượng không được dùng làm chứng cứ DTW cắt dựng; xung đột với cue chưa xác minh chỉ làm giữ mốc dự phòng cục bộ.
- Quy đổi speed/offset sau đo PCM nguồn, giữ kiểm bảo toàn frame nguồn và toàn bộ voice. Lỗi native không bị che thành fallback timing. Giữ phép đo Encoding và điều khiển workflow của 2.20.44.

## 2.20.44 — đo chẩn đoán Encoding 0%

- Ghi riêng tổng thời gian panel chờ, timer CEP và thời gian host/native/finalize của phiên xuất WAV.
- Giữ phép đo khi native ném lỗi; logger lỗi không làm hỏng workflow. Không ghi tên media/nội dung lỗi vào log tự động.
- Không đổi preset, thời gian nhường 100 ms, ASR/căn subtitle, điều khiển dừng/tạm dừng hoặc thuật toán dựng. Chưa xác nhận nguyên nhân hoặc hết kẹt 0%.

## 2.20.43 — căn ranh giới subtitle theo audio, phục hồi DTW cục bộ

- Chỉ tạo subtitle chia vùng kiểm DTW ở khoảng nghỉ, tối đa 26 giây; nhận diện lại riêng cửa sổ lỗi. Giữ timing theo từ ở các cửa sổ tốt, không hạ cả audio dài sang timestamp cấp câu.
- Dùng envelope RMS 5 ms để tìm đáy năng lượng tương đối quanh token cuối của từ đứng trước ranh giới; tránh kéo ranh giới vào giữa số có nhiều âm tiết. Giữ khoảng thở đo được và giới hạn tìm kiếm có neo.
- Vùng vẫn thiếu DTW sau retry chỉ dùng timing ước lượng cục bộ và báo vị trí cần kiểm tra. Log hiệu năng giữ chế độ timing, số vùng retry/ước lượng và số ranh giới đo được, không lưu lời nói hoặc đường dẫn media.
- Thêm kiểm hồi quy timing cục bộ, ranh giới trước số, đáy sóng chưa xuống ngưỡng im lặng, âm phẳng và PCM lỗi. Không đổi planner, điểm cắt, timing Auto edit hoặc host Premiere. Xem [bằng chứng và giới hạn](docs/releases/notes/SUBTITLE_TIMING_2.20.43.md).

## 2.20.42 — giữ SRT đã căn tốt khi một nguồn không khớp

- Subtitle fallback theo từng nguồn, giữ chữ/timing SRT hợp lệ của nguồn khác. Ghi lý do mismatch/partial/ambiguous/order/no-speech; lỗi kỹ thuật vẫn dừng như trước.
- Nguồn ASR ban đầu rỗng có thể được nhận diện lại khi có SRT; vùng vẫn rỗng được báo lại, không nội suy chữ SRT.
- Kiểm timing dùng chung cho phục hồi và xác nhận subtitle: từ chối NaN, Infinity, khoảng bằng 0, đảo/chồng hoặc vượt nguồn. Giữ thuật toán căn toàn bài, nội suy và planner Auto edit.
- Thêm các ca nhiều nguồn, rỗng, lặp/đảo thứ tự và timestamp lỗi; đối chiếu Auto edit với baseline. Xem [rà soát cơ chế](docs/reviews/ALIGNMENT_REVIEW_2026-10-15.md). Chưa nghiệm thu trong Premiere thật.

## 2.20.41 — lõi căn SRT/voice dùng chung

- Tách parser ASR, lexical layout, mapper, gán timing cho cue và phục hồi cue thiếu sang ReferenceAlignment.ps1. Auto edit và subtitle gọi chung; giữ chính sách timing/scope riêng theo workflow.
- Subtitle dùng phục hồi cue thiếu của Auto edit trước bước nhận diện bổ sung. Giữ chữ SRT khi khớp đủ; phần còn lại và lời ngoài SRT/CTA vẫn nhận diện và ghép chung như 2.20.40.
- Giữ thuật toán dựng/timeline Auto edit; 100 ca đối chiếu toàn bộ kết quả căn với snapshot 2.20.40. Thêm kiểm phục hồi chung, parser và offsets/indices, gói cài bắt buộc có lõi mới.
- Ghi cue được phục hồi; giữ số cue SRT gốc trong báo cáo xét duyệt sau khi gộp. Chưa nghiệm thu trong Premiere thật.

## 2.20.40 — SRT dài và nhận diện bổ sung trong chế độ chỉ tạo subtitle

- Thay ma trận truy vết toàn bộ bằng checkpoint và truy vết từng khối; bỏ chặn cố định 25 triệu ô trong bước chọn đoạn SRT của caption-only.
- Giữ recurrence, tie order và near-best endpoints. Phần khớp dùng chữ SRT; phần thiếu/khác SRT và lời nói ngoài SRT (gồm CTA) được nhận diện bổ sung, gộp vào cùng SRT/caption. Không gán timestamp SRT cũ để đoán timing.
- Nhận diện lại bằng đoạn câu khi DTW đầu vào không hợp lệ; lượt bổ sung không tách từng từ hoặc dùng prompt chữ SRT. Không tìm được scope tham chiếu an toàn thì dùng ASR cho audio được chọn. Báo khoảng bổ sung và khoảng không nhận diện được lời trong log/thông báo cuối.
- Kiểm bộ nhớ dự tính trước cấp phát, gồm các mapping ứng viên, với ngân sách 128 MiB cho dữ liệu chính của bộ so khớp. Giới hạn 25 triệu của hàm căn cũ không thuộc luồng caption-only hiện tại vẫn giữ nguyên.
- Thêm đối chiếu 120 mẫu với oracle toàn ma trận; các ca 36 triệu ô toàn bài, 30 triệu ô đoạn giữa và 60 triệu ô nội dung lặp. Chưa nghiệm thu import/Play/Save trong Premiere.

## 2.20.39 — tạm dừng và tiếp tục ở điểm an toàn

- Thêm Tạm dừng/Tiếp tục dùng chung hai chế độ: chờ script nhận diện, toàn phiên export audio hoặc lượt dựng hiện tại kết thúc trước khi nghỉ. Không suspend tiến trình hay chạy lại ASR đã xong.
- Chụp trạng thái chỉ đọc khi nghỉ và so sánh trước tiếp tục: project/sequence, các clip video/audio, nguồn, timing/speed, mute, In/Out, bin gốc và số Caption Track khi API cung cấp. Thay đổi/lỗi đọc chặn tiếp tục, giữ khóa phục hồi.
- Dừng vẫn dùng được khi đang nghỉ/đang kiểm tra tiếp tục; lỗi giao diện đánh thức luồng chờ để cleanup. Không tự tiếp tục khi mở lại panel. Không sửa thuật toán dựng hoặc lịch no-delay.
- Log riêng thời gian tạm dừng, loại khỏi processingMilliseconds và thời gian xử lý stage. UI tổng thời gian vẫn bao gồm thời gian nghỉ.
- Thêm kiểm thử luồng pause/resume, helper host thật qua VM và bố cục đang nghỉ. Cần nghiệm thu Premiere thật.

## 2.20.38 — dừng tác vụ đang chạy

- Thêm Dừng tác vụ dùng chung cho Auto edit/Caption-only, giữ khóa đến khi host/engine trả về và cleanup xong; bấm lặp không gửi lệnh lặp.
- Mỗi engine chạy trong Windows Job Object riêng với bước chờ trước khởi động; hủy kết thúc và chờ mọi tiến trình con thoát, không tìm/kill theo tên hoặc PID của ứng dụng khác.
- Dừng ở ranh giới lượt Premiere; abort phiên dựng, khôi phục mute/In/Out khi xuất audio, chặn lượt dựng/import tiếp theo. Không tự Undo/Save. Timeline đã thay đổi/chưa xác minh giữ khóa phục hồi.
- Log phân biệt cancelled với success/failed; lỗi engine/khôi phục vẫn báo lỗi. Hủy không tự gọi toast/focus.
- Thêm test giao diện và tiến trình Windows thật. Nghiệm thu native Premiere còn chờ; không cam kết ngắt tức thì lệnh encoding/import đang bận.

## 2.20.37 — tách chuẩn bị audio khỏi lượt encoding

- Tách begin/advance/abort; trả quyền điều khiển về Premiere và nhường CEP 100 ms trước mỗi lần xuất WAV.
- Mỗi lượt chỉ xuất một vùng; kiểm snapshot/mute/In/Out/project giữa các lượt và chặn token/lượt trùng.
- Khôi phục khi lỗi/hủy; thao tác kiểm tra đầu vào hỗ trợ phục hồi phiên host dang dở khi panel mở lại.
- WAV thủ công được người dùng xác nhận chạy ngay. Chưa nghiệm thu native cho bản sửa; cơ chế audio graph chưa kịp cập nhật vẫn là giả thuyết cần kiểm chứng. Xem docs/releases/notes/NOTIFICATIONS_2.20.37.md.

## 2.20.36 — kiểm tra kết quả xuất WAV và chẩn đoán encoding

- Chặn giá trị lỗi/hủy native kể cả WAV dở dang; giữ khôi phục mute/In/Out.
- Kiểm phạm vi hữu hạn và In/Out trước export, dùng rõ workAreaType=1.
- Log đúng phiên bản và mã giai đoạn xuất lỗi; nói rõ xuất WAV khóa tương tác Premiere.
- Chưa xác minh nguyên nhân hoặc khắc phục kẹt 0% trong Premiere; cần so sánh xuất WAV thủ công cùng vùng. Xem docs/releases/notes/NOTIFICATIONS_2.20.36.md.

## 2.20.35 — chỉ lấy track voice khi tạo subtitle

- Thêm chọn track voice cho Chỉ tạo subtitle, mặc định A2 hoặc A1 nếu chỉ một track audio. Giữ lựa chọn khi đọc lại cùng sequence, đặt lại khi đổi sequence; track trống/không còn tồn tại cần chọn lại.
- Xuất WAV chỉ từ track đã chọn bằng cách lưu mute toàn bộ track audio, tạm mute các track khác/bật voice, rồi khôi phục từng track và In/Out trong finally. Xác minh cô lập trước/sau xuất; lỗi khôi phục giữ cả lỗi gốc và chi tiết track, dừng trước nhận diện/import.
- Hồi quy mock kiểm chọn track, dữ liệu job, voice vốn mute, nhiều vùng, lỗi xuất/thiết lập/khôi phục và timeline cũ. Không thay nhận diện/căn timestamp hoặc executor dựng; cần nghiệm thu âm thanh, routing, caption và Play/Save trong Premiere thật. Không tách được nhạc trộn sẵn trên track voice.

## 2.20.34 — sửa kiểm tra caption-only khi CEP thiếu captionTracks

- Không đọc thẳng `sequence.captionTracks.numTracks` khi Premiere không cung cấp collection này. Lưu số caption là chưa biết, không giả định bằng 0; vẫn kiểm In/Out, bin tạm, sequence và snapshot video/audio trước import.
- Nếu lỗi sau thao tác có thể đã sửa Project và không thể đếm caption, giữ khóa chạy lại đến khi người dùng xác nhận kiểm tra caption thủ công, rồi vẫn đối chiếu các trạng thái đọc được. Giữ chi tiết lỗi host khi đọc trạng thái thất bại.
- Thêm hồi quy chạy biểu thức host thật với API thiếu/có/sai, In/Out không hợp lệ, sequence đổi, luồng SRT và phục hồi sau lỗi. Không đổi engine nhận diện/căn chữ hay executor dựng.

## 2.20.33 — áp dụng kênh thông báo theo tình huống

- Dùng kết quả bộ định tuyến để chọn hiển thị thật: lỗi SRT/tham số/ngôn ngữ hiện cạnh trường và mở vùng tùy chỉnh cần sửa, không thêm popup; lỗi chưa sửa timeline hiện banner, lỗi đã ảnh hưởng/không rõ kết quả hoặc fatal mới mở hộp nổi bật. Xác nhận vẫn cần lựa chọn rõ ràng.
- Phân biệt hoàn tất có cảnh báo với cảnh báo trong tiến trình. Tác vụ dài ở nền có toast kể cả khi kèm cảnh báo; trường hợp cần người nghe/kiểm tra báo cả khi tác vụ ngắn, không lấy focus.
- Bấm toast chỉ yêu cầu mở panel. Cửa sổ xem riêng mở khi người dùng chọn rõ; nút quay về panel đóng cửa sổ xem trước để tránh hai nơi tranh focus.
- Giữ xác minh sau lỗi, ID phiên/lượt/sự cố và giới hạn thông báo. Kiểm thử bằng mock/dữ liệu, không điều khiển giao diện Windows.

## 2.20.32 — ứng viên gia cố thông báo, kiểm thử không điều khiển Windows

- Chặn dữ liệu null/sai schema trước khi xử lý trong helper và bridge; lỗi kênh thông báo không được làm phát sinh lỗi bất ngờ trong luồng tác vụ. Bỏ dữ liệu đến sau khi bridge đã dừng.
- Tắt toast có hiệu lực khi đang chờ focus/handshake và ẩn toast hiện tại, vẫn giữ sự cố để xét duyệt trong panel. Callback của toast đã ẩn bị vô hiệu hóa.
- Thêm bộ kiểm schema C# thuần và chế độ `tests/Run-Tests.ps1 -NoWindowsIntegration`; không gọi helper native, registry hoặc shortcut trong chế độ này. Không nghiệm thu GUI/Windows hoặc cài thay panel đang dùng trong lượt gia cố.

## 2.20.31 — ứng viên tích hợp thông báo nhiều kênh

- Lỗi SRT có dấu báo tại trường nhập; trạng thái, cảnh báo và xác nhận tiếp tục giữ trong panel. Thêm nút cửa sổ xem riêng không khóa Premiere, đóng cửa sổ không chấp thuận tác vụ.
- Windows toast im lặng cho lỗi/xét duyệt khi chưa đưa được panel ra trước và kết quả tác vụ dài ở nền. Tùy chọn bật/tắt riêng, không vượt cài đặt Không làm phiền. Không gửi toast trùng khi panel đã có focus.
- Helper WinForms/WinRT dùng ống giao tiếp riêng, gắn PID cha, phiên/lượt/sự cố; kiểm SHA256 trước chạy. Callback cũ không được mở sự cố đã đóng hay lượt mới, không thực thi thao tác dựng từ toast.
- Setup quản lý shortcut AUMID riêng, kiểm quyền sở hữu và khôi phục nguyên byte nếu lỗi cài. Cung cấp mã nguồn helper trong gói. Không thay bản 2.20.30 đang cài; còn cần nghiệm thu trong Premiere thật.

## 2.20.30 — thông báo và xử lý sự cố, chờ nghiệm thu native

- Lỗi và xét duyệt hiện giữa panel, ưu tiên thao tác an toàn; thành công/cảnh báo không chặn. Gộp lỗi trùng, giữ lỗi chính, chi tiết mở rộng và lịch sử metadata 30 thông báo/30 ngày.
- Thử kích hoạt đúng panel/Premiere qua CEP và helper Windows chỉ tìm tiến trình tổ tiên; một lần mỗi sự cố, timeout, taskbar fallback và tùy chọn tắt. Không gửi phím hoặc đặt cửa sổ luôn trên cùng.
- Theo dõi ảnh hưởng trước/sau thao tác, khóa chạy lại nếu đã ghi hoặc chưa rõ kết quả; xác minh template hoặc caption/In/Out/bin tạm sau khôi phục. Dấu phiên gián đoạn chỉ lưu loại tác vụ/thời gian, cần kiểm tra thủ công khi mở lại panel.
- Kết quả cuối đợi cleanup; có cue cần nghe lại/GPU fallback/lỗi dọn file thì báo cần kiểm tra. Bắt lỗi giao diện/Promise chưa xử lý; tác vụ lâu chỉ báo chưa có phản hồi, không tự timeout/retry ghi timeline.
- Giữ thuật toán, engine nhận diện và executor dựng của 2.20.27. Chưa cài panel thật, chưa nghiệm thu foreground/taskbar/Preview/Play/Save của bản mới.

## 2.20.25 — 2026-10-08

- Người dùng xác nhận bản đã cài hoạt động tương đối ổn, không còn lỗi được báo, không đơ và Save bình thường; đồng ý gộp PR #9 và phát hành. 35 nhóm hồi quy/88 PowerShell parse và CI đạt. Không coi một lần nghiệm thu là bảo đảm mọi project/máy.

- Quét SRT khi khởi động/Đọc lại không còn phụ thuộc sequence vượt kiểm tra template Auto edit. Sequence đã dựng, không có sequence hoặc thiếu A2 vẫn liệt kê được SRT trong Project; giữ nguyên guard trước dựng.
- Bỏ placeholder báo đang tìm khi chưa bắt đầu quét. Không đổi nhận diện, timestamp caption, điểm cắt/speed/marker hoặc native executor.
- Hồi quy tái hiện đường gọi cũ bỏ qua quét khi sequence không hợp lệ, kiểm startup/Đọc lại và ba trường hợp sequence không sẵn sàng. 2.20.24 đã được người dùng xác nhận dựng/caption, Preview và Save bình thường; lỗi quét trên sequence đã dựng vẫn còn, không coi là nghiệm thu hoàn toàn.

## 2.20.24 — candidate, chưa nghiệm thu native

- Quét SRT theo từng nhóm tối đa 64 ProjectItem/40 ms, chỉ duyệt children của bin; chặn vòng lặp, đổi project và lượt gọi trùng. Không truy cập ổ đĩa đồng bộ chỉ để lập danh sách SRT; giữ lựa chọn người dùng nếu đổi file trong lúc chờ.
- Timeout 30 giây riêng cho đọc danh sách SRT, hiển thị lỗi thay vì chờ mãi. Không retry native read chưa trả lời, bỏ qua kết quả trễ. Không thêm timeout vào dựng/import hoặc hủy thao tác native.
- Caption DTW trong Auto edit ánh xạ theo frame qua các lát A2 đã lập kế hoạch, không clamp vào nhóm câu legacy sai. Giữ điểm cắt, nguồn, speed, duration, caption text và marker. Lát 1 frame trùng nguồn được bỏ khỏi riêng chỉ mục ánh xạ caption, không xóa A2. Xung đột với caption bên cạnh giữ mốc cũ và báo cue cần nghe lại.
- Tái hiện chính xác timestamp lỗi 96–97 trong SRT xuất. Hồi quy quét Project/bounded read/timeout, frame mapping và trường hợp caption nằm trong lát voice của câu trước. Không cài panel/main/Release chỉ từ kiểm thử tự động.

## 2.20.23 — candidate, chưa nghiệm thu native

- Tăng tốc lexical mapping bằng cùng edit-distance và tie rules, rolling cost rows + compiled loop. Giữ PowerShell tham chiếu cho cửa sổ nhỏ, kiểu dữ liệu ngoài fast path và máy không chạy được accelerator. Không thay ASR/DTW hoặc mốc bằng heuristic.
- 450 ca mapping đối chiếu, dữ liệu ASR thật 305 cue ở 30/29.97 fps và profile voice 90/110/125% cho cùng toàn bộ cue JSON. Phép đo riêng căn cue khoảng 24,5 → 1 giây, không phải benchmark toàn workflow.

- Bảo toàn khoảng không lời ở đầu/giữa/cuối khi ngưỡng giây làm tròn sang frame; bỏ kiểm ngưỡng trùng và kiểm partition trước khi chạm Premiere.
- Căn cue chỉ duyệt đúng phần từ của cue thay vì quét toàn bộ từ hai lần; giữ mapping và đối chiếu kết quả với 2.20.22.
- Cache không khởi tạo được, cleanup cache tạm bị khóa và log hiệu năng không ghi được không làm mất kết quả thành công. Giữ thời gian tạm ngừng CUDA sau lỗi runtime qua nhiều lượt resolve.
- Không làm mất đối số native rỗng. Đọc SRT có khoảng trắng ở dòng trống/giờ một chữ số, từ chối cue lỗi thay vì âm thầm bỏ qua.
- Thêm hồi quy và tài liệu rà soát; tách kiến trúc hiện tại khỏi lịch sử. Không đổi executor native, không cập nhật panel/main/Release chỉ từ test cục bộ.

## 2.20.10 (bản chẩn đoán, chưa nghiệm thu hết lag)

- Người dùng xác nhận 2.20.9 vẫn đơ Preview/Play/Save. Không coi guard openSequence là nguyên nhân đã được xác minh; không tự lưu hay xóa Undo để thử chữa.
- Thêm nút dựng chẩn đoán riêng dùng kế hoạch ổn định. Các vòng cắt/speed/move/voice/marker chạy qua nhiều evalScript, nhường lượt bằng timer CEP; một cặp V1–A1 không bị tách giữa hai đợt. Host ổn định và toàn bộ engine giữ nguyên.
- Dừng tùy chọn sau hình, voice, marker, caption để người dùng thử Preview/Play. Dừng khi lag không Undo và không hoàn thiện timeline một phần. Có kiểm sequence/fingerprint giữa đợt, session/token/call-order, tái ánh xạ reference và không retry thao tác native.
- Sinh executor ES3 cơ học từ host ổn định, kiểm hash/freshness và đối chiếu đầy đủ native call/report trên mock. Log hiệu năng cục bộ chỉ ghi bước/thời gian/trạng thái, không có media/transcript. Không đưa raw dump vào ZIP hoặc GitHub. Chưa merge main/Release.

## 2.20.9 (bản thử, tránh mở lại sequence đang hoạt động)

- Cuối Auto edit, không gọi `openSequence` nếu sequence gốc vẫn đang hoạt động. Nếu đã chuyển sang sequence khác hoặc không còn sequence mở, vẫn khôi phục sequence gốc và giữ cách báo lỗi cũ.
- Không đổi ASR/DTW, điểm cắt, speed, nguồn hình/voice, caption, marker hay hậu kiểm. Kế thừa giới hạn một cặp của 2.20.8.
- Thêm mock hồi quy cho cùng ID, ID khác, không có sequence, lỗi khôi phục và lỗi preflight. Đây là bản thử để kiểm chứng hiện tượng preview/save bị chậm; chưa xác nhận hết lag trong Premiere, không tự gộp main/Release.

## 2.20.8 (bản thử, chỉ gộp một cặp liền kề)

- Chỉ gộp một lần với một hàng xóm tốt hơn; khóa cặp đã gộp dù đã đạt hay vẫn ngoài ngưỡng. Đoạn khác không được hấp thụ cặp đó để gián tiếp tạo gộp chuỗi. Nếu còn ngoài ngưỡng, giữ marker cảnh báo V1.
- Giữ cách tính thử hai phía theo frame, cho phép chapter liền nhau, bảo toàn A2/caption/hình/thời lượng và rào chắn không lời. Đổi protocol thử sang `adjacent-speed-v2`; cả planner và host chặn nhóm hơn hai đoạn đầu vào.
- Thêm hồi quy dưới/trên ngưỡng vẫn dừng sau một lần, cặp đạt không bị tái sử dụng, từ chối kế hoạch v1/gộp ba đoạn, giới hạn pair ở 80 ca frame. Nút dựng ổn định không đổi; chưa nghiệm thu timeline Premiere.

## 2.20.7 (bản thử, gộp hình cân bằng tốc độ)

- Thêm lựa chọn thử riêng, mặc định tắt và không lưu: gộp V1–A1 với hàng xóm để đưa tốc độ gần dải cảnh báo hơn. Tính thử hai phía theo frame, lặp khi cải thiện, dừng khi đạt ngưỡng hoặc không còn phương án tốt hơn. Cho phép qua chapter liền nhau, không vượt đoạn không lời/khoảng hở voice.
- Giữ nguyên A2, tốc độ voice, mọi điểm cắt voice an toàn, caption, marker căn voice, hình nguồn và tổng thời lượng. Kế hoạch hình `visualSegments` tách riêng khỏi kế hoạch voice `segments`; không nối các file voice của hai chapter. Marker speed vẫn gắn clip V1 bằng chỉ mục kế hoạch hình.
- Bổ sung kiểm bảo toàn ở planner và kiểm hình trước mọi mutation trong host. Nút dựng ổn định, ASR, căn caption và planner revision 18 không thay thuật toán. Đây là thuật toán gộp cục bộ, chưa nghiệm thu timeline Premiere; chưa gộp main/Release.

## 2.20.6 (bản thử, sửa chốt speed voice)

- Bỏ yêu cầu voice 100% thừa trong chốt thử DTW; giữ speed đã đặt của từng chapter và tái dùng quy đổi word/quiet 100/speed hiện có. Không đổi speed voice, planner ổn định hoặc executor. Giữ chốt media In 0 vì chưa hỗ trợ offset voice trim đầu.
- Kiểm đầu vào trước ASR bằng `-ValidateOnly`, không nhận diện xong mới từ chối. Lỗi nêu chapter/media In/speed, không kiểm nhầm CTA nằm ngoài nhóm voice chính.
- Thêm hồi quy speed chậm/nhanh, sai số số thực, metadata lỗi, CTA scope và UI dừng trước ASR; kiểm media riêng với tốc độ đều/khác nhau theo chapter. Chưa nghiệm thu timeline DTW trong Premiere.

## 2.20.5 (bản thử, chưa nghiệm thu timeline DTW)

- Thêm mục Auto edit DTW riêng, mặc định tắt, không lưu lựa chọn. Nút dựng thường, nhận diện, caption-only, planner revision 18 và executor 25 giữ nguyên.
- Lập kế hoạch ổn định trước rồi chỉ thêm điểm cắt giữa câu có bằng chứng DTW đầy đủ và khoảng lặng có biên an toàn; không dùng padding caption. Giữ điểm cắt cũ, bảo toàn hình nguồn/voice/chữ caption/thời lượng/khoảng không lời; không đạt thì dừng trước khi dựng.
- Hai xác nhận riêng: bắt đầu phân tích và duyệt kế hoạch trước khi gọi executor. Không có điểm cắt mới thì giữ timeline; kiểm lại template trước khi dựng. Giới hạn bản thử ở chapter voice có media In 0, tốc độ 100%.
- Tái dùng một lõi DTW thử nghiệm cho harness offline và panel, không import thư mục experiments vào runtime. Bổ sung hồi quy opt-in, hủy/dừng, template đổi, bảo toàn và exact allowlist cho ZIP. Không gộp main hoặc tạo Release chính thức.

## 2.20.4 (người dùng đã nghiệm thu hoạt động)

- Đưa cách căn caption DTW đã nghiệm thu trên SRT thử nghiệm vào thư viện `CaptionTiming.ps1` dùng chung cho Auto edit và Chỉ tạo subtitle. Giữ mốc token trước từ khi chuyển caption vì giới hạn ký tự; không dịch cố định 5 frame. Dấu câu và khoảng nghỉ thật không bị bù thời gian theo cách đó.
- Không bỏ từ trong segment Whisper SOW có duration bằng 0 nếu token DTW vẫn hợp lệ. Giữ giới hạn một dòng, cụm từ và padding tối đa 5 frame không overlap.
- Auto edit dùng recognition/cache DTW riêng cho caption; giữ nguyên timestamp dựng, nhóm câu, đoạn V1/A1/A2, tốc độ và executor. Chapter không xác minh được DTW giữ đường căn cũ, không làm lệch mapping chapter kế bên; nhật ký báo lý do và cue cần nghe lại.
- Giữ đường chia theo ký tự hiện có cho Trung/Nhật. Không tải thêm model hoặc bật GPU ngoài chính sách hiện có. Timestamp DTW vẫn cần nghe lại, không bảo đảm chính xác tuyệt đối.

## 2.20.3 (bản thử, chờ nghiệm thu Premiere)

- Khắc phục khoảng nghỉ sau “Engineer” đã được FFmpeg phát hiện nhưng bị loại vì mép từ Whisper lệch: chỉ nhận sai lệch có giới hạn ở mép từ, không chuyển mọi điểm sóng thấp thành chỗ nghỉ. Ưu tiên gán khoảng nghỉ dấu câu trước để không làm caption chứa “chúng ta” biến mất ngay sau “Hôm nay,”. Áp dụng chung hai quy trình, giữ nguyên mốc dựng video/voice và ngưỡng phân tích audio hiện tại.
- Loại đối số tên executable dư trong response file của Whisper; giữ nguyên truyền prompt UTF-8 và tự dọn file tạm.
- Bảo vệ tên có chữ cái viết tắt như “H. R. Giger”, “H.R. Giger”, “J. R. R. Tolkien”: dấu chấm trong tên không kết thúc caption hoặc cue ASR; giữ chuỗi chữ viết tắt và họ trong cùng caption. Không sửa các mốc dựng video/voice.

## 2.20.2 (đang nghiệm thu)

- Dấu phẩy/chấm phẩy/hai chấm không buộc tách thành mảnh 1–2 từ; giữ tên Latin như “Alien: Covenant” nguyên cụm khi phù hợp giới hạn ký tự. Dùng chung cho Auto edit và Chỉ tạo subtitle.
- Nới caption tối đa 5 frame mỗi mép khi còn chỗ, không chồng caption kề bên.
- Kiểm tra/căn riêng caption quanh mọi cue có chữ số bằng cửa sổ ASR ngắn; giữ nguyên số hiển thị và toàn bộ mốc dựng video/voice. Không đủ căn cứ thì báo cue cần nghe lại, không đoán timestamp. Không bật DTW thử nghiệm.
- Sửa truyền prompt tiếng Việt sang Whisper trên Windows bằng response file đúng bảng mã; tự xóa file đối số. Đối chiếu thêm số viết bằng chữ/chia nhiều token với số tham chiếu, không tự đổi giá trị hoặc chữ caption. Timestamp vẫn cần nghiệm thu nghe thực tế.

## 2.20.1 (bản thử)

- Chỉ tạo subtitle tự tìm phần SRT tương ứng với từng vùng audio, báo rõ cue đã dùng và cue ngoài vùng; giữ chữ SRT, căn bằng timestamp lời nói thực tế, không dùng timecode cũ để chọn phạm vi.
- Nhận diện lại tối đa một cửa sổ đuôi ngắn khi ASR vượt mép audio hoặc bỏ sót phần cuối; từ chối nếu vẫn chưa xác minh được thay vì âm thầm bỏ cue. Caption dùng frame bên trong mép clip audio sample-based, tránh lỗi vượt vùng do làm tròn.
- Từ chối phạm vi mơ hồ do nội dung lặp, audio cắt giữa cue, thiếu cue bên trong hoặc thứ tự các vùng bị đảo/chồng. Không thay Auto edit hoặc âm thanh/hình ảnh trên timeline.

## 2.20.0 — 2026-10-06

- Auto edit nhận diện lại vùng ngắn có cue bị Whisper bỏ sót, dựa trên mốc neo cùng chapter; chỉ nhận kết quả đủ word timestamp và độ khớp cao. Khắc phục lỗi chia caption ở cue 303–305 của video tàu vũ trụ, không thay thuật toán dựng hoặc remap cue đã khớp.
- Hòa lại ranh giới caption chồng đúng 1 frame do thời lượng tối thiểu sau khi giới hạn theo điểm cắt voice; giữ đủ chữ, không sửa các điểm cắt video/audio, không tự sửa chồng lấn lớn hơn.
- Sửa báo lỗi giả ở chức năng subtitle độc lập khi SRT có "Be…" nhưng Whisper ghi "b", hoặc sai dấu ở cue ngắn như "đùa"/"đua". Chỉ chấp nhận biến thể tiếng Việt có timestamp đủ, mốc neo mạnh hai phía, block ngắn và không vượt khoảng chọn; giữ chữ SRT/timestamp, báo cue cần nghe lại. Không hạ ngưỡng toàn bộ SRT hoặc đổi thuật toán dựng.
- Siết bảo mật ZIP: checksum bắt buộc, exact allowlist, chặn junction/symlink, xác minh runtime/DLL theo hash cố định và rollback khi cập nhật panel lỗi.
- Tải GPU cần đồng ý, mặc định tắt; không dùng binary tìm qua PATH hoặc tải runtime latest không khóa hash.
- Thêm xóa cache nhận diện và xuất log đã che thông tin; gỡ chỉ đúng ID và vùng dữ liệu sở hữu. Giữ nguyên thuật toán dựng/chia caption.
- Tách thử nghiệm ký CEP khỏi production; ZIP hiện tại vẫn chưa ký, không tuyên bố bảo mật tuyệt đối.
- Chuyển sang phân phối ZIP duy nhất với Setup-Panel.cmd/Remove-Panel.cmd, không đăng ký Windows Installed apps hoặc tạo Setup.exe. Chuyển từ bản cũ giữ cache/model/backend.
- Thêm chức năng Chỉ tạo subtitle: clip đang chọn hoặc toàn sequence, không cần template hay dựng lại video.
- Dùng audio thực tế của sequence, tự nhận diện ngôn ngữ/lời nói hoặc căn SRT có sẵn; thêm Caption Track mới và tự dọn file tạm.
- Tái sử dụng alignment và cách chia caption tiếng Việt của 2.19.9, giữ padding tối đa 3 frame; bổ sung xử lý chữ Trung/Nhật cho chức năng mới.
- Kiểm tra trạng thái media trước khi thêm caption, khôi phục In/Out sau export và bảo toàn video/audio.
- Thêm hướng dẫn sử dụng trong panel và tài liệu, giải thích rõ dữ liệu cục bộ và giới hạn bảo mật của bộ cài chưa ký số.

## 2.19.9

- Nới mép caption tối đa 3 frame khi đủ khoảng trống, không đè caption liền kề; kế hoạch dựng V1/A1/A2 giữ nguyên.
- Bảo vệ thêm các cụm "cấm kỵ", "lúc này" và "tổng khối lượng" khi chia caption theo voice, kể cả lúc nghỉ hơi nằm giữa các tiếng.
- Tách các cụm bổ sung do người dùng báo vào danh sách riêng để dễ bảo trì, không trộn vào từ vựng gốc.
- Kiểm thử bằng đúng voice/SRT phản vật chất và rà soát 4.582 cue từ 54 SRT tiếng Việt.

## 2.19.8

- Nới mép đầu và cuối của mỗi cue caption tối đa 2 frame khi timeline còn chỗ, không chồng lên caption kế tiếp. Không thay đổi các mốc dựng V1/A1/A2.
- Thêm từ vựng cụm từ tiếng Việt chạy offline để tránh cắt giữa hai âm tiết đi liền nhau, kể cả khi điểm nghỉ hơi rơi vào giữa cụm; vẫn ưu tiên dấu câu.
- Kiểm thử hồi quy câu thực tế có "phá tung", "trực tiếp", kiểm tra 52 cue/voice thực tế và quét 4.582 cue từ 54 SRT tiếng Việt.

## 2.19.7

- Giữ điểm ngắt ở khoảng nghỉ hơi đo được ngay sau giới hạn 42 ký tự bằng cách chia cân đối phần trước đó; không cắt đôi cụm "tối cao" trong câu phản vật chất được báo lỗi.
- Nới ngưỡng nghỉ hơi trong câu không dấu xuống 0,16 giây, nhưng chỉ cho phép nhìn vượt giới hạn thêm một từ và tối đa 6 ký tự để tránh tạo nhiều chỗ cắt kém tự nhiên.
- Khi timestamp Whisper nằm trong vùng im lặng, hiệu chỉnh riêng mép caption theo voice thật; dấu câu có thể chọn khoảng nghỉ âm thanh gần đó ngay cả khi timestamp từ của Whisper bị lệch. Không thay đổi cue dùng để dựng video/voice.
- Bổ sung kiểm thử hồi quy cho hai câu thực tế, gồm thời điểm "Hôm nay," và điểm nghỉ sau "cao".

## 2.19.6

- Xử lý dấu câu trên toàn cue trước khi áp giới hạn ký tự, nên câu hỏi ngắn và dấu phẩy nằm sau mốc 42 ký tự vẫn được chọn làm ranh giới caption.
- Ghép vùng im lặng đo trên voice với ranh giới từ gần nhất ngay cả khi Whisper báo timestamp hai từ liền sát nhau; chọn mỗi vùng im lặng cho một ranh giới.
- Kiểm thử bằng SRT, word timestamp và các vùng im lặng thực của câu phản vật chất được báo lỗi; kiểm tra cả 52 cue của voice đó không còn caption một từ hoặc thời lượng dưới 0,3 giây.

## 2.19.5

- Khi caption dài cần tách, ưu tiên dấu câu; nếu không có dấu câu phù hợp, dùng khoảng nghỉ hơi được cả word timestamp và FFmpeg xác nhận; cuối cùng mới chia ở khoảng trắng.
- Điểm chuyển tại chỗ nghỉ hơi lấy tâm vùng im lặng và làm tròn theo frame. Khoảng trống nhận diện không khớp âm thanh không được xem là nghỉ hơi.
- Giữ cách cân lại caption cuối quá ngắn và thêm kiểm thử ưu tiên ngắt câu, xác minh âm thanh, timestamp và tích hợp planner.

## 2.19.4

- Cân lại hai caption cuối khi cách chia theo giới hạn ký tự để lại một đoạn đuôi quá ngắn; tránh caption riêng chỉ một từ như "khiếp".
- Giữ các điểm ngắt trước đó và tiếp tục đặt thời điểm chuyển caption theo word timestamp của voice, làm tròn theo frame.
- Thêm kiểm thử cho câu tiếng Việt thực tế có ba caption và kiểm tra cả hai ranh giới voice.

## 2.19.3

- Tách caption dài thành nhiều caption một dòng, mặc định tối đa 42 ký tự và có thể chỉnh từ giao diện.
- Giữ word timestamp của Whisper để điểm chuyển caption bám theo lời đọc; mọi timestamp đầu ra vẫn được làm tròn theo frame.
- Xóa toàn bộ xuống dòng có sẵn bên trong cue caption mà không làm mất nội dung.
- Thêm kiểm thử bằng word timestamp giả lập và dữ liệu Whisper thực tế; không thay đổi thuật toán retime V1/A1/A2, schema 8 hoặc executor 25.

## 2.19.2

- Đổi ngưỡng cảnh báo tốc độ tối đa mặc định từ 110% lên 130%; tốc độ dựng vẫn không bị giới hạn.
- Tự chuyển thiết lập mặc định 110% còn lưu từ bản cũ sang 130% một lần.
- Thêm chẩn đoán chỉ đọc cho sequence, voice, SRT và backend trước khi dựng.
- Cải thiện thông báo lỗi khi đọc lại sequence và khả năng sử dụng giao diện.
- Tách mã vận hành, bộ cài, kiểm thử, công cụ thủ công và thử nghiệm thuật toán thành các khu vực rõ ràng.
- Thêm bộ chạy test thống nhất và GitHub Actions cho các kiểm tra không cần Premiere.

Không thay đổi thuật toán dựng timeline, planner schema 8, planner revision 10 hoặc executor 25 đã được nghiệm thu ở 2.19.1.
