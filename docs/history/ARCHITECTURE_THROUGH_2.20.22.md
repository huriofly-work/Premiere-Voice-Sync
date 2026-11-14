# Lịch sử kiến trúc đến Premiere Voice Sync 2.20.22

Tài liệu lịch sử: các phần mô tả nút thử nghiệm, opt-in và giới hạn speed chỉ đúng tại phiên bản được ghi. Xem [kiến trúc hiện tại](../ARCHITECTURE.md) trước khi sửa chương trình.

## Lịch chạy mặc định đã nghiệm thu, 2.20.22

Promote profile no-delay từ 2.20.21, bỏ trial flag/prompt. Auto edit truyền trực tiếp `enhanced` vào lựa chọn lịch chạy nội bộ; không thêm setting/UI tùy chọn. Baseline/fast chỉ giữ cho harness hồi quy. Native generator/host/engine giống bản người dùng đã thử; thay đổi promote chỉ ở lời gọi panel, version và tài liệu. Ba lượt native ngày 2026-10-08 đều hậu kiểm đạt; người dùng xác nhận không đơ và Save bình thường. Không suy rộng thành bảo đảm mọi máy/project. Log/rollback ZIP 2.20.20 giữ nguyên.

## Profile no-delay, 2.20.21

Nhánh riêng `codex/no-delay-auto-edit`. Main chuyển Auto edit sang profile `no-delay`: không gọi setTimeout (kể cả 0 ms), vẫn await callback CEP nối tiếp theo stage. Generator bỏ cả count/time batch limits và nhánh sleep 50 ms ở vòng kiểm caption cleanup chỉ cho profile này. Baseline/fast và host.jsx gốc giữ nguyên. Không ghép tất cả stage thành một evalScript: nhóm chuẩn bị/guard/hậu kiểm vẫn là các lời gọi native riêng theo thứ tự. Guards vẫn đọc đủ timeline trước mỗi stage, post-snapshot và final audit vẫn giữ nguyên; DTW/merge/cache không đổi. Trace ghi profile/no delay/batch disabled; không kết luận an toàn native từ mock.

## Log workflow tự lưu, 2.20.20

`createWorkflowMetrics` ở panel ghi JSONL append sau từng bước, không thêm lời gọi host hoặc thay native executor. Schema 1 chỉ cho phép workflow/stage/outcome cố định, thời gian, backend cpu/cuda, boolean fallback, các counter cache/count hữu hạn không âm. Không serialize result/error/log nguyên bản. Mỗi lượt tạo file `Workflow_<date>_<time>_<epoch>_<random>.jsonl` bằng `wx`, kiểm đường dẫn trước ghi. Auto edit ghi tên trace `Performance_*.jsonl`, không ghi đường dẫn trace. Dòng bắt đầu bước được ghi trước lệnh blocking, nên khi app bị đóng vẫn còn bằng chứng bước cuối; không có `finish` nghĩa là bị gián đoạn. Logger best-effort: lỗi tạo/ghi chỉ báo cảnh báo chung một lần, không thay kết quả edit. Retention chỉ chạm file thường không symlink có tên đúng do logger tạo, sau 30 ngày hoặc ngoài 99 file cũ trước khi tạo lượt mới (giữ file dưới 24 giờ). Cache/model/nhật ký khác không bị dọn. Thời gian workflow bắt đầu sau confirmation/validation, kết thúc sau cleanup; không bao gồm thời gian chờ xác nhận của người dùng.

## Cache kết quả audio thô, 2.20.19

`AudioCache.ps1` được `Native.ps1` nạp. Job alignment/caption/planner/DTW khởi tạo trạng thái riêng. Wrapper chỉ cache Whisper JSON/capture thành công và FFmpeg silencedetect, không cache các native call khác. Khóa SHA-256 gồm nội dung input audio, model, executable, runtime/CUDA lock và toàn bộ argv; bỏ đường dẫn output, thay đường dẫn input/model bằng hash nội dung. Whisper legacy, DTW, prompt, language, flags/crop khác nhau không dùng nhầm. Hash input được tính lại, không dùng size/date làm khóa persistent; model/executable chỉ memoize trong một job sau kiểm runtime của các bước ASR.

Kết quả nguồn chưa scale/offset được khôi phục vào file JSON của tác vụ hiện tại. Các bước lexical mapping, recovery validation, DTW speech edges, cue splitting, padding, frame conversion và planning vẫn chạy như cũ theo input hiện tại. Không lưu kế hoạch dựng hoặc PCM lâu dài, không cache failure hoặc GPU âm thầm chạy CPU. GPU/CPU có key riêng theo executable/argv và runtime lock; cache hit không thực thi Whisper. Counts hit/miss được báo trong panel. Các bộ đếm recovery cũ vẫn là số yêu cầu logic, không phải số lần nạp model thực tế.

