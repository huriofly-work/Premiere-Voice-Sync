# Đánh giá tăng tốc Premiere Voice Sync

## Căn chữ từ 2.20.23, đã tích hợp trong 2.20.25

Lõi lexical edit-distance hiện có được thực hiện bằng compiled rolling rows, không đổi thuật toán/timestamp Whisper DTW. Máy không chạy được accelerator và cửa sổ nhỏ dùng PowerShell cũ. Không thêm lựa chọn hoặc bước bấm cho người dùng.

Đối chiếu pipeline trên ba voice thật/305 cue với cùng cache đã prime: alignment 52,307 → 22,333 s; planner 3,803 → 3,665 s. Cả hai 30 recognition hit/0 miss, không gọi nhận diện mới. Full cue JSON, 695 caption, segments và markers giống nhau. Phép đo căn cue riêng khoảng 24,5 → 1 giây; không lấy tỷ lệ này áp cho toàn workflow. Chi tiết, fixture gates và giới hạn nằm trong [báo cáo rà soát](reviews/AUDIT_2026-10-08.md).

2.20.25 đã được người dùng xác nhận Preview/Play/Save bình thường và không còn lỗi được báo. Chưa có benchmark đối chứng native/cold-cache toàn workflow để kết luận tỷ lệ tăng tốc tổng. Native executor/lịch chạy giữ nguyên. Hướng chưa áp dụng: giảm đọc dữ liệu Premiere lặp bằng phép đo riêng, không nhiều worker cùng sửa timeline.

## Chốt mặc định không delay 2.20.22 (2026-10-08)

Người dùng đồng ý promote sau ba lượt no-delay hoàn tất, không đơ và Save bình thường. Cùng video có cache: tổng sau xác nhận 328,585 → 203,412 s (giảm 125,173 s, 38,1%); timeline 262,883 → 137,891 s; host call 116 → 24; check+snapshot 72,914 → 13,159 s. Căn voice gần như giữ nguyên 52,820 → 52,836 s với 30 recognition hit và 9 quiet hit. Lợi ích quan sát chủ yếu ở giảm số batch/đọc timeline/giao tiếp, không phải riêng timer 20 ms. Chưa khẳng định tỷ lệ này trên mọi lần chạy.

Đổi thông số: 281,313 s, timeline 169,846 s; 6 recognition hit/24 miss, trong đó 20 cửa sổ numeric/recovery và 4 caption-edge; không có cache hỏng/lỗi ghi. Nhận diện chapter gốc/DTW toàn chapter vẫn được dùng lại. Chưa đủ dữ liệu xác định chính xác thay đổi nào làm cửa sổ nguồn khác, vì log không lưu media/voice coordinates. Video mới: tổng 55,118 s, alignment 33,495 s (0 hit/4 miss), timeline 17,218 s, 162 caption/72 voice. Không dùng video mới ngắn hơn để suy ra mức tăng tốc so với video trước.

2.20.22 bỏ nhãn/cờ thử nghiệm, mặc định no-delay. Không đổi native generator/host/engine so với 2.20.21 được thử. ZIP 2.20.20 được giữ để phục hồi; không merge main/tạo Release chỉ từ kết quả thử nếu chưa được người dùng yêu cầu.

## Bản thử bỏ giới hạn lịch chạy 2.20.21 (2026-10-08)

Người dùng yêu cầu bỏ toàn bộ delay để thử lại hiện tượng đơ. Tách nhánh khỏi 2.20.20 đã chạy xong, Preview/Save bình thường. Bỏ timer 20 ms, count/time batch limits và sleep caption-cleanup trong Auto edit. Chỉ bỏ timer 20 ms ở 116 lời gọi tối đa mới tiết kiệm khoảng 2,32 s theo lịch đặt (không tính độ trễ timer thực tế); lợi ích lớn hơn nếu có phải đến từ giảm số batch/guard/snapshot/giao tiếp. Không bỏ hậu kiểm, không đổi thuật toán. Chưa có phép đo native của no-delay; có thể tái phát treo trước đây. Log mới phải ghi profile no-delay, yieldMilliseconds=0, batchLimitsDisabled=true; so cùng template đã lưu/input/cache, kiểm Play/Preview/Save sau cùng.