Envelope có schema/key/payload SHA-256; corruption trở thành miss. File ghi tạm cùng thư mục rồi publish atomic; không chạy code từ cache. PowerShell 5.1 dùng chuỗi .NET thuần để tránh tuần tự hóa provider metadata. Ghi cache thất bại không thay kết quả nhận diện. Giới hạn khoảng 512 MB/30 ngày được áp dụng đầu job, chỉ trong `Cache/Whisper/Audio-v1`; nút clear hiện có xóa cả cache cũ/mới, không xóa model/backend. Các cache riêng toàn chapter cũ theo path/size/date không di trú tự động vì chưa chứng minh cùng nội dung audio.

Không thay `host.jsx`, executor sinh, timeline guard/yield, thứ tự native editing calls, DTW/merge/caption heuristics hoặc UI workflow. Tối ưu post-move snapshot chưa đưa vào bản này. Cache không thay thế bước export timeline audio của Caption-only: export mới vẫn cần để xác định nội dung đang nghe. Chưa triển khai persistent worker, parallel ASR hay cache PCM.

## Quét đến exact hit đầu tiên, 2.20.18

Log native 2.20.17 xác nhận số phần tử QE thay đổi sau retime, khiến index bị dựng lại: 418 queries/builds, 312 count changes trong đợt, không có reuse. Thay index bằng lookup đọc track hiện tại và dừng ở exact start đầu tiên. Khoảng cách 0 không thể bị một item sau cải thiện; tie rule của lookup gốc luôn giữ item đầu tiên, nên duplicate/unordered start không phá tính tương đương. Không dừng ở near hit: nếu không tìm được exact trong dung sai, vẫn quét hết và trả nearest đầu tiên theo quy tắc/dung sai gốc. Các trường native không đọc được bị bỏ qua như host; lỗi getItemAt vẫn truyền lên.

Không còn cache/index/proxy cũ hoặc rebuild do gap/count. Mỗi query đọc numItems hiện tại một lần trong lookup chỉ đọc đồng bộ, rồi đọc candidate trực tiếp từ track; không giữ item qua hai query/đợt. Khóa track generator, guard đầy đủ trước đợt, source/duration/mapping audit, yield và mọi lệnh native dựng giữ nguyên. `host.jsx`, engine và UI runtime không đổi.

Log thêm `qeItemReads`, `qeEarlyHits`, `qeNearestScans`; counters index cũ giữ 0 để tương thích reader. Mock count thay đổi mỗi query có ít lần đọc hơn, nhưng chưa phải chứng minh giảm thời gian dựng native. Chỉ triển khai bước tra QE, chưa tối ưu sort/marker/A2/snapshot hoặc song song ASR.

## Chỉ mục QE theo track trong từng đợt, 2.20.17

Chỉ thay tra cứu clip trước setSpeed trong executor sinh; `host.jsx`, engine, UI, thuật toán DTW/gộp/caption và các tham số native không đổi. Generator kiểm đúng bốn call site V1/A1 và thêm khóa `V:0`/`A:<linkedTrackIndex>` vào helper riêng. Cache thuộc closure của một sequence/session và bị xóa mỗi đợt sau guard đầy đủ/rebind; không giữ native track/item proxy, chỉ lưu key, numItems và chỉ số nguyên theo start ticks.

Mỗi query vẫn đọc numItems; count đổi thì dựng lại toàn index. Start trùng/không tăng/không hữu hạn hoặc đọc native lỗi thì dùng lookup gốc, giữ nearest-start/tie semantics. Exact hit phải lấy candidate mới và kiểm type/start ngay trước setSpeed; candidate sai thì vô hiệu index và fallback. Truy vấn thiếu/không đúng khóa hoặc profile baseline không dùng cache. Không bỏ yield, guard trước đợt hoặc hậu kiểm; không giữ cache qua structural edit/move hay qua hai đợt.

Log thêm `qeCacheReuses`, `qeCountChanges`, `qeCandidateMisses`, `qeInvalidLayouts`, cạnh queries/builds/hits/fallbacks/time. Cần log native để phân biệt proxy identity với gap/count thay đổi. Nếu Premiere đổi count liên tục, tối ưu này vẫn phải rebuild; chưa chứng minh giảm wall time thực tế.

## Tương phản nút xác nhận, 2.20.16