Ngày: 2026-10-07. Log cơ sở: 2.20.15–2.20.18. Bản candidate 2.20.19 triển khai cache audio của mục 4, độc lập với executor. Không đưa lại các nút thử nghiệm lên giao diện.

## Đo lại sau khi đóng Premiere, 2.20.20 (2026-10-08)

Hai lượt 2.20.19 người dùng đã thử hoàn tất hậu kiểm, Play/Preview và Save bình thường. Nhật ký panel đã mất sau khi đóng Premiere nên chưa thể xác nhận số hit/miss và thời gian audio của các lượt này. Lượt 10:01 bị người dùng đóng app do treo import caption là lượt gián đoạn, không dùng làm benchmark hoàn tất. Chưa kết luận cache làm tổng thời gian nhanh/chậm hơn từ log host-only.

2.20.20 chỉ thêm `Workflow_*.jsonl` trên đĩa cho hai chế độ: thời gian preflight, nhận diện/căn lời, lập kế hoạch/DTW/gộp hình hoặc xuất audio/tạo caption, dựng và cleanup; counter cache theo mỗi kết quả trả về; liên kết tên file Performance cho Auto edit. Không chứa văn bản nhận diện hay đường dẫn media và không thêm native call. Tổng processing bắt đầu sau confirmation/validation, cần so cùng phạm vi thời gian; không lấy số này thay thế máy móc tổng UI tính cả chờ người dùng. Khi không có finish, chỉ đọc bước cuối, không xếp là success. Giữ nguyên algorithm/executor/cache và chưa áp dụng post-move snapshot. Kiểm tự động của logger không chứng minh tốc độ thực tế trong Premiere.

## Cache audio 2.20.19

Auto edit trước đây đã cache hai pass nhận diện toàn chapter, nhưng recovery/số/edge chưa được cache; Caption-only và detector khoảng nghỉ còn xử lý lặp. Cache native mới theo bytes audio/config bao phủ các lượt này cho cả hai chế độ và các lượt quét khoảng nghỉ của planner/DTW. SRT/timeline/timestamp mapping và kế hoạch vẫn tính lại. Không lưu WAV lâu dài và chưa bỏ export/conversion audio; chưa thêm parallel worker. Cache cũ theo metadata không di trú tự động, nên lần đầu 2.20.19 cần prime lại.

Native CUDA trên đoạn voice fixture ngắn: bốn lượt Whisper mới 776–1165 ms, dùng lại 15–24 ms; CPU mới 2670–3145 ms, dùng lại 15–45 ms. JSON/timestamp giống từng byte, quiet output không đổi. Chưa đo mức tiết kiệm toàn workflow trong Premiere. Cần so cùng template sạch và cùng input, tách cold/warm, nghe điểm cắt/caption và kiểm Play/Save. Bản này giữ nguyên toàn bộ executor/guard/yield của 2.20.18; post-move snapshot đang nghiên cứu chưa áp dụng.

Hai lần 2.20.17/18 người dùng xác nhận cùng template/input/settings và đều chạy ổn. Host wall tăng 281,005 → 354,947 s (+73,942 s); precheck tăng 25,285 s, post snapshot tăng 22,786 s, work tăng 22,906 s. QE lookup giảm 28,648 → 25,399 s nhưng không bù phần khác; số batch tăng 113 → 140. Trong work, thời gian razor tăng trước khi lookup mới chạy. Vì vậy chưa có bằng chứng lookup là nguyên nhân trực tiếp làm tổng thời gian tăng. Log này chỉ đo host, không đo phần audio. Cache audio tối ưu một nút thắt riêng, không khẳng định sửa được toàn bộ chậm native.

## Kết quả native 2.20.17 và hướng 2.20.18

Người dùng báo chạy xong ổn. Log 22:24 có finish ok: 113 calls, host wall 281,005 s, timer cộng dồn 2,260 s, stage total 192,235 s; guard 36,288 s, snapshot 17,908 s, work 136,661 s, QE lookup 28,648 s (nằm trong work). Host wall trừ stage total còn 88,770 s chưa phân loại. Không khẳng định tăng tốc native từ log này; không phải A/B kiểm soát.