`acceptWorkflowNotice` của 2.20.15 chỉ có class button, thiếu class primary/secondary nên không có nền xác định. CSS chữ trắng có thể nằm trên nền nút mặc định sáng của trình duyệt. Thêm class primary và màu riêng cho hàng action của notice: nền #5d43d6/chữ #ffffff, hover #4d35b8, active #40299c. Kiểm tỷ lệ tương phản ba trạng thái 6,48/8,34/10,42:1. Không thay confirmation Promise, main.js, engine hoặc executor. Đánh giá tăng tốc ở PERFORMANCE_REVIEW.md là đề xuất, không phải thay đổi runtime.

## Một kiểu thông báo/xác nhận, 2.20.15

Người dùng nghiệm thu 2.20.14 không còn tụt Premiere ra sau khi hiện kết quả. Mọi dialog của panel chuyển sang box DOM chung: `showWorkflowNotice` cho kết quả, `confirmWorkflowNotice` trả Promise chờ lựa chọn thật. Không dùng alert/confirm/prompt hệ thống, không focus/activate. Renderer dùng textContent, tone theo whitelist; nút hành động chỉ hiện khi chờ xác nhận, Hủy/Đóng quyết định false, click lặp không resolve hai lần. Không thay một xác nhận đang chờ bằng kết quả khác.

Auto edit chờ đồng ý trước tạo job/ASR/dựng. Xóa cache khóa các tác vụ trong lúc chờ để không xóa cache giữa một lần dựng; Hủy không xóa gì. Checkpoint dùng chung box, Dừng giữ đường abort cũ. Kết quả xuất log giữ redaction và ghi `wx`, hộp chọn thư mục vẫn native. Chẩn đoán chỉ đọc và reset settings cũng dùng box chung; tiến trình, scan tự động và log vẫn inline. Engine/host/generator không đổi so với 2.20.14.

Theo lựa chọn người dùng, bỏ `performanceTrialSection`, hai nút dựng chẩn đoán và ô dừng từng nhóm khỏi HTML/wire. Không chỉ ẩn bằng CSS. Nhánh đối chiếu/checkpoint nội bộ vẫn có để bộ test hồi quy kiểm cơ chế staged/abort; không có nút truy cập trên giao diện. Giữ `runDiagnostics` chỉ đọc đầu vào, không phải thử thuật toán. Không xóa experiments hoặc dữ liệu `_local`.

## Thông báo kết quả trong panel, 2.20.14

Người dùng báo 2.20.13 dựng xong kết quả tương đối chấp nhận được, không lỗi nghiêm trọng/đơ và Save bình thường; Premiere tụt sau cửa sổ khác ngay khi hộp hoàn tất xuất hiện. Đường kết thúc gọi `window.alert()`; chưa có trace Windows chứng minh nguyên nhân native chính xác. Bản mới bỏ native alert của cả success/failure ở Auto edit và Caption-only, thay bằng `showWorkflowNotice` DOM dùng `textContent` và một box fixed trong panel. Không gọi focus/activate/window.open/host API, không tự Play/Save; đây là sửa UI để loại bỏ đường nghi vấn, chưa bảo đảm xử lý mọi lỗi foreground Windows.

Box không modal, không chặn cleanup/finally, đóng chỉ ẩn box. Bắt đầu tác vụ khác ẩn kết quả cũ, kết thúc vẫn giữ status/log. Nội dung dài scroll bên trong, nút đóng vẫn nhìn thấy ở panel thấp. Xác nhận trước khi dựng và thông báo khi người dùng chủ động xuất log không đổi. Engine, thuật toán DTW/gộp/caption, `host.jsx`, generator và JSX chia đợt giữ nguyên byte so với 2.20.13.

## Đường dựng mặc định và marker, 2.20.13

`runSync` tạo job `one-click-dtw-direct` với protocol DTW/gộp v1/v2 hiện có. Hai preflight chạy trước ASR. Kế hoạch cơ sở → thêm điểm cắt DTW đã kiểm bảo toàn (nếu có) → visual partition gộp một lần → factory profile fast. Không có ô đồng ý thử thuật toán, chỉ một xác nhận bắt đầu; no-op DTW/gộp vẫn dựng kế hoạch hợp lệ. Nút chẩn đoán giữ baseline không DTW/gộp để đối chiếu. Tên script/trường có chữ Trial được giữ để tương thích protocol, không còn là lựa chọn thuật toán trên UI.

Không thay các lệnh razor linked, retime, move, fallback đuôi, A2 hay căn caption. Mọi cặp hình gộp có marker; `speedWarningSentenceCount` chỉ đếm nhóm thực sự ngoài ngưỡng, `mergeClipMarkerCount` đếm nhóm gộp đánh dấu thành công.