418 queries/hits/builds, 312 count changes, 0 reuse/fallback/candidate miss/invalid layout: index đúng nhưng không tái sử dụng được vì số item đổi giữa các lần retime. Đây là bằng chứng hiện tại; không tiếp tục gán nguyên nhân chính cho proxy identity. Log chưa chỉ ra loại item thêm/bớt, nên việc gap thay đổi là giả thuyết từ hành vi setSpeed, không phải trace trực tiếp gap.

2.20.18 bỏ index: quét track hiện tại, trả exact start đầu tiên ngay khi tìm thấy. Đây là nghiệm khoảng cách 0 và giữ first-item tie của host, không cần giả định start tăng/không trùng; near hit không được dừng, phải quét hết theo nearest rule gốc. Không giữ cache/proxy hoặc bỏ guard/yield/audit. Log thêm itemReads/earlyHits/nearestScans; counters index cũ về 0. Mock 200 clip/100 query giảm reads từ 20.000 xuống 5.050 (count ổn định), 24.950 xuống 10.000 (gap chèn mỗi query). Không coi tỷ lệ mock là wall-time native; cần log/nghiệm thu bản mới.

## Bước lịch sử: 2.20.17

Không còn dùng native track object identity để ghép cache. Generator cấp khóa V1/A1 theo track thật, cache chỉ tồn tại trong đợt đã qua guard đầy đủ. Count đổi vẫn rebuild; candidate được đọc mới và kiểm type/start; duplicate/unordered/nonfinite vẫn lookup cũ. Thêm bộ đếm reuse/count changes/candidate misses/invalid layouts để đo nguyên nhân rebuild trên Premiere. Không thay engine, thuật toán/timestamp hoặc scheduling/yield.

Test mock 200 clip/100 query/wrapper mới mỗi query/count ổn định giảm 20.000 xuống 300 lần đọc QE item. Đây không phải benchmark native hoặc cam kết giảm 98,5% thời gian: count/gap đổi có thể vẫn rebuild, và QE lookup chỉ chiếm một phần tổng quy trình. Chưa xác nhận proxy identity là nguyên nhân chính của 418/418 builds trong log cũ. Cần người dùng nghiệm thu native và log mới trước khi mở rộng tối ưu.

## Bằng chứng hiện có

Đọc tổng hợp bốn log Performance mới nhất; không cần media/transcript. Đây không phải A/B cùng template trong điều kiện kiểm soát. Log chỉ đo phần dựng trong Premiere, không đủ để suy ra tỷ lệ thời gian ASR/planner trên toàn quy trình.

| Lần chạy ngày 07/10 | Lượt gọi host | Host wall time | Timer 20 ms cộng dồn | Guard trước đợt | Snapshot sau đợt | Tra QE (nằm trong work) | Chuẩn bị ban đầu |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 21:29 | 122 | 278,143 s | 2,44 s | 46,290 s | 27,315 s | 29,552 s | 53,614 s |
| 20:51 | 112 | 200,280 s | 2,24 s | 35,174 s | 18,405 s | 27,598 s | 31,150 s |
| 20:37 | 107 | 572,610 s | 2,14 s | 29,415 s | 16,318 s | 26,794 s | 54,031 s |
| 20:09 | 115 | 209,809 s | 2,30 s | 37,221 s | 18,550 s | 28,825 s | 31,528 s |

Không cộng các cột thành tổng: QE là phần con của work; host wall còn có phần ngoài stage timer. Lần 21:29 có stage total 233,232 s so với host wall 278,143 s, chênh 44,911 s chưa được phân loại. Lần 20:37 có wall time bất thường; chưa biết do bridge/event-loop, native finalization hay người dùng tương tác. Không bỏ lần này khỏi dữ liệu hoặc gán cho một nguyên nhân khi chưa đo riêng.