Host ánh xạ trước các ProjectItem V1/A1/A2 và hợp các khoảng source; dọn marker nhận diện được trước các thao tác cắt/retime, kể cả lượt mới không sinh cảnh báo. Owner được dọn một lần, không xóa marker vừa tạo. Chỉ nhận tên `VOICE SYNC -` kèm tag `[PremiereVoiceSync:owned-marker:v1]`, hoặc đúng tên và regex ghi chú tốc độ/căn voice của bản cũ. Không chắc thì giữ; không dựa màu/vị trí để nhận tác giả. Tag không phải chữ ký chống sao chép. Marker nằm trong khoảng source nửa mở; ngoài phạm vi, CTA và marker thủ công giữ lại. Vì marker thuộc ProjectItem, các instance dùng chung cùng source có thể thấy cùng thay đổi marker.

Factory có đợt dọn marker riêng, rebind owner bằng nodeId đã lưu trước đợt; không đọc native proxy đã remove. Thao tác marker được tính `timelineMutated`, báo số đã dọn. Hash source sinh giữ guard; profile nhanh và hậu kiểm như 2.20.12.

Marker palette: nhanh=1/đỏ, chậm=3/cam, cần kiểm căn voice=4/vàng, gộp trong ngưỡng=6/xanh dương. Nhóm gộp còn vượt dùng màu cảnh báo speed, không tạo hai marker chồng nhau. Màu không tham gia ownership/cleanup. Khi API đọc màu có sẵn, kiểm lại sau set; lỗi màu là cảnh báo riêng `clipMarkerColorFailureCount`, không làm fail hậu kiểm hình/voice đúng. Không đổi marker thủ công.

Người dùng xác nhận 2.20.12 không đơ Preview và Save bình thường. Log executor 124 lượt/216,365 giây, so với 2.20.11 126 lượt/245,397 giây; đây không phải A/B kiểm soát toàn bộ input. DTW và gộp trước đó cũng được nghiệm thu riêng. Bản tích hợp 2.20.13 cần nghiệm thu native riêng; unit/mock không chứng minh media engine không lag.

Các phần phiên bản dưới đây ghi lại quá trình phát triển; mô tả “nút ổn định không đổi” chỉ áp dụng ở phiên bản lịch sử đó.

## Snapshot sau đợt theo clip vừa đổi, 2.20.12

Chỉ profile `fast` dùng post-snapshot gia tăng sau hai vòng speed và snapshot chỉ đọc ID sau hai vòng marker. Trước mọi đợt vẫn quét đầy đủ fingerprint của mọi clip/track, nguồn, vị trí và speed; final audit không thay đổi. Timer 20 ms/budget 600 ms/100 iterations giữ như 2.20.11, không tăng thời gian chặn host.

Generator gắn `postMode` theo loop index đã review và thêm ghi nhận nodeId vào helper `setClipSpeed` của factory (không sửa host ổn định). Snapshot trước đợt lưu plain rows/ID/order/layout. Sau đợt xác minh mọi track/count/clip ID/thứ tự bằng native item mới; chỉ đọc lại source/time/speed đầy đủ của ID đã gọi setSpeed. Dirty item không tìm thấy, ID trùng hoặc đổi track/count/order thì fallback toàn bộ. Marker chỉ thay ProjectItem marker, không đổi các trường clip trong fingerprint. Thay đổi ngoài scope không được hấp thụ vào expected state: full guard trước đợt sau sẽ dừng. Cắt/remove/move/setup/caption và hậu kiểm luôn full post-scan.

`snapshotStrategy` và `snapshotDetailReads` được ghi trong timings; detail reads chỉ đếm clip đọc đủ source/time/speed, KHÔNG tính lượt kiểm ID/thứ tự. Không giữ thêm native item proxy trong kết quả post-snapshot. Revision `staged-edit-v3` chặn executor sinh cũ khi tải nhầm. Profile baseline và nút stable không dùng tối ưu này.

Người dùng xác nhận lần chạy fast 2.20.11 không đơ Preview và Save bình thường. Log đo 126 lượt/245,397 giây, so với log baseline trước khoảng 333 giây/296 lượt (không phải phép A/B kiểm soát toàn bộ input). Full guard trước đợt mất 37,843 giây, post-snapshot 55,502 giây, work 114,641 giây; lookup QE 34,736 giây nằm trong work. 2.20.12 tối ưu post-snapshot, chưa đo tốc độ hoặc nghiệm thu Preview/Save trong Premiere.

## Đường chia đợt nhanh, 2.20.11

Nút thử nhanh dùng profile `fast` của factory, tách khỏi stable/DTW và profile `baseline` chẩn đoán cũ. Budget mềm 600 ms/100 lần lặp, timer CEP 20 ms; baseline giữ 200 ms/20 lần lặp và 150 ms. Không có `$.sleep`, tự Play, Save, xóa History hoặc bỏ hậu kiểm. Không thể ngắt một native API đang kẹt; budget chỉ kiểm trước lần lặp kế tiếp.

Fast gộp snapshot kiểm fingerprint và ánh xạ TrackItem vào một lượt quét; đọc collection/count một lần mỗi track, memoize nodeId của mảng đã ánh xạ. Fingerprint vẫn bao gồm mọi clip, nguồn, speed và sequence ID như baseline. QE lookup lập chỉ mục start-ticks mỗi đợt, chỉ lưu số index, đọc lại/kiểm chính xác candidate ngay trước dùng; duplicate/không thứ tự/không khớp exact/thay index quay về nearest-start lookup ổn định. Không thay bất cứ lệnh cắt, setSpeed, move, marker hoặc caption nào. Build-only helper ở `tools/diagnostic-fast-support.jsx` được chèn vào file sinh; không cần thêm file runtime.

Log tách `checkMs`, `rebindMs`, `workMs`, `snapshotMs`, thời gian/số lần QE lookup. `qeLookupMs` nằm trong `workMs`, không cộng hai số này để tính tổng. Giảm ghi DOM ở fast xuống mỗi đổi stage; log file vẫn ghi mọi đợt. String literal trong JSX sinh được escape Unicode để không lệ thuộc codepage của `$.evalFile`.

Người dùng xác nhận 2.20.10 chia đợt tự động đã hoàn tất, Preview không đơ và Save bình thường. Log run này: 296 lượt dựng, 333,165 giây; timer 150 ms cộng 44,4 giây, host-call tổng 274,713 giây (bao gồm guard/rebind, không phải chỉ native edit). Hai mẫu Player của phiên được báo bình thường chờ queue nhận việc, khác mẫu bị đơ cũ chờ gate qua AudioSupport. Chưa đủ bằng chứng chỉ ra lỗi native Adobe cụ thể. 2.20.11 cần nghiệm thu native riêng về tốc độ và Preview/Save; chưa nâng thành stable.

## Dựng theo đợt để chẩn đoán, 2.20.10

`host.jsx` và toàn bộ engine giữ nguyên so với 2.20.9. Nút ổn định vẫn gọi `executePlan` một lần. Đường chẩn đoán riêng gọi factory trong `diagnostic-executor.jsx`, được sinh cơ học bằng `tools/Build-DiagnosticExecutor.js` từ chính executor ổn định. Acorn chỉ dùng khi sinh/kiểm thử; panel không cần parser, npm hay tải thêm thư viện. `--check` và unit test chặn source sinh bị cũ; panel kiểm SHA256 host đã chuẩn hóa LF trước khi chạy.

Biến function-scope được giữ trong một closure; từng nhóm lệnh chạy qua một `evalScript` riêng. Các vòng cắt, retime, move, bỏ silence và marker nhường lượt sau tối đa 20 lần lặp hoặc sau 200 ms tại đầu lần lặp kế tiếp. Một cặp V1–A1 luôn nguyên tử theo lần lặp. Đây là soft budget: không thể ngắt một API native đang kẹt. Caption import/create/delete vẫn là một nhóm nguyên vẹn để không thay đổi hành vi cleanup.

CEP chờ 150 ms bằng timer giữa các lần gọi, không thêm `$.sleep` vào lượt dựng. Session/token và số lần gọi chặn replay. Fingerprint ID, vị trí, mép nguồn, speed của tất cả clip và sequence ID được đối chiếu giữa các đợt; nếu thay đổi ngoài lượt trước thì dừng. TrackItem/QE references cần dùng được ánh xạ lại; không truy cập proxy các lát voice đã remove. Hậu kiểm giữ nguyên.

Mặc định đường chẩn đoán dừng sau V1–A1, A2, marker và caption để người dùng thử scrub/Play rồi dừng playback trước khi tiếp tục. Dừng khi lag chỉ dừng các thao tác tiếp theo, KHÔNG Undo, KHÔNG lưu và KHÔNG khôi phục timeline. Không lưu kết quả dựng dở; cần Undo hoặc mở bản đã lưu. Đóng/reload panel lúc tạm dừng không tự tiếp tục; nếu bỏ phiên thì khôi phục bản đã lưu và khởi động lại Premiere trước thử lại.