Cả bốn lần cũ có 418 QE queries và 418 index builds. Tra cứu có exact hit nhưng không tái sử dụng chỉ mục giữa các truy vấn như kỳ vọng. Ở bản cơ sở, `diagnosticQEClipAtTicks` dựa vào identity của native track proxy và số item; cả proxy mới lẫn thay đổi gap/item count khi setSpeed đều có thể làm mất cache. Log cũ chưa phân biệt được nguyên nhân nào chiếm đa số; log 2.20.17 ở trên đã bổ sung bằng chứng count changes.

Marker tốc độ chiếm tổng stage 12,545–33,658 s, bao gồm guard/snapshot, không phải toàn bộ là native createMarker. `createOwnedClipMarker` đọc lại mọi marker của ProjectItem cho mỗi marker mới; các clip cùng nguồn dùng chung owner, tạo cơ hội giảm quét lặp.

## Thứ tự đề xuất

1. **Đo riêng các đoạn chưa rõ, rồi giảm đọc native lặp.** Tách timer cho read/parse plan, kiểm visual partition, dời tail, thu thập/sort clip, tạo Caption Track, hậu kiểm/finalization và bridge wall. Sau đó thử bộ DTO nhỏ cho executor, chỉ giữ các trường cần dựng/hậu kiểm; giữ nguyên bản plan đầy đủ cho conservation ở engine. Các sort hiện đọc `clip.start` bên trong comparator: có thể lấy giá trị một lần, sort bằng số, rồi rebind/kiểm nodeId trước khi ghi. Không giữ native proxy qua các đợt. Không giả định 31–54 s chuẩn bị đều do JSON.

2. **Sửa chiến lược tra QE.** Thay index phụ thuộc proxy object bằng định danh session/sequence/track; đo nguyên nhân invalidation. Nếu speed làm count/gap đổi, dùng lookup theo vị trí đã biết hoặc tìm có kiểm chứng, đọc lại candidate ngay trước setSpeed, giữ fallback đầy đủ cho duplicate/unordered start/gap/stale. Không đơn thuần bỏ kiểm count hoặc tái dùng QE proxy cũ. Mục tiêu giảm chi phí 27–30 s này; chưa hứa tỷ lệ tiết kiệm.

3. **Giảm quét marker, mapping A2 và snapshot dư.** Lưu tập vị trí marker theo owner trong đúng một đợt, cập nhật khi thêm/xóa, đọc lại khi sang đợt; giữ marker thủ công/ngoài vùng và kiểm projected source. Mapping speechPlans → allVoicePieces hiện tìm mọi candidate mỗi lần: có thể lập index start/end frame rồi vẫn áp dụng dung sai và tie-breaking cũ. Post-move snapshot có thể chỉ đọc chi tiết clip đã chạm nếu đã kiểm đủ ID/count/order; structural/caption/final audit vẫn quét đầy đủ. Guard trước đợt không được bỏ hoặc giảm dung sai.

4. **Dùng lại audio/quiet/recovery và giảm khởi động process.** Auto edit đã cache nhận diện legacy và DTW toàn chapter; không coi đây là chức năng mới. Recovery/số/caption-edge còn nhận diện cửa sổ qua CLI riêng, mỗi lần nạp model. Thêm cache cửa sổ theo media fingerprint, crop/speed, prompt, model/runtime/algorithm version, lưu atomically; timestamp nguồn trước khi scale để không tái dùng sai speed. Chia sẻ PCM/quiet giữa planner cơ sở, DTW và candidate planner khi tham số detector giống hệt; không nhầm quiet cho caption với silence bảo vệ điểm cắt. Một engine session có thể giảm nhiều lần mở PowerShell và hash runtime, nhưng vẫn kiểm tài nguyên trước khi thực thi native, có cache invalidation và chốt an toàn. Không bỏ checksum để lấy tốc độ.

5. **Song song có giới hạn, chỉ bên ngoài Premiere.** Có thể overlap FFmpeg chuẩn bị chapter kế tiếp/quiet trên CPU với một lượt Whisper GPU hiện tại; mỗi worker có output riêng, tổng số thread/process bị giới hạn, thu kết quả theo thứ tự chapter. Không chạy planner/gộp trước khi đủ alignment mà chúng phụ thuộc. Bắt đầu từ pipeline CPU+GPU, không mở nhiều Whisper GPU ngay. Sau khi đo GPU/VRAM, thử 1 so với 2 GPU workers trên chapter độc lập; chỉ giữ nếu nhanh thật, không thiếu VRAM hoặc khiến Premiere chậm. Máy CPU fallback phải có giới hạn riêng để tránh oversubscription.