`Logs/Performance_*.jsonl` chỉ chứa revision/hash, tên bước, thời gian, số lần gọi và đánh giá Preview của người dùng. Không có transcript, tên clip hay đường dẫn media; không tự gửi đi. Log được giữ để chẩn đoán, còn plan/audio/job tạm vẫn được dọn như trước. Raw dump cục bộ không nằm trong ZIP/GitHub.

## Khôi phục sequence khi kết thúc, bản thử 2.20.9

Auto edit dựng trực tiếp trên sequence đang mở. `finally` của `executePlan` chỉ gọi `openSequence` khi sequence hiện tại khác `original.sequenceID` hoặc không còn sequence hiện tại. Giữ xử lý lỗi khôi phục như cũ; không đổi các thao tác timeline, setSpeed, caption, marker hoặc thuật toán. Đây là thay đổi nhỏ để kiểm chứng lỗi playback/save chậm sau dựng, chưa chứng minh giải quyết lỗi Premiere. Bản này kế thừa quy tắc chỉ gộp một cặp từ 2.20.8; nên kiểm nút dựng ổn định trước để tách khỏi thay đổi đó.

## Gộp hình cân bằng tốc độ, opt-in từ 2.20.7

`build-speed-merge-trial-plan.ps1` và `lib/SpeedMergeTrial.ps1` chỉ chạy khi job có `speedMergeTrial=adjacent-speed-v2` và workflow thử nghiệm. Preflight được gọi trước ASR. Sau kế hoạch DTW (hoặc baseline khi không có điểm mới), lõi clone và giữ nguyên mọi trường, chỉ thêm `visualSegments`, `speedMergeTrial`, `speedMergeSummary`. Không ghi đè baseline, không chạy lại ASR/caption.

Từ 2.20.8, mỗi visual group chứa `MemberSegmentIndices` gồm một hoặc hai nhóm liên tiếp của `segments` gốc. Tính speed bằng frame nguồn/frame đầu ra, xử lý outlier nặng nhất, thử hai hàng xóm chưa được dùng và chỉ nhận một bước giảm khoảng cách đến dải ngưỡng. Hòa thì ưu tiên hàng xóm ngắn hơn, sau đó bên trước. Cặp vừa gộp bị khóa cả vai trò target lẫn neighbor; nếu vẫn ngoài ngưỡng thì host đặt marker thông thường, không gộp tiếp. Planner và host đều từ chối hơn hai members; đổi protocol sang v2 để không nhận nhầm kế hoạch gộp chuỗi v1. Qua chapter được phép nhưng ranh giới source/output/original voice phải liền nhau; gap là rào chắn. Đây là chọn cặp greedy cục bộ, không solver tối ưu toàn cục.

Host `_speedMergeVisualPlans` kiểm partition, frame, speed, gap/tail trước khi đọc/mutate sequence; chỉ đường razor/retime V1–A1 nhận `visualSegments`. Đường cắt/mapping/move/marker A2 tiếp tục dùng `plan.segments`, mọi caption và speed voice không đổi. Marker speed dùng chỉ mục hình riêng, marker căn voice dùng chỉ mục voice cũ. Executor 25 không đổi thủ tục setSpeed, reconcile, tail shift, marker hoặc caption; bản mới chỉ chọn kế hoạch hình tùy chọn đã kiểm bảo toàn. Không có cờ thử thì trả thẳng `plan.segments`, giữ hành vi ổn định.

UI có lựa chọn cân bằng mặc định tắt, không persist, tự reset. Chỉ nút thử gọi wrapper; có thể áp dụng merge-only khi DTW không thêm cut, nhưng không có thay đổi cả hai thì không gọi executor. Kiểm lại template và xác nhận riêng trước dựng; hậu kiểm thực tế/marker vẫn bắt buộc. Chưa nghiệm thu timeline Premiere.

## Tạo subtitle độc lập

Panel có đường chạy `caption-only` riêng. `scanCaptionRange` hợp nhất các vùng clip đang chọn (hoặc lấy toàn sequence), chụp trạng thái video/audio và xuất audio thực tế qua preset WAV có sẵn trong Premiere. In/Out được khôi phục trong `finally`, kể cả khi export lỗi. `run-captions.ps1` dùng backend CPU/CUDA hiện có để nhận diện lời nói đa ngôn ngữ; timestamp được đưa về vị trí gốc của từng vùng chọn. Nó dùng lại `Split-PvsVoiceAlignedCaptionCue` và `Add-PvsCaptionEdgePadding` cho caption theo từ; chữ Trung/Nhật có bộ chia theo ký tự trong `CaptionOnly.ps1`.

Với SRT, `Select-PvsSubtitleReference` căn bán toàn cục theo từng vùng audio: bỏ qua prefix/suffix SRT nhưng phải tiêu thụ toàn bộ từ ASR, giới hạn 25 triệu ô DP (rolling cost + byte traceback). Chỉ nhận phạm vi cue nguyên vẹn có mốc lexical rõ hai mép và duy nhất; nhiều vùng phải theo thứ tự cue, không chồng nhau. Giữ cue ID/chữ gốc, gọi lại validator nội dung hiện có cho mọi cue bên trong phạm vi; không bỏ cue thiếu timing ở giữa. Kết quả ghi phạm vi và số cue ngoài vùng. Không dùng timecode SRT để tìm phạm vi.

`Repair-PvsSubtitleRecognitionEdge` nhận diện lại tối đa một cửa sổ đuôi không quá 30 giây khi token vượt mép WAV hoặc (chế độ SRT) ASR kết thúc hơn 1 giây trước tín hiệu âm thanh cuối. Cửa sổ dài hơn 30 giây không được dùng; file dài cần khoảng nghỉ đo được để bắt đầu. Ghép lại timestamp bằng offset WAV thực, không đoán thời gian từ SRT. Không xác minh được đuôi thì từ chối thay vì tự thu hẹp SRT. Mép caption dùng ceil/floor frame bên trong phạm vi sample-based của audio.

`applyCaptionOnly` kiểm tra sequence và trạng thái media trước khi thêm Caption Track. Nó chỉ import SRT vào bin tạm, tạo caption và dọn bin; không gọi edit planner, razor, move hay setSpeed. File công việc/audio/SRT tạm nằm trong vùng Jobs và được panel dọn. Đường edit ổn định không import `CaptionOnly.ps1`.