6. **Worker Whisper giữ model trong bộ nhớ — hướng dài hơn.** Có thể dùng API/thư viện để tái sử dụng context cho nhiều cửa sổ recovery. Mỗi yêu cầu phải reset trạng thái đúng, cô lập chapter/prompt, hỗ trợ DTW/GPU fallback và dừng worker. Đây là thay đổi kiến trúc, không phải bản vá nhỏ; cần chứng minh timestamp và recognition parity trước khi thay CLI.

## Những hướng không nên áp dụng ngay

- Không nhiều worker cùng cắt/dồn/setSpeed timeline. [Adobe CEP Cookbook](https://github.com/Adobe-CEP/CEP-Resources/blob/master/CEP_12.x/Documentation/CEP%2012%20HTML%20Extension%20Cookbook.md#invoke-point-products-scripts-from-html-extension) nêu ExtendScript chạy trên main thread của host và khuyên chia script thành các lượt nhỏ để CEP event có cơ hội chạy. Nhiều Promise/process không biến thao tác DOM thành đa lõi an toàn; có thể làm queue dài hoặc mất thứ tự/guard.
- Không bỏ timer/yield: phần này chỉ ~2–3 s cộng dồn trong các log, trong khi cơ chế đã giúp Premiere không bị đơ. Timer thực tế có thể trễ hơn 20 ms; wall time ngoài stage cần đo trước.
- Không bật Flash Attention cho DTW: [whisper.cpp v1.9.1](https://github.com/ggml-org/whisper.cpp/blob/v1.9.1/src/whisper.cpp#L3406) tự tắt DTW token timestamps khi flash attention bật. `CaptionTiming.ps1` cố ý dùng `-nfa`; bỏ cờ này có thể làm mất chính mốc đang cho kết quả tốt. Legacy recognition không DTW đã dùng mặc định Flash Attention của CLI.
- Không tăng `--processors` để tự chia một voice dài: [upstream v1.9.1](https://github.com/ggml-org/whisper.cpp/blob/v1.9.1/src/whisper.cpp#L7118) chia theo số mẫu và cảnh báo chất lượng giảm quanh mép chia; không tự chọn chỗ nghỉ/câu. `--threads` và `--processors` không cùng nghĩa. Cần benchmark riêng nếu thay thread count, không mặc định lấy hết logical cores.
- Chưa đổi model nhỏ/quantization/greedy decode hoặc bỏ pass legacy chỉ để nhanh. Tool dùng legacy để bảo toàn mốc dựng, DTW để bổ sung điểm cắt an toàn/caption; hai pass hiện không thay thế nhau. Bỏ một pass là thay thuật toán, phải nghiệm thu nội dung và timestamp riêng.
- UXP transaction có thể là hướng dài hạn, không phải tăng tốc chắc chắn cho CEP đang dùng. [Adobe Project API](https://developer.adobe.com/premiere-pro/uxp/ppro-reference/classes/project#executetransaction) có executeTransaction/lockedAccess, nhưng migration cần kiểm đủ API speed/linked cut/marker/caption và tương thích phiên bản. Không thay nền tảng ở bản sửa UI.

## Điều kiện chấp nhận tối ưu

Mỗi hạng mục làm riêng; không nâng toàn bộ cùng lúc. So sánh cùng template sạch, cùng voice/SRT/speed/settings, cold/warm cache tách riêng, nhiều lần chạy. Bộ test phải giữ đúng nguồn V1/A1, duration theo frame, A2 không xén lời, speed/range/marker/manual marker, caption text/timing, scope CTA/Adjustment và file tạm. Trong Premiere cần Play/scrub/Save bình thường. Đo cả wall time, native work, API reads, GPU/CPU/VRAM; chỉ giữ thay đổi có lợi và không giảm chất lượng. Không đưa nút thử lên giao diện người dùng; dùng harness developer và bản candidate được đồng ý rõ trước khi cập nhật panel.