API export và lưu/khôi phục In/Out tham khảo [mẫu PProPanel của Adobe](https://github.com/Adobe-CEP/Samples/blob/master/PProPanel/jsx/PPRO/Premiere.jsx). Preset WAV được tìm từ các system preset cài cùng Premiere; gói không sao chép preset riêng từ máy phát triển.

## Đường chạy ổn định

1. `extension/js/main.js` đọc template và tạo job trong `%LOCALAPPDATA%\PremiereVoiceSync\Jobs`.
2. `run-alignment.ps1` căn SRT tiếng Việt với các chapter A2 bằng Whisper và giữ timestamp của từng từ đã map.
3. `build-sentence-plan.ps1` tạo kế hoạch schema 8 hoàn toàn theo frame, đồng thời chia caption dài thành các phần một dòng theo dấu câu, vùng nghỉ hơi đã xác nhận, rồi ranh giới từ trong voice.
4. `extension/jsx/host.jsx` executor 25 cắt, retime, dồn V1/A1/A2, tạo clip marker và caption.
5. Panel hậu kiểm rồi xóa job tạm; project không tự lưu.

Schema 8 và executor 25 được giữ nguyên từ bản 2.19.1 đã nghiệm thu; planner revision 18 chỉ cập nhật cách chia và thời điểm caption. Ngưỡng tốc độ 70–130% chỉ quyết định marker cảnh báo.

Caption ưu tiên dấu câu trước giới hạn ký tự, nhưng dấu phẩy/chấm phẩy/hai chấm chỉ tạo clause khi đã có ít nhất ba token và độ dài đọc được. Dấu hai chấm nối hai tên Latin được bảo vệ. Dấu kết thúc câu vẫn giữ những phát ngôn ngắn hoàn chỉnh. Một vùng im lặng FFmpeg dài ít nhất 0,16 giây được gán cho ranh giới từ đã map gần tâm vùng đó nhất nếu cách không quá 0,16 giây và hai từ cùng chapter. Từ vựng offline và `vi-caption-overrides.txt` cấm ngắt trong cụm. Nếu nghỉ hơi nằm ngay sau mốc 42 ký tự, thuật toán nhìn vượt tối đa hai âm tiết và 6 ký tự, rồi chia cân đối phần trước đó. Mép caption được thu theo im lặng khi phù hợp, sau đó nới tối đa 5 frame nếu không chồng caption bên cạnh. Cue gốc và timeline retime không đổi.

`CaptionTiming.ps1` là lõi timing caption dùng chung. Nhận diện với `-dtw <model> -nfa`, ánh xạ ký tự/token về từ (kể cả segment SOW có duration 0), kết hợp khoảng lặng PCM -35 dB / 120 ms để giữ hai mép speech độc lập. Mốc DTW của token không phải onset từ; chuyển caption do giới hạn ký tự dùng ranh giới trước token đầu khi có bằng chứng, không áp dụng offset frame cố định. Dấu câu/nghỉ hơi được bảo vệ. Mép caption được padding tối đa 5 frame và chia phần trống khi cần, không overlap.

Caption-only dùng DTW trong lượt ASR thường; tiếng Trung/Nhật giữ parser/chia ký tự hiện có. Auto edit chạy DTW riêng với cache tách biệt, chỉ ghi `CaptionWordTimings`, `CaptionStart`, `CaptionEnd`, `CaptionTimingRevision`; không sửa timestamp/confidence/chapter dùng dựng. Căn theo chapter đã xác minh để chapter lỗi không làm lệch chapter khác. Thiếu từ ở mép caption thì nhận diện lại cửa sổ tối đa 30 giây; đủ coverage/độ khớp/thứ tự mới nhận. DTW không hợp lệ thì giữ đường caption cũ, báo cue/lý do, không đoán thời gian. Cache có thể xóa bằng nút hiện có; WAV/crop/job vẫn tự dọn.

`Repair-PvsNumericCaptionTimings` còn dùng cho đường caption cũ và fallback, giữ nguyên đối chiếu giá trị số/ngữ cảnh/thứ tự. Auto edit vẫn giữ bước này để bảo toàn chất lượng fallback. DTW vẫn là ước lượng Whisper, không phải bằng chứng khớp âm vị chính xác; số, tên riêng hoặc nhiều token cùng anchor có thể cần nghe lại. Không thêm model/runtime hay thay chính sách tải GPU.

`Invoke-PvsWhisperCapture` dùng response file khi có prompt: UTF-8 cho nội dung tiếng Việt, Windows system code page cho các đối số đường dẫn như argv gốc. File đối số được tạo trong job và xóa trong `finally`, không đổi bảng mã hệ thống hoặc console. Các lần ASR không prompt và FFmpeg giữ đường gọi cũ.

## Ranh giới an toàn

`build-dtw-trial-plan.ps1` chỉ được gọi từ nút thử nghiệm đã chọn rõ, không từ planner/recognition ổn định hoặc caption-only. `lib/DtwEditTrial.ps1` là lõi dùng chung cho đường thử và harness offline; production không import thư mục experiments. UI gọi `-ValidateOnly` trước ASR để kiểm đầu vào ngay; không cần alignment/baseline/runtime cho bước này. Không ép speed voice về 100%: word timing DTW và quiet đã được lõi hiện có quy đổi bằng 100/speed theo từng chapter. Giới hạn media In 0 vẫn giữ vì recognition hiện tại chưa trừ offset nguồn. Voice ngoài nhóm chính/CTA không bị chốt thử kiểm nhầm. Wrapper nhận job template thực tế và alignment đã có, giữ baseline không đổi, chạy planner ổn định trong process con cho candidate rồi kiểm conservation/định danh các điểm cắt. Chỉ báo `canApply=true` khi mọi kiểm tra đạt; UI yêu cầu xác nhận thứ hai và đọc lại template trước khi dùng executor 25. Job/candidate/SRT/report ở cùng vùng Jobs, được dọn bởi luồng hiện có. Trạng thái bật thử không lưu vào localStorage, tự tắt sau mỗi lần chạy. Nút dựng thường không đổi thuật toán; bản thử không thay host.jsx.

- `extension` là cây duy nhất được cài vào CEP.
- `installer`, `tests`, `tools`, `docs` và `experiments` không được cài vào CEP.
- `experiments` không được production import và không chạy trong CI ổn định.
- Nút Chẩn đoán chỉ gọi API đọc sequence, đọc SRT và trạng thái backend; không tạo job, không chạy planner và không gọi executor.
- Mã điều khiển Premiere tiếp tục nằm trong một `host.jsx` để tránh thay đổi thứ tự nạp ExtendScript ở bản ổn định.

## Dữ liệu ngoài repository

Gói phân phối là ZIP với Setup-Panel.cmd/Remove-Panel.cmd. Thiết lập vẫn chép extension vào CEP và bật PlayerDebugMode, nhưng không đăng ký Installed apps. Marker deployment-mode.txt nhận diện bản panel ZIP. Chuyển từ bản EXE cũ chỉ xóa đăng ký khớp tên/đường dẫn và file uninstaller nhận diện đúng ID của tool; cache/model/backend không bị xóa. Script gỡ yêu cầu marker hợp lệ trước khi dọn dữ liệu và khôi phục cấu hình CEP.

Runtime CPU và model lớn nằm trong `extension/engine/runtime` trên máy build nhưng bị Git bỏ qua. Bộ phát hành offline lấy đúng các file đã khóa trong `installer/release-common.ps1`. CUDA được tải vào `%LOCALAPPDATA%\PremiereVoiceSync\Backends` khi cần.
