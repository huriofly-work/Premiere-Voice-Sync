# Kiểm thử

2.20.70: kênh duy nhất nhắc ngoài ứng dụng là toast Windows. Panel là nguồn kết quả/phê duyệt; bỏ form review và tự giành focus. Bridge kiểm danh tính phiên/run/sự kiện, không gửi nội dung panel; helper dùng NotificationWindow chỉ đọc trạng thái host thuộc ancestry, chỉ kích hoạt host khi người dùng bấm toast. Xem [phạm vi và nghiệm thu](releases/notes/NOTIFICATIONS_2.20.70.md).

## Nhãn một chữ SRT — 2.20.67

53 nhóm/123 script parse đạt; sáu nhóm Windows integration bỏ qua theo runner.
Kiểm nhãn một chữ đúng/khác dấu, giữ chữ đến caption cuối, không bổ sung ASR
sai, offset, thiếu neo, sai nguồn/span, lời thêm/khác, đoạn trống và nhãn lặp
mơ hồ. Replay 2.346 từ từ cache chỉ phục hồi thêm A./C.; toàn engine CPU trên
45 giây audio A2 dựng lại giữ đúng hai nhãn, không chồng caption/timing ước lượng.
Chi tiết và giới hạn [2.20.67](releases/notes/SUBTITLE_TIMING_2.20.67.md); chưa nghiệm thu native.

## Short bị chuyển toàn bộ sang ASR — 2.20.64

52 nhóm/122 script parse đạt; sáu nhóm Windows integration bỏ qua theo runner.
Kiểm cue ngắn tương lai trùng trong voice, giữ SRT dù ASR ghi sai dấu/chữ,
xét lại cue khi có neo phải mới, lời ngoài SRT, câu bị cắt, chính sách Auto edit
mặc định, ngữ cảnh “giải”/“dài”, nhiều sai khác, từ không liên quan và cụm lặp.
Marker từng caption giữ đầy đủ chữ ASR kể cả sau 220 ký tự. Replay cache thật
0 → 27 cue; toàn engine CPU trên voice dựng lại giữ 27 cue, 50 caption và chỉ
bổ sung CTA, không còn chữ “dài.” thừa. Kiểm cấu trúc toàn output, hash project,
70 payload/71 mục ZIP và 15 bộ VM với mã đóng gói đạt. Chưa nghiệm thu native.
Chi tiết [2.20.64](releases/notes/SUBTITLE_TIMING_2.20.64.md).

## Chữ thừa ở biên SRT và marker số — 2.20.60

50 nhóm/120 script parse đạt, sáu nhóm Windows integration bỏ qua theo runner; log `.tmp-supplement-tail-2.20.60/suite-final.log`. Các kiểm liên quan được chạy lại sau thay đổi biên cuối. Cache từ lượt native tái hiện mã cũ thêm “tật.” sau “vô tận.”; mã mới không thêm chữ này và vẫn giữ 75 từ outro. Không chạy ASR/DTW mới hoặc playback để suy độ chính xác toàn video. 12 bộ VM chạy với mã lấy từ gói đạt; project được đọc giữ nguyên hash. Chi tiết [2.20.60](releases/notes/SUBTITLE_TIMING_2.20.60.md).

## Nhận diện bổ sung có ngữ cảnh — 2.20.57, 17/10/2026

48 nhóm hồi quy đạt, parse 118 script; sáu nhóm Windows integration được runner
bỏ qua. Các kiểm numeric/DTW cuối đạt; 12 bộ VM và 5 nhóm engine kiểm lại trên
runtime của gói đạt. Năm vùng ASR lạc đề thật không sinh lại chữ thêm khi nhận
diện với ngữ cảnh/mốc SRT; lời cảm ơn/hội viên thật vẫn giữ; 23/23 vùng nghỉ
được phân loại đúng trong kiểm ngoại tuyến. Không chạy lại toàn bộ sequence
trong Premiere. Cài thật xác minh 62 file panel; 2.035 file dữ liệu/24 thư mục
và registry CEP giữ nguyên. Xem [bằng chứng và giới hạn](releases/notes/SUBTITLE_TIMING_2.20.57.md).

## Giữ chữ SRT khi nhận diện gần khớp — 2.20.56, 17/10/2026

47 nhóm hồi quy đạt, parse 116 script PowerShell; sáu nhóm Windows integration
được runner bỏ qua. Log `.tmp-subtitle-partial/suite-final.log`. Sau đổi phiên
bản, kiểm repository/UI/metrics đạt; gói có 71 entry được đối chiếu hash, chín
bộ VM và bốn bộ engine dùng runtime trong gói đạt. Fixture đóng gói/cài/gỡ/
rollback/registry đạt. Cài thật xác minh 62 file panel, giữ nguyên 1.568 file dữ
liệu/24 thư mục và registry CEP. Chưa nghiệm thu nhận diện hoặc Premiere thật;
xem [bằng chứng phát hành](releases/notes/SUBTITLE_TIMING_2.20.56.md).

## Đối chiếu marker — 2.20.55, 17/10/2026

`Run-Tests.ps1 -NoWindowsIntegration` đạt **46 nhóm**, parse **115 script PowerShell**; log `.tmp-marker-reconcile/suite-final.log`. Sáu nhóm Windows integration được runner bỏ qua. Phép thử junction bảo mật chạy với quyền ngoài sandbox, dùng TEMP/TMP/LOCALAPPDATA riêng trong workspace. Kiểm mới bao phủ đối chiếu marker theo nguồn, không ghi lại khi dữ liệu không đổi, khôi phục metadata khi lỗi giữa chừng, xác minh xóa, báo khôi phục không đầy đủ, nguồn dùng chung, thời gian nguồn bị làm tròn, và hủy giữa hai nhóm nguồn trong cả ba profile. VM executor giữ parity với luồng trực tiếp; xem [thiết kế và bằng chứng](reviews/MARKER_RECONCILIATION_2026-10-17.md).

Đã đóng gói/cài 2.20.55, kiểm hash toàn bộ 71 entry ZIP, chạy chín bộ VM bằng runtime trong gói và kiểm fixture cài đặt/rollback/registry. Cài thật xác minh 62 file panel; 1.568 file dữ liệu/24 thư mục và registry CEP giữ nguyên. Đã sao lưu panel 2.20.54. Nghiệm thu Premiere vẫn chờ; xem [bằng chứng phát hành](releases/notes/REVIEW_MARKERS_2.20.55.md).

## Nối nhiều SRT — 2.20.54

46 nhóm hồi quy đạt, parse 115 script PowerShell; sáu nhóm Windows integration bỏ qua theo runner. Log `.tmp-srt-join/suite-verified.log`; chạy ngoài sandbox với TEMP/TMP/LOCALAPPDATA riêng để kiểm junction. Kiểm bổ sung `Test-SrtJoin.ps1` xác nhận UTF-8/timestamp/số cue được bộ đọc SRT engine hiện có đọc đúng. Browser fixture 320/385/560 px đạt cho cả hai chế độ và danh sách nhiều file. Chi tiết tại [2.20.54](releases/notes/SRT_JOIN_2.20.54.md). Chưa kiểm ASR/caption/dựng thật trong Premiere.

## Voice đã lược bỏ nội dung — 2.20.51

`Run-Tests.ps1 -NoWindowsIntegration` đạt **45 nhóm**, parse **114 script PowerShell**; log `.tmp-edited-suite/final-suite.log`. TEMP/TMP/LOCALAPPDATA riêng trong workspace; chạy ngoài sandbox để phép thử junction được thực hiện, không thay test hoặc bỏ qua kiểm tra bảo mật. Sáu nhóm Windows integration vẫn được runner bỏ qua. Đã kiểm cả hồi quy SRT dài, planner/DTW/speed merge, marker, hủy/tạm dừng và lỗi native trong VM.

Hai nhóm mới kiểm nhiều cụm câu bị bỏ, đầu/cuối, ASR bỏ sót, partial cue, thứ tự/câu lặp, output subtitle và ánh xạ hình nguồn tại 30/29.97 fps. Bộ thực thi mô phỏng kiểm xóa đúng cặp V1/A1, giữ A2 liền, Cancel trước xóa, lỗi xóa từng phía dừng phần dựng còn lại, và tránh đọc TrackItem đã bị xóa. Chi tiết: [voice đã cắt](releases/notes/EDITED_VOICE_2.20.51.md). Chưa nghiệm thu bản mới trong Premiere.

Đã cài 2.20.51 từ 2.20.50 lúc 17:48 ngày 16/10/2026 (UTC+7): 61/61 file panel khớp checksum, 923 file dữ liệu/24 thư mục giữ nguyên theo hash/cấu trúc, registry CEP giữ nguyên, shortcut/helper đúng identity. Bằng chứng `dist/_installation-2.20.51-20261016-174846/verified.json`; bản sao panel cũ nằm trong `previous-panel` cùng thư mục. Không mở/đóng Premiere hoặc thao tác project; native acceptance còn chờ. ZIP SHA256 `1674AD52753A916464CF0ABD602C716860F67F2C7A1190785047F55A4505EEFD`.

## Ưu tiên SRT 2.20.49 — đã cài

Ngày 16/10/2026, đối chiếu bản vừa cài từ chat marker: 2.20.48 đủ 60/60 file đúng checksum và chưa có tự chọn SRT. Gói 2.20.49 kế thừa payload đó, chỉ đổi lựa chọn SRT, phiên bản và tài liệu; 68 payload đạt kiểm manifest, các file engine/host/marker giữ nguyên từng byte với 2.20.48.

Kiểm SRT trên chính main.js của gói phát hành đạt: một file, xếp hạng/tên voice, nhiều file ngang nhau, Project rỗng/import sau đó, chọn thủ công/file ngoài/không SRT, chuyển chế độ, chọn lúc quét, tự chọn bị gỡ và giữ lựa chọn còn trong Project. JS syntax, metadata và parse installer/build đạt. Bằng chứng delta `.tmp-srt-release/payload-delta.json`.

Đã cài khi Premiere đóng: 60/60 file panel đúng checksum, 923 file/24 thư mục dữ liệu và 153 file/8 thư mục project giữ nguyên qua hash trước/sau. Registry CEP không đổi; shortcut/helper đúng identity/hash. Bằng chứng `dist/_installation-2.20.49-20261016-164617/verified.json`. ZIP SHA256 `B440A2B8B0C852A3F5A132A22861A29E834FE41B5B32BC89CED9D4EC25B41812`. Chưa nghiệm thu chọn SRT/import/Play/Save trên Premiere thật.

## Nguồn audio và phạm vi subtitle — 2.20.50

Đã kiểm lại trước đóng gói: 43 nhóm, parse 112 script, log `.tmp-caption-input/release-2.20.50/final-suite.log`. Package kiểm đủ 69 payload/70 entry ZIP và 61 file extension khớp nguồn; đã cài 2.20.50 khi Premiere đóng. 61 file panel đúng checksum, 923 file dữ liệu/24 thư mục và registry CEP giữ nguyên; shortcut helper đúng identity. Bằng chứng `dist/_installation-2.20.50-20261016-165436/verified.json`; không thao tác project hay khởi chạy helper. Native acceptance còn chờ.

Ngày 16/10/2026, lượt kiểm nguồn ban đầu `Run-Tests.ps1 -NoWindowsIntegration` đạt **43 nhóm**, parse **112 script PowerShell**. Sáu nhóm Windows integration được bỏ qua theo runner; phép thử junction và browser fixture chạy ngoài sandbox với TEMP/TMP riêng trong workspace. Log `.tmp-caption-input/final-suite.log`. Các phép thử không điều khiển Premiere hoặc dùng project người dùng.

`caption-input.test.js` kiểm ES3 parse, ma trận nguồn/phạm vi, overlap/enabled, tập track thủ công, mute/disabled, gộp vùng và bỏ vùng rỗng. `caption-audio-ui.test.js` kiểm checkbox nhiều track, giữ lựa chọn rỗng, đổi sequence, source/scope bị khóa, summary và busy. `caption-input-host.test.js` dùng resolver/job/host thật trên DOM/file fixture để kiểm đúng tập clip có tiếng, phối track, clip không chọn cùng track, disabled, selection/time đóng băng, staged export, setter không tác dụng, native lỗi, abort và journal khôi phục khi mất session/sai project/journal hỏng. `caption-recovery-ui.test.js` kiểm giữ job còn journal, khóa chạy khi journal mồ côi và khôi phục nhiều journal lần lượt. SRT/notification/host-export/pause/cancel cũ tiếp tục được kiểm trong suite.

Edge headless fixture đạt 320/385/560 px ở cả hai workflow, các chế độ nguồn, checkbox, khóa ô, giữ cấu hình, pause/cancel và không tràn ngang. Log `.tmp-caption-input/verified-ui.log`, ảnh `.tmp-caption-input/ui/`. JS syntax, UTF-8, diff whitespace và generated executor đều đạt. Đây là kiểm mô phỏng/browser layout; chưa nghe/so waveform xuất thực, xác minh Audio.disabled, nested, speed/effect, routing/solo, media offline, caption import hoặc Preview/Play/Save trong Premiere. Snapshot chưa bao phủ mọi tham số effect/mixer. Xem [trạng thái triển khai](reviews/AUDIO_SOURCE_SCOPE_REVIEW_2026-10-16.md).

## Marker cần kiểm tra 2.20.47

`Run-Tests.ps1 -NoWindowsIntegration` đạt 43 nhóm, parse 112 script PowerShell ngày 16/10/2026; sáu nhóm Windows integration được bỏ qua. Log `.tmp-marker-review/verified-suite.log`. `Test-ReviewMarkers.ps1` kiểm mapping cue/các vùng giữ lại sau dựng, ownership/phạm vi/workflow, marker người dùng, chạy lại, trùng frame và lỗi API/vị trí/màu. Mock host kiểm marker Chỉ tạo subtitle, executor trực tiếp, baseline/fast/no-delay, lỗi native và bảo toàn trạng thái caption đã thêm khi marker thất bại. Dữ liệu phân tích 615 cue có sẵn cho 86 mục cần kiểm tra nằm trong timeline ở cả ba kế hoạch cơ sở/DTW/gộp. Xem [phạm vi và giới hạn](releases/notes/REVIEW_MARKERS_2.20.47.md); cần nghiệm thu hiển thị/màu marker và Preview/Play/Save trong Premiere thật.

## Timing âm học Auto edit 2.20.45

Kiểm cuối ngày 16/10/2026: `Run-Tests.ps1 -NoWindowsIntegration` đạt 42 nhóm, parse 111 script PowerShell; sáu nhóm tích hợp Windows bị bỏ qua theo runner. Log `.tmp-shared-auto-timing/final-tests.log`.

`Test-AutoAcousticTiming.ps1` kiểm dùng chung lõi đo, hai chapter, năm speed 50/90/100/125/150%, offset, frame rate 30/29,97, giữ chữ/timecode nguồn và phạm vi voice ngoài cùng; loại timing ước lượng khỏi chứng cứ cắt, xử lý xung đột cục bộ và truyền lỗi native. Dùng Find-SafeVoiceBoundary thật để kiểm mốc mới dẫn tới khoảng nghỉ hợp lệ.

A/B ngoại tuyến toàn bài 615 cue chạy đủ alignment, sentence planner, DTW bổ sung và gộp speed: 465 cue nhận mốc mới, 45 cue xung đột giữ dự phòng, 224 → 237 nhóm hình. Kiểm bảo toàn nguồn/voice/chữ/thời lượng cuối đạt. Chỉ tạo subtitle xuất SRT giống từng byte với 2.20.44. Harness media có `-AllowEditTimingChanges` để kiểm bảo toàn thay vì khóa điểm cắt cũ. Chi tiết, giới hạn và bằng chứng xem [2.20.45](releases/notes/NOTIFICATIONS_2.20.45.md); chưa nghiệm thu Auto edit trong Premiere thật.

## Đo thời gian xuất audio 2.20.44

Test đồng hồ giả kiểm thời gian riêng native 8 giây và tổng host, kể cả native ném lỗi; panel kiểm sự kiện prepare/yield/render/abort và giữ kết quả khi logger ném lỗi; metrics kiểm số/pha allowlist, không ghi nội dung riêng tư, chỉ ghi trong stage xuất audio. Không thay cách căn subtitle 2.20.43. Cần một lượt chậm thật để phân biệt host/native với CEP/callback; test mô phỏng không xác nhận hết Encoding 0%.

## Timing subtitle 2.20.43

41 nhóm kiểm thử đạt, parse 110 script với `-NoWindowsIntegration`; 6 nhóm Windows integration bị bỏ qua theo runner. Kiểm mới bao gồm retry DTW theo cửa sổ, giữ nguyên vùng tốt, vùng ước lượng cục bộ, neo trước số, envelope RMS và âm phẳng/WAV lỗi. Thử dữ liệu ASR thực và audio dựng ngoại tuyến từ project; xem [báo cáo và giới hạn](releases/notes/SUBTITLE_TIMING_2.20.43.md).

Đã cài 2.20.43 khi Premiere đóng, dùng `-SkipRegistry`: 60 file panel đúng checksum, 624 file dữ liệu/22 thư mục và 408 file project/8 thư mục giữ nguyên. Registry CEP trước/sau khớp; helper/shortcut đúng identity/hash. Bằng chứng `dist/_installation-2.20.43-20261016-104923/verified.json`. Caption cũ và project không bị thay đổi; nghiệm thu native còn chờ.

## Rà soát căn SRT/voice 2.20.42

`Run-Tests.ps1 -NoWindowsIntegration` đạt 40 nhóm, parse 107 script PowerShell. Sáu nhóm Windows integration được bỏ qua; dùng TEMP/TMP trong workspace và quyền chạy ngoài sandbox cho phép thử junction. Log: `dist/alignment-audit-2.20.42-tests.txt`. Ca mới kiểm nguồn tốt ở hai bên nguồn sai, ASR rỗng một/toàn bộ nguồn, scope lặp/đảo thứ tự và timestamp không hợp lệ. Cả strict callers và chính sách không nội suy subtitle vẫn được kiểm.

100 fixture căn Auto edit khớp toàn bộ cue/word/confidence với oracle 2.20.40. A/B 10 plan và SRT khớp baseline, chỉ chuẩn hóa createdAt/đường dẫn fixture: `dist/alignment-audit-2.20.42-plan-parity.txt`. Xem [rà soát và giới hạn](reviews/ALIGNMENT_REVIEW_2026-10-15.md); đây chưa phải nghiệm thu chất lượng ASR/import/Play/Save trên Premiere thật.

Các nhóm shared core, scope, variants, fallback, layout và release chạy lại đạt sau cập nhật version/định dạng cuối; fallback thêm ca CJK rỗng/timing lỗi. Nhận diện chính Auto edit, compiled word mapper, CaptionTiming, host và generated executor vẫn khớp hash với 2.20.40; planner khớp hash với 2.20.41. JS syntax, generated-source và diff whitespace đạt.

Đã đóng gói và cài 2.20.42 khi Premiere đang đóng: 66 payload, 58 file panel đúng manifest. 608 file/22 thư mục dữ liệu giữ nguyên qua hash trước/sau; shortcut/helper đúng identity/checksum. ZIP SHA256 `04C76FE2839B77CA2F114A3D805ABB71BD7233588EB0D30C90330AFDB8B54EC7`; bằng chứng `dist/_installation-2.20.42-20261015-232809/verified.json`. Không mở/đóng Premiere hoặc sửa project; nghiệm thu native còn chờ.

## Lõi căn SRT/voice chung 2.20.41

`Run-Tests.ps1 -NoWindowsIntegration` đạt 39 nhóm, parse 106 script PowerShell; sáu nhóm Windows integration được bỏ qua. Fixture planner có thêm lõi mới, chạy ngoài sandbox cho phép thử junction. Sau kiểm chính sách cuối, nhóm shared core chạy lại đạt; subtitle không có lối gọi nội suy. Log: `dist/shared-reference-2.20.41-tests.txt`. JS syntax, generated-executor và diff whitespace đạt.

100 ca có seed đối chiếu toàn bộ kết quả căn Auto edit với oracle cố định từ 2.20.40. Parser Edit giữ timing legacy; parser Subtitle giữ lọc metadata/clamp. Hai workflow cùng dùng projection/recovery, kiểm cả không khớp sau retry để chuyển sang ASR bổ sung. Nội suy Auto edit đối chiếu tại 30 và 29,97 fps; subtitle gặp ASR rỗng phải báo vùng thiếu, không sinh timing ước lượng. Snapshot oracle chỉ có trong test helper, không đóng gói runtime.

Kiểm A/B bổ sung chạy planner 2.20.40 và planner mới trên 10 ca: safe/unsafe/weak boundary, điểm nghỉ dùng lại tại hai frame rate, ranh giới làm sụp đoạn phải, gap đầu/giữa/cuối và nội suy. Toàn bộ plan JSON và SRT đầu ra giống nhau sau khi bỏ duy nhất `createdAt` và chuẩn hóa đường dẫn fixture. Log: `dist/shared-reference-2.20.41-plan-parity.txt`. Nhận diện Auto edit, compiled word mapper, CaptionTiming, host và generated executor còn khớp hash từng byte với baseline 2.20.40.

Không chạy ASR mới trên media người dùng hoặc điều khiển Premiere trong các phép thử. Cần nghiệm thu hai workflow, phần phục hồi/bổ sung/CTA, caption, Play và Save trên project thật. Xem [phạm vi 2.20.41](releases/notes/NOTIFICATIONS_2.20.41.md).

Gói đối chiếu đủ 66 payload, SHA256 `FB9BD4551AF77D0DCA8647FFA205895B7994A84E92270CEAA71CD7734A46BC97`. Đã cài 2.20.41 khi Premiere đóng, baseline khớp 2.20.40; 58/58 file panel đúng manifest, 608 file và 22 thư mục dữ liệu giữ nguyên qua hash trước/sau. Shortcut/helper đúng identity/checksum. Bằng chứng: `dist/_installation-2.20.41-20261015-230204/verified.json`. Không mở/đóng Premiere hoặc sửa project khi cài; nghiệm thu native còn chờ.

## SRT dài và nhận diện bổ sung 2.20.40

`Run-Tests.ps1 -NoWindowsIntegration` đạt 38 nhóm, parse 103 script PowerShell; sáu nhóm Windows integration được bỏ qua. Fixture TEMP riêng trong workspace, chạy ngoài sandbox để phép thử junction hoạt động. Sau thay đổi cuối về timestamp bị dồn, chạy lại nhóm supplement và SRT dài đều đạt; JS syntax, generated-executor check và diff whitespace đạt. Log: `dist/long-srt-2.20.40-tests.txt`.

Oracle 120 ca giữ đúng mapping/cost/endpoint của DP cũ; fixture dài vượt guard cũ, intro/outro, nội dung lặp và thiếu cue. Fixture supplement kiểm giữ chữ SRT, nhận diện nội dung khác ở giữa, intro/CTA, fallback toàn ASR khi scope không dùng được hoặc timestamp bị dồn, nhiều vùng/offset, vùng rỗng và từ chối timing sai. Mock native kiểm lượt câu bỏ SOW/DTW/prompt SRT; UI kiểm báo phần bổ sung và vùng không tìm thấy lời. Không coi các mock/fixture này là kết quả nhận diện thật.

Kiểm cache project thật đọc 615 cue/7.591 từ SRT và 7.263 từ ASR legacy; 55.133.433 ô vượt được guard cũ, giữ 603 cue và xác định 12 cue cần nhận diện lại, cùng phần audio khác và CTA. Chỉ lập khoảng trên cache; không chạy ASR mới hoặc Premiere. Còn cần nghiệm thu nhận diện câu sau fallback DTW, chữ bổ sung/CTA, import, Play và Save trên project người dùng. SRT nguồn được đối chiếu hash không đổi. Xem [phạm vi bản sửa](releases/notes/NOTIFICATIONS_2.20.40.md).

Gói 2.20.40 đối chiếu đủ 65 payload, SHA256 `05C055270E45E2B333EEC009D7AE7AED6B1101AC8908A7C0F8C04C7F1D3F4A01`. Đã cài khi Premiere đóng, baseline khớp 2.20.39; 57/57 file panel đúng manifest, 608 file và 22 thư mục dữ liệu giữ nguyên qua hash trước/sau. Shortcut/helper đúng identity/checksum. Bằng chứng: `dist/_installation-2.20.40-20261015-222920/verified.json`. Không mở/đóng Premiere hoặc sửa project khi cài; nghiệm thu native còn chờ.

## Tạm dừng/tiếp tục 2.20.39

`workflow-pause.test.js` dùng fixture workflow thật để kiểm preflight, các engine, đầu/giữa lượt dựng và toàn phiên export; không có công việc nền/host khi đã nghỉ, không chạy lại ASR đã xong, click lặp, stop khi chờ điểm nghỉ/đang nghỉ/đang xác minh, lỗi giao diện và lỗi đọc/khác biệt trạng thái. `workflow-pause-host.test.js` chạy helper host thật qua VM: document/sequence, clip/source/timing/speed/mute, In/Out, bin, Caption Track có/thiếu API; playback/selection không làm sai so sánh. Metrics test loại thời gian nghỉ khỏi stage/processing và ghi riêng. Đây là kiểm giao thức/mocks; vẫn cần nghiệm thu Premiere thật.

Ngày 15/10/2026: đạt 36 nhóm, parse 101 PowerShell với `-NoWindowsIntegration` (bỏ qua sáu nhóm Windows integration). Chạy ngoài sandbox với TEMP fixture riêng để phép thử junction hoạt động. Edge headless với profile tạm riêng đạt 320/385/560 px và trạng thái pause/resume/stop ở hai chế độ; đã xem ảnh subtitle-paused-385. JS syntax, generated executor và diff whitespace đạt. Log: `dist/pause-2.20.39-tests.txt`; ảnh: `dist/_ui-preview-2.20.39`.

ZIP 2.20.39 đã đối chiếu 65 payload theo manifest, SHA256 `755D0ED157FB75E63EC92459B30C4CF0761EE3CC5F80E4B25B4EF3A9D63EC8EF`. Đã cài khi Premiere đóng và baseline khớp 2.20.38: 57/57 file panel đúng manifest, 605 file và 22 thư mục dữ liệu giữ nguyên qua hash trước/sau, shortcut/helper đúng identity/checksum. Bằng chứng: `dist/_installation-2.20.39-20261015-215254/verified.json`. Không mở/đóng Premiere hay sửa project; nghiệm thu native còn chờ.

## Dừng tác vụ 2.20.38

`Test-WorkflowCancellation.ps1` chạy UI/VM qua preflight, các engine, begin/advance/final của dựng và export, import caption, nút dừng lặp, chờ pending, cleanup sau callback, phục hồi timeline và ưu tiên lỗi engine/restore. Test tiến trình dùng worker PowerShell giả trong thư mục riêng: Unicode/quote/arguments, exit thành công/lỗi, script ngoài allowlist, hủy trước chạy, kết thúc cả worker/grandchild và giữ process không liên quan. Không gọi Premiere, nhận diện media hay sửa dữ liệu người dùng. Cần kiểm nút dừng và mute/In/Out trên Premiere thật; không thể suy nghiệm thu encoding/import/Play/Save từ test này.

Kiểm ngày 15/10/2026: `Run-Tests.ps1 -NoWindowsIntegration` đạt 36 nhóm, parse 101 script; sáu nhóm tích hợp Windows được bỏ qua. Lượt sandbox vướng cache fixture/junction; đã dùng TEMP riêng trong workspace và chạy bộ đầy đủ ngoài sandbox. Edge headless với profile tạm đạt hai chế độ tại 320/385/560 px, nút dừng đang chạy/đang yêu cầu dừng, khóa chạy và không tràn ngang; đã xem ảnh 385 px. JS syntax và generated executor check đạt. Log: `dist/cancellation-2.20.38-tests.txt`; ảnh: `dist/_ui-preview-2.20.38`.

ZIP đối chiếu đủ 65 payload theo manifest; SHA256 `6210A7996B7670EB7CAE9910C67B9503CD91150A820176D91B5A884C0AAA6C90`. Đã cài khi Premiere đóng bằng `dist/Install-Verified-2.20.38.ps1`, đối chiếu baseline 2.20.37: 57/57 file panel đúng manifest, 604 file và 22 thư mục dữ liệu giữ nguyên qua hash trước/sau, shortcut/helper đúng identity/checksum. Bằng chứng: `dist/_installation-2.20.38-20261015-214030/verified.json`. Không mở/đóng Premiere, không sửa project; nghiệm thu native còn chờ.

## Xuất audio qua nhiều lượt host 2.20.37

`Test-CaptionOnly.ps1` thêm test phiên host và `caption-export-ui.test.js`: không export trong begin, native chạy sau lượt đổi In/Out, một vùng mỗi lượt, guard token/thứ tự/snapshot/In/Out và khôi phục. Test panel kiểm yield trước mỗi native call, không retry và abort khi bridge lỗi. Đây là mô phỏng giao thức; không chứng minh nguyên nhân hoặc kết quả native Encoding 0%. Người dùng xác nhận WAV thủ công chạy ngay; cần thử bản sửa trên cùng project. Xem [ghi chú](releases/notes/NOTIFICATIONS_2.20.37.md).

## Chẩn đoán encoding 2.20.36

Test caption host thêm native trả false/số âm/chuỗi lỗi với WAV dở dang; kiểm dừng trước nhận diện, khôi phục mute/In/Out, các kiểu trả thành công, hằng AME thiếu, In/Out không được nhận và phạm vi lỗi. Test metrics kiểm phiên bản thực, chỉ lưu mã giai đoạn theo allowlist. Cần đối chiếu WAV thủ công và chạy Premiere thật để xác định vì sao 0%; chưa coi mock là bằng chứng đã hết kẹt. Xem [ghi chú](releases/notes/NOTIFICATIONS_2.20.36.md).

## Cô lập track voice 2.20.35

`Test-CaptionOnly.ps1` chạy host/VM kiểm WAV chỉ xuất khi các track khác mute và voice bật, khôi phục trạng thái hỗn hợp/voice vốn mute, nhiều vùng, lỗi xuất giữa chừng, lỗi thiết lập, lỗi khôi phục, track không hợp lệ và snapshot cũ. `caption-audio-ui.test.js` kiểm mặc định A2/A1, giữ lựa chọn, đổi sequence, track bị xóa/trống và khóa khi bận. Workflow UI kiểm truyền track vào job, chặn trước khi ghi/xuất/ASR nếu lựa chọn sai.

Cần nghiệm thu Premiere thật với nhạc A1/A3, voice A2 và track khác, nested/routing/hiệu ứng/Solo, lỗi xuất, Caption/Play/Save. Test mock không chứng minh WAV thực tế đã loại nhạc. Xem [ghi chú 2.20.35](releases/notes/NOTIFICATIONS_2.20.35.md).

Ngày 15/10/2026: đạt 35 nhóm / parse 99 PowerShell với `-NoWindowsIntegration`, bỏ qua sáu nhóm tích hợp Windows. Kiểm có junction và browser headless được chạy ngoài sandbox sau lỗi quyền trong sandbox; browser dùng profile tạm, không dùng phiên cá nhân. Bố cục 320/385/560 px đạt. Sau gia cố cuối, chạy lại host/UI caption, executor parity, JS syntax và kiểm version đều đạt. Chưa nghiệm thu Premiere hoặc cài panel thật.

## Sửa preflight caption-only 2.20.34

Chạy `tests/Run-Tests.ps1 -NoWindowsIntegration`: 35 nhóm đạt, 99 script PowerShell parse đạt. `caption-state.test.js` chạy biểu thức host được sinh thật để kiểm thiếu/có/sai `captionTracks`, In/Out thiếu/sai, đổi sequence và giữ chi tiết lỗi host. UI mock kiểm chạy SRT khi API caption không có; phục hồi giữ khóa khi Hủy, chỉ mở sau xác nhận kiểm tra caption thủ công và vẫn chặn In/Out/bin tạm đổi. Các nhóm thông báo dùng mock, không gọi cửa sổ hoặc toast Windows. Lượt sandbox bị chặn ghi cache fixture; bộ đầy đủ đã chạy ngoài sandbox với fixture riêng và đạt. Log: `dist/caption-state-2.20.34-tests.txt`.

Không đổi JSX/engine/executor của bản 2.20.33. Chưa chạy tạo caption trên project thật “Ý thức đến từ đâu”, chưa nghiệm thu Play/Save. File Source.srt đọc được 615 cue. Sau khi người dùng xác nhận lưu và đóng Premiere, đã cài bằng `dist/Install-Verified-2.20.34.ps1`: 56/56 file panel đúng manifest, 599 file dữ liệu và 22 thư mục giữ nguyên qua đối chiếu trước/sau, shortcut/helper đúng identity/checksum. Gói ZIP đối chiếu 64 file payload; SHA256 `2B02A4C8E28012379DD28D0DEBE2C7C1038CA3FFE4C87F9B5EB59351CE4F5002`. Bằng chứng: `dist/_installation-2.20.34-20261015-202814/verified.json`. Không tự mở/đóng Premiere hoặc sửa project khi kiểm tra/cài đặt.

## Nghiệm thu và promote 2.20.22

Ba lượt 2.20.21: dùng cache (203,412 s, timeline 137,891 s, 695 caption/229 đoạn voice); đổi thông số 69–131%, gap 1,1/2,1 s và speed voice 100% (281,313 s, timeline 169,846 s, 695 caption/227 đoạn); video/voice mới (55,118 s, timeline 17,218 s, 162 caption/72 đoạn, 4 nhận diện mới). Các trace đều profile no-delay, 24 host call, yield=0, batch limits disabled, mọi stage complete và hậu kiểm ok. Người dùng xác nhận không đơ, Save bình thường cả ba. Promote bỏ trial flag/prompt, giữ native generator/host/engine; test UI yêu cầu no-delay mặc định và không còn nhãn thử nghiệm. Đây là nghiệm thu trên máy người dùng với CUDA, không phải mọi hardware/project.

## Thử Auto edit không delay 2.20.21

Thêm profile `no-delay` vào các fixture parity 1/6/65/130 đoạn, voice 90/100/110%, gap và hình gộp. Yêu cầu toàn bộ native edits/report như host gốc; mọi stage complete không nhường đợt. Test UI yêu cầu không gọi setTimeout, trace đúng profile/no delay. Fixture bin caption không xóa được vẫn báo lỗi; fast gọi sleep 5 lần, no-delay không sleep. Guard timeline, thứ tự call và không Save/Undo tự động giữ nguyên. Mock không xác nhận Preview/Save thực tế; bản 2.20.20 được giữ để quay lại.

## Log workflow tự lưu 2.20.20

`workflow-metrics.test.js` chạy logger thật trên filesystem tạm, kiểm thời gian/cache, loại dữ liệu riêng tư theo whitelist, bằng chứng bước cuối khi không có finish, outcome lỗi, lỗi tạo/append/link không làm throw và retention chỉ xóa file riêng. Các mock UI Auto edit/Caption-only kiểm thứ tự từng stage, success/failure/cleanup và không gọi thêm host. Executor/engine được giữ nguyên; kiểm thử này không thay thế việc chạy trong Premiere.

`node tests/manual/Measure-WorkflowMetrics.js` đo 30 lượt logger thật với `security.js`, 19 event/lượt trong thư mục tạm riêng, không mở Premiere/media/model/cache. Ngày 2026-10-08: 5,10–10,01 ms/lượt, trung bình 6,07 ms. Đây là chi phí filesystem-only tại thời điểm đo, không phải cam kết latency trong Premiere hoặc trên mọi máy. 28 nhóm hồi quy/76 PowerShell parse, Node syntax và generated-executor check đạt cho bản này; native workflow mới còn cần người dùng chạy.

## Cache audio 2.20.19

Kiểm cục bộ: 28 nhóm hồi quy đạt, 76 PowerShell script parse; JS syntax, generated executor và diff whitespace đạt. Executor không đổi so với 2.20.18. Nghiệm thu toàn workflow/Play/scrub/Save trong Premiere còn chờ người dùng.

`Test-AudioCache.ps1` kiểm cold/warm JSON và quiet parity, cùng bytes khác path, audio đổi nhưng giữ length/mtime, prompt/language/DTW/model/exe/runtime revision, corruption/checksum, disable/restart, expiry và cleanup file atomic. Failed capture và GPU silent CPU fallback không được lưu dưới key thành công. Các harness planner dùng fixture detector riêng và cache disabled, không chạm cache người dùng. Package allowlist bắt buộc có `AudioCache.ps1`.

`tests/manual/Test-AudioCacheMedia.ps1 -MediaPath <voice> [-UseGpu]` dùng cache/temp riêng, không gọi Premiere. Kiểm byte equality của Whisper JSON qua bốn cặp cold/warm: legacy/DTW × không prompt/có prompt; quiet parity và hit/miss counts. Trên fixture voice ngắn ngày 07/10/2026, CUDA và CPU đều đạt 4 hits/4 misses, quiet 1 hit/1 miss, không lỗi. CUDA mới 776–1165 ms, warm 15–24 ms; CPU mới 2670–3145 ms, warm 15–45 ms. Không suy tỷ lệ này thành mức tăng tốc workflow, không phải nghiệm thu Play/Save hoặc chất lượng nghe nhìn của caption.

## First-exact lookup 2.20.18

Người dùng báo 2.20.17 chạy xong ổn. Log mới có finish ok; 418 exact hits/418 builds, 312 count changes, 0 reuse/fallback/candidate miss/invalid layout. Tra QE 28,648 s; host wall 281,005 s/113 calls, stage total 192,235 s. Không kết luận tăng tốc toàn workflow hoặc A/B từ một lần chạy.

Test 2.20.18 đối chiếu item/report/native calls với host: exact đầu tiên, nearest tie, near hit chưa được dừng, unordered/duplicate/nonfinite start, NaN/negative/infinite tolerance, gap chèn/xóa mỗi query, item đổi thứ tự/thay proxy, unreadable fields và getItemAt error. Có 120 fixture có seed/1.800 query với layout thay đổi giữa query. Full executor vẫn giữ voice speed 90/100/110%, A2/caption/marker/CTA/Adjustment, guard/yield/abort và report parity; log phải đếm đúng native item reads, 0 index builds.

Fixture 200 clip/100 query nửa đầu track: 20.000 → 5.050 item reads khi count ổn định; chèn gap sau mỗi clip vừa tra (count đổi mỗi query): 24.950 → 10.000. Đây là mô phỏng, không phải số liệu tăng tốc Premiere. Case không exact vẫn phải đọc toàn track. Cần nghiệm thu bản mới với Auto edit, Play/scrub/Save và log thời gian/reads.

Kiểm cục bộ 07/10/2026: 27 nhóm test qua, 73 PowerShell script parse; JS syntax/generated-source check và diff whitespace qua. Test installer chỉ chạy fixture riêng; native 2.20.18 chưa nghiệm thu.

## Chỉ mục QE 2.20.17

Test helper dùng track wrapper mới ở mỗi query, tách khóa V/A, đọc candidate mới, gap insert/remove buộc rebuild, count giữ nguyên nhưng index sai buộc fallback, replacement cùng start trả item mới; reset mỗi đợt không dùng cache cũ. Đối chiếu nearest/exact/negative tolerance/NaN, duplicate/unordered/nonfinite starts và 120 fixture ngẫu nhiên có seed (1.800 query); khóa không được generator cấp và baseline dùng lookup gốc.

Fixture 200 clip/100 query với count ổn định: tra gốc đọc 20.000 QE item, tra mới đọc 300 (200 dựng index + 100 xác minh candidate). Đây là số lần đọc mock, không phải tỷ lệ tăng tốc trong Premiere. Full executor đối chiếu mọi native editing call theo đúng thứ tự và report với host gốc trên các kế hoạch V1/A1/A2, speed voice 90/100/110%, gộp/marker/CTA/Adjustment và nhiều đợt. Không đổi điểm cắt, timestamp hay lệnh setSpeed; guard/abort/yield vẫn kiểm riêng.

Nghiệm thu native còn cần: cùng template/input/settings với 2.20.16, không tương tác trong lúc chạy, Play/scrub/Save sau hoàn tất bình thường; đối chiếu log queries/builds/reuses/countChanges/candidateMisses/invalidLayouts và thời gian dựng. Không khẳng định đã tăng tốc thực tế từ test mô phỏng.

Kiểm cục bộ 07/10/2026: 27 nhóm hồi quy qua, 73 PowerShell script parse; JS syntax và generated-source check qua. Test bộ cài chạy trong fixture riêng, chưa cài vào panel thật. `host.jsx`, engine và UI runtime không thay so với 2.20.16.

## Nút xác nhận 2.20.16

Hồi quy kiểm acceptWorkflowNotice có class primary, CSS màu foreground/background tường minh ở normal/hover/active. Tính luminance từ các mã màu thật trong CSS, yêu cầu text contrast ≥4,5:1; kết quả 6,48/8,34/10,42:1. Các ca wait/cancel/busy/cache/export/Caption-only và wire tiếp tục chạy. Đây là kiểm CSS/mocks, không thay thế đánh giá thị giác trên panel Premiere. main.js/engine/JSX/generator giữ nguyên so với 2.20.15; chưa thực hiện các đề xuất tăng tốc.

## Thống nhất thông báo 2.20.15

Người dùng xác nhận 2.20.14 không tụt cửa sổ Premiere ra sau app khác khi hiện kết quả. 2.20.15 thay các xác nhận/thông báo còn lại bằng cùng box DOM, không thay engine/executor.

Mock UI kiểm xác nhận phải chờ lựa chọn thật, Hủy không tạo job/ASR/dựng hoặc xóa cache, click lặp không resolve hai lần, không ghi đè xác nhận đang chờ, chặn tác vụ khác khi chờ xóa cache. Kiểm xóa đúng Cache/Whisper; xuất log dùng đầu ra redaction và ghi wx, hủy file picker không ghi, lỗi picker/ghi file hiện box chung. Chẩn đoán success/error không ghi file/sửa timeline. Checkpoint Tiếp tục/Dừng vẫn giữ wait/abort; một box/nút hành động, không còn alert/confirm/prompt toàn panel, textContent an toàn, nội dung dài cuộn, hàng nút wrap.

Giao diện đã bỏ mục dựng thử/chẩn đoán hiệu năng, hai nút baseline/fast và checkbox dừng từng nhóm; test kiểm HTML không chứa và wire không gắn listener cho các control đã bỏ. Bộ test và đường đối chiếu nội bộ vẫn giữ, engine/JSX/generator không đổi.

Kiểm cục bộ: 27 nhóm hồi quy qua, 73 PowerShell script parse; JS syntax và generated-source check qua. Thêm phép khởi tạo wire với đúng inventory ID từ HTML (thiếu control sẽ lỗi), chạy handler xác nhận/đóng/reset thật trong mock. Test bộ cài chạy ở fixture riêng, không cập nhật panel đang dùng. Đây là bằng chứng tự động, chưa phải nghiệm thu giao diện Premiere 2.20.15.

Nghiệm thu native còn cần kiểm Auto edit Bắt đầu/Hủy, xóa cache Hủy, xuất log và Caption-only; Premiere giữ foreground, Preview/Save bình thường. Mock/CSS không chứng minh z-order, bố cục render thật hoặc media engine native.

## Thông báo kết quả 2.20.14

Người dùng báo 2.20.13 kết quả tương đối chấp nhận được, không lỗi nghiêm trọng/đơ, Save bình thường; Premiere tụt ra sau ngay khi alert hoàn tất xuất hiện, không phải sau OK. Bản UI này bỏ native alert cuối tác vụ, không đổi engine/executor. Chưa có nghiệm thu native việc giữ foreground sau thay đổi.

`workflow-notice-ui.test.js` kiểm DOM-only/no focus/new window, dùng textContent với chuỗi HTML không diễn giải, thông báo dài giữ đủ, thay kết quả/đóng/ẩn lúc bắt đầu, busy trở lại bình thường không ẩn kết quả mới. Caption-only chạy qua success có/không reference và lỗi phạm vi/engine/apply; không gọi alert và vẫn cleanup/finally. UI default Auto edit kiểm success/error cũng không gọi alert; confirm trước dựng giữ nguyên. CSS có vùng cuộn riêng, HTML đúng một box/nút đóng. Kiểm thử mock không đo z-order/foreground Windows hoặc chứng minh đã hết tụt cửa sổ.

Kiểm cục bộ: 27 nhóm test qua, 73 PowerShell script parse; JavaScript syntax, UI notice/default workflow, host mock và generated-source check qua. Git diff xác nhận engine/JSX/generator không đổi so với 2.20.13. Installer chỉ kiểm trong fixture riêng, chưa cập nhật panel thật ở bước test.

## Tích hợp mặc định 2.20.13

UI mock kiểm một xác nhận đúng nội dung, hai preflight trước ASR, workflow mặc định DTW/gộp/fast, bỏ ô thuật toán thử, no-op vẫn dựng và template đổi thì chặn. Nút chẩn đoán giữ kế hoạch cơ sở. Full executor mock đối chiếu toàn bộ native editing calls/report giữa host, baseline và fast trên kế hoạch gộp 1/6/65/130 đoạn với voice 90%/100%/110%; A2 vẫn riêng, mọi cặp hình có đúng một marker trong khoảng source, số cảnh báo chỉ đếm speed ngoài ngưỡng.

Marker test kiểm tag mới, đúng mẫu legacy, tên gần giống/tự đặt/marker không rõ giữ lại, scope source nửa mở, owner V1/A1 dùng chung, các khoảng của cùng voice được hợp và ánh xạ đầy đủ trước khi xóa. Fixture dựng có marker cũ từ trước, marker thủ công và marker ngoài source; xác nhận chỉ hai marker thuộc vùng được dọn, manual/ngoài vùng giữ và không xóa marker mới. Native proxy cleanup owner được rebind trước đợt.

Mock màu kiểm đỏ/cam theo hai phía ngưỡng, vàng A2, xanh dương nhóm gộp trong ngưỡng, nhóm gộp ngoài ngưỡng vẫn đỏ/cam. Giả lập native setter lỗi: marker vẫn đúng vị trí/ghi chú và hậu kiểm timeline đạt, báo ba lỗi màu riêng, không yêu cầu Undo chỉ vì lỗi màu. Cần nhìn màu trong Premiere thật khi nghiệm thu.

Kiểm cục bộ: toàn bộ 27 nhóm test qua, 73 PowerShell script parse; JS syntax, generator hash/current-source và UI/host mock qua. Bộ cài chỉ chạy trong fixture riêng, không cập nhật panel thật trong bộ test.

Người dùng đã nghiệm thu riêng DTW/gộp và profile fast 2.20.12 không đơ Preview/Save. Bản kết hợp 2.20.13 cùng marker mới chưa nghiệm thu trong Premiere; phải kiểm trên template sạch, nghe điểm cắt, xem marker từng nhóm gộp và thử Preview/Play/Save trước Release. Unit/mock không mô phỏng media engine Adobe. Các phần dưới là lịch sử kiểm thử của từng phiên bản.

## Thử nghiệm Auto edit DTW riêng, mặc định tắt

Người dùng đã nghiệm thu bản căn caption 2.20.4 hoạt động tốt. Harness `experiments/auto-edit-dtw` (đã gỡ 13/11/2026) từng đối chiếu planner trên ba chapter tại 30 và 29,97 fps, 222→227 nhóm với năm điểm cắt mới. Giữ mọi điểm cắt cũ, vùng nguồn/voice sử dụng, tổng thời lượng, khoảng không lời và toàn bộ chữ caption. Cảnh báo tốc độ 23→24; không tuyên bố tốc độ tốt hơn ở mọi đoạn. Sáu ranh giới thiếu bằng chứng không được thay; chapter 2 vẫn fallback do một chuỗi DTW chung anchor khoảng 152,70 giây. Bản thử 2.20.5 có nút opt-in riêng, không đổi thuật toán dựng thường; đã cài ngày 2026-10-06 sau khi người dùng xác nhận đóng Premiere. Cả 43 file extension đã đối chiếu hash với gói; cache/model/backend giữ nguyên. Chưa nghiệm thu timeline DTW thật.

`Test-BoundaryTrial.ps1` chạy riêng, kiểm hai frame rate, không dùng padding caption làm mốc cắt, các ca từ chối và conservation. `Test-ReviewAudio.ps1` kiểm WAV đúng thời lượng/cấu trúc, 20 ms ở mép cắt có năng lượng thấp. Mười WAV tại mỗi fps đã qua kiểm tra. Ngày 2026-10-06 người dùng nghe năm cặp trước/sau và xác nhận tất cả không xén vào lời; xác nhận này chỉ áp dụng cho các điểm cắt đã nghe, không suy rộng cho mọi voice/chapter/frame rate. Media, kết quả và đường dẫn riêng tư ở `_local/` bị Git bỏ qua. Bộ ổn định vẫn 23 nhóm qua; mọi script được parse, nhưng CI không bật thuật toán thử nghiệm. Chưa có nghiệm thu executor/V1-A1/Premiere thật cho các điểm cắt mới.

Bản thử yêu cầu chọn và xác nhận hai lần; nút dựng ổn định và executor không đổi. Phải tạo lại job từ template Premiere thực tế, đối chiếu baseline/candidate và kiểm conservation trước khi dựng. Không mở khóa file `candidate-plan.DO-NOT-APPLY.json`: dữ liệu V1/A1 của nó chỉ là fixture. Quy trình nghiệm thu và các điều kiện dừng được ghi tại `experiments/auto-edit-dtw/README.md`; không tự cài panel, đóng Premiere, sửa timeline hoặc gộp Release từ kết quả nghe.

`Test-DtwEditTrial.ps1` kiểm opt-in, schema/định danh template, voice In 0 với speed 50/90/110/150% và sai số số thực quanh 100%, bảo toàn các trường kế hoạch và định danh điểm cắt cũ/mới. Metadata không hợp lệ/trim đầu phải bị từ chối; CTA ngoài nhóm chính không bị kiểm nhầm. `node tests/unit/dtw-trial-ui.js` mô phỏng đường UI thật: nút thường không gọi wrapper thử, checkbox chưa chọn không chạy, hủy ở cả hai xác nhận, report lỗi/không có điểm mới/template đổi không gọi executor; metadata lỗi dừng trước ASR; cleanup và reset consent đều chạy. CI chỉ chạy các chốt/mô phỏng, không chạy ASR hay bật đường thử trên timeline.

`Test-DtwEditTrialMedia.ps1 -FixtureRoot <run-private> -FrameRate <fps>` kiểm toàn wrapper mới với audio thật, alignment đã nhận diện và metadata file được xác minh. Dùng template mock có nhãn rõ trong fixture tạm, không gọi Premiere; không xuất candidate live ra ngoài. Baseline/job/alignment và media gốc phải giữ nguyên. Đã qua ở 30 và 29,97 fps: 222→227 nhóm, năm điểm cắt mới, bảo toàn và giữ mọi cut cũ. Đây chưa phải nghiệm thu V1/A1/Premiere thật. Bộ unit hiện có 24 nhóm qua, 68 script parse được; UI mock qua.

Bản thử 2.20.6 sửa chốt 100% quá hẹp. Project copy lưu trước lần lỗi cho thấy ba chapter có playback speed 1.1 (110%) và media In 0; không phải sai số metadata. Các bộ quy đổi word timing và quiet đã hỗ trợ 100/speed; không đổi nhận diện/planner/executor ổn định để sửa chốt này. `-VoiceSpeeds` kiểm fixture speech alignment cũ được quy đổi theo từng chapter; không được gọi đó là fresh ASR. Trường hợp 110/110/110 tại 30 fps qua với 224→229 nhóm/năm cut mới; 90/110/125 tại 29,97 fps qua với 222→227 nhóm/năm cut mới; 50/90/150 tại 30 fps qua với 218→225 nhóm/bảy cut mới. `-FreshAlignment` chạy lại đường căn thật (raw Whisper cache đã xác minh khi có; cửa sổ nhận diện lại chạy native) trong AppData/TEMP fixture, không thay cache thật. 110% fresh alignment cũng cho 224→229 nhóm và bảo toàn speed/nguồn/voice/caption. Đây chỉ kiểm quy đổi/bảo toàn, không phải nghiệm thu nghe các cut mới ở tốc độ khác. Không thao tác timeline Premiere; vẫn cần nghiệm thu bằng nghe nhìn.

## Tự động

Bản thử 2.20.4: `Test-CaptionDtwTiming.ps1` kiểm ranh giới trước token (không offset cố định), từ SOW duration 0, bốn khoảng nghỉ thật, bảo vệ dấu câu, padding độc lập, frame 30/29.97, giữ input dựng và GPU→CPU fallback. `Test-ReferenceCaptionMedia.ps1 -AcceptedCaptionSrtPath <srt>` đối chiếu kết quả tích hợp với SRT đã nghiệm thu. Chapter 1: 334 caption khớp toàn bộ chữ và hai mép trong 1 ms; chưa phải nghiệm thu panel Premiere.

`Test-DtwCaptionIntegrationMedia.ps1` đối chiếu alignment/planner cũ với mới trên media chỉ định. Không gọi executor hoặc sửa Premiere. Kiểm toàn bộ segment/marker/mốc dựng giống nhau; báo vùng DTW fallback. Audit điểm cắt chỉ đếm khả năng tìm khoảng lặng với mốc cũ/mới, không tạo kế hoạch DTW hay chứng minh cut mới tốt hơn. Bản nhận diện DTW mới chưa được dùng thay điểm cắt/tốc độ Auto edit.

Đối chiếu ba chapter: 695 caption đủ chữ, 150 cue dùng overlay DTW; chapter 2 và cue 304–305 giữ timing cũ vì chưa xác minh được. Cả segment, marker và dữ liệu căn dùng dựng giống bản 2.20.3. Audit 120 ranh giới câu: 109 ứng viên khoảng lặng theo mốc cũ, 120 theo DTW; 109 ứng viên cũ giữ nguyên frame. Xem `experiments/auto-edit-dtw/README.md` để biết giới hạn và gate nghiệm thu. Bộ tự động hiện tại: 23 nhóm qua, 60 script parse được.

Chạy từ thư mục repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Bộ này kiểm cú pháp PowerShell/XML, hợp đồng UI 130%, chẩn đoán chỉ đọc, planner theo frame, caption một dòng ưu tiên dấu câu rồi vùng nghỉ hơi được xác nhận trên voice, cắt voice an toàn, Unicode, marker, bootstrap host và vòng đời cài/gỡ. GitHub Actions chạy cùng bộ test trên checkout sạch, không cần runtime lớn.

`Test-CaptionOnly.ps1` kiểm nội dung/timestamp ASR, tái dùng căn SRT, giữ cụm từ, giữ mép caption không padding (từ 2.20.89), giới hạn từng vùng chọn và chữ Trung/Nhật. Bộ mock host kiểm chọn clip linked, vùng rời nhau, toàn sequence, khôi phục In/Out khi export thành công/lỗi, dọn bin caption và từ chối timeline đã thay đổi. Các kiểm tra này chưa phải nghiệm thu export/caption thật trong Premiere.

`Test-CaptionVoiceAlignment.ps1` thêm hồi quy “Trong Alien: Covenant…”, các cụm ngắn “Hôm nay,”/“Năm 1979,” và mặc định không padding; padding 5 frame chỉ còn khi gọi tường minh, không overlap. `Test-NumericCaptionTiming.ps1` kiểm integer, decimal, percent trong gợi ý, giữ nguyên số mơ hồ/tên mã, từ chối recognition không đủ và xác nhận timestamp dựng gốc không thay đổi khi thêm timing riêng cho caption.

`Test-CaptionInitials.ps1` kiểm tên viết tắt có khoảng trắng/dạng liền, giữ họ đi kèm, giữ dấu kết câu thông thường và không chia cue ASR giữa các chữ viết tắt. Bản thử 2.20.3 có các ca hồi quy riêng cho thời lượng “Hôm nay…” và nghỉ hơi sau “Engineer”; vẫn chờ nghiệm thu Premiere.

`Test-WhisperPromptEncoding.ps1` kiểm byte UTF-8 của prompt tại ranh giới gọi native, chỉ một đối số response-file không có tên executable dư, từ chối newline và dọn file đối số. `Test-NumericCaptionTiming.ps1` kiểm thêm số viết bằng chữ/số bị chia thành nhiều token, giữ đủ span và từ chối sai giá trị/ngữ cảnh. Bộ 2.20.3: 22 nhóm test qua; 54 script PowerShell parse được.

Kiểm pipeline 2.20.2 bằng media thật: chapter 1 chọn đúng cue 1–143, 333 caption; 12 cue đọc số được nhận diện lại, ba cue 23/56/57 giữ timing cũ và báo cần nghe lại. Chapter 2 chọn cue 144–296, 344 caption, ba cue đọc số nhận diện lại và cue 219 báo cần nghe lại. Chapter 3 giữ cue 297–305, 15 caption. Auto edit đủ 305 cue, 691 caption, 222 nhóm câu; giữ nội dung, không overlap và vẫn phục hồi cue 303–305. `Test-NumericCaptionMedia.ps1` chạy riêng một cue với CPU/CUDA, có tham số khoảng timestamp ground-truth tùy chọn để kiểm khi đã có annotation từ nghe thực tế. Các số liệu này kiểm pipeline, không chứng minh timestamp đọc số chính xác: Whisper có thể cho thời điểm khác khi thay cửa sổ audio; một khoảng im lặng không tự chứng minh đó là mép của số. Cần nghiệm thu bằng nghe nhìn trong Premiere.

`Test-SubtitleReferenceVariants.ps1` có 14 kiểm tra cho cue "Be…"/"b" và "Đừng đùa!"/"đừng đua", giữ nguyên chữ/timestamp/confidence; từ chối sai từ, thiếu timing, thiếu/ yếu mốc neo, block quá dài, khác ngôn ngữ, khác khoảng chọn và span mơ hồ. `tests/manual/Test-ReferenceCaptionMedia.ps1` chỉ đọc media/SRT được truyền rõ qua tham số, không tìm dữ liệu người dùng hoặc sửa project; chạy Whisper thật, kiểm nội dung, một dòng, thời lượng dương, không overlap/vượt audio, rồi dọn WAV/JSON/SRT tạm. Lần tái hiện 2026-10-05: 68 cue tham chiếu tạo 133 caption; bốn cue biến thể được báo nghe lại. Chưa phải nghiệm thu nghe nhìn trong Premiere.

`Test-SubtitleReferenceScope.ps1` kiểm prefix/middle/suffix/full SRT, offset timeline thay vì timecode cũ, nhiều vùng rời nhau và CJK; từ chối nội dung sai, lặp mơ hồ, cắt giữa cue, thiếu cue bên trong và đảo thứ tự. Kiểm thêm retry đuôi bình thường/đẩy token quá mép/bỏ sót lời, offset đúng và không retry khoảng im lặng; từ chối đuôi vẫn chưa xác minh hoặc thiếu mốc cắt an toàn. `Test-CaptionOnly.ps1` kiểm mép audio nằm giữa hai frame không làm caption vượt vùng chọn.

Kiểm bằng Whisper CUDA thật ngày 2026-10-06: ba chapter “Tàu vũ trụ không phải là một cỗ máy” với cùng SRT 305 cue lần lượt chọn đúng cue 1–143 (353 caption), 144–296 (356 caption), 297–305 (16 caption). Chapter 1 và 3 cần một lần retry đuôi; nội dung SRT giữ nguyên, không overlap/vượt audio. Hồi quy “Tại sao cừu…” giữ đủ 68 cue, 133 caption và bốn cue biến thể cần nghe lại. Không chỉnh project hoặc gọi executor; đây không phải nghiệm thu nghe nhìn/caption thật trong Premiere.

`Test-MissingWordTimingRecovery.ps1` kiểm nhận diện lại block thiếu timestamp từ, offset chapter, không remap mốc neo, cùng 10 trường hợp phải từ chối. Kiểm thêm hòa ranh giới caption chồng đúng 1 frame và từ chối chồng lấn lớn hơn. `tests/manual/Test-AutoEditAlignmentMedia.ps1` nhận rõ thư mục voice/SRT, chạy alignment và planner thật nhưng không gọi Premiere; có thể dùng bản sao cache/backend có sẵn trong fixture riêng, không tải GPU. Mọi dữ liệu tạm tự dọn; không sửa voice/SRT/project gốc.

`Test-PanelRegistry.ps1` dùng khóa HKCU riêng có tên ngẫu nhiên và thư mục fixture riêng, không dùng registry CEP thật. Kiểm thiết lập không đăng ký Installed apps, chuyển từ mục đăng ký cũ đúng tool, giữ cache, thiết lập nhiều lần, khôi phục PlayerDebugMode khi gỡ và từ chối đăng ký của ứng dụng khác. Kiểm fixture không thay thế nghiệm thu trên máy khác.

Để nghiệm thu subtitle độc lập: chạy trên một clip ở giữa timeline, nhiều clip rời nhau, toàn sequence không chọn clip, sequence có nest và audio nhiều track, với/không SRT tham chiếu, tiếng Việt và một ngôn ngữ khác. Xác nhận video/audio giữ nguyên, In/Out cũ được khôi phục, caption đúng vị trí, không có SRT/bin tạm trong Project. Nghe lại rồi lưu/đóng/mở project để kiểm caption còn nguyên.

`tests/manual` chỉ chạy khi truyền fixture cụ thể. Không script nào ở đó được tự tìm dữ liệu trong project hoặc thư mục tạm của người dùng.

`Test-StandaloneCaptionEngine.ps1` là ngoại lệ có chủ đích: nó tự tạo giọng mẫu tiếng Anh bằng Windows TTS, chạy FFmpeg/Whisper thật và kiểm cả chế độ tự nhận diện/SRT tham chiếu, rồi xóa mẫu. Nó không tìm hay dùng media của người dùng; không kiểm được API export/caption trong Premiere.

## Nghiệm thu trong Premiere Pro 26.2.2

`Test-CaptionBreathAttribution.ps1` dùng chữ/timestamp từ file voice được cung cấp: ca “Engineer” phải chia đúng ba caption, dùng tâm khoảng nghỉ 39.643–39.941 giây ở cả 30 và 29.97 fps; ca “Hôm nay,” không gán nghỉ dấu phẩy cho các từ tiếp theo. Kiểm âm thấp trong lòng từ, khoảng quá ngắn/vùng không liên quan không được đổi cách chia, đồng thời toàn bộ mốc edit đầu vào giữ nguyên. Đây là kiểm hồi quy trên dữ liệu âm học/timestamp, không thay thế nghe lại.

Kiểm media thật bản thử 2.20.3 bằng CUDA: chapter 1 đủ cue 1–143, 333 caption; câu “Engineer” cho đúng ba caption ở 37.871–39.806 / 39.806–41.642 / 41.642–43.176 giây (29.97 fps). “Hôm nay…” không còn kết thúc caption chứa “chúng ta” tại 64.264 giây. Auto edit đủ 305 cue, 693 caption, 222 nhóm dựng, phục hồi cue 303–305 và giữ đủ chữ/không overlap; câu “Engineer” chia cùng ba phần. Không gọi executor/Premiere, không sửa file gốc. So sánh với SRT xuất chỉ tạo danh sách điểm cần nghe lại, không chứng minh mọi chỗ lệch đã được sửa.

`Test-ReferenceCaptionMedia.ps1 -ExportedCaptionSrtPath ... -FrameRate ...` đối chiếu toàn bộ caption xuất với kết quả mới theo chỉ số từ, báo các điểm cắt bị bỏ/thay đổi và giữ đủ chữ. Các vị trí thay đổi là danh sách cần nghe lại, không phải chứng minh mọi timestamp mới đều chính xác hơn.

Kiểm tra tự động không thay thế nghiệm thu thật trong Premiere. Trước Release cần dùng một bản sao project:

1. Mở template sạch có V1 nested, A1 linked và các chapter A2.
2. Bấm Chẩn đoán; xác nhận báo sẵn sàng và không có thay đổi timeline.
3. Xác nhận mặc định cảnh báo nhanh là 130% và tốc độ thực tế vẫn có thể vượt ngưỡng.
4. Chạy dựng, kiểm hình liên tục, V1/A1 linked, A2 không xén lời, marker đúng clip và caption tồn tại.
5. Với cue dài, xác nhận mỗi caption chỉ hiện một dòng và đổi đúng tại ranh giới từ đang được đọc; thử dấu câu, câu không dấu câu nhưng có nghỉ hơi, câu không nghỉ hơi, tên riêng và số.
6. Dùng Rate Stretch Tool trên một đoạn đã dựng và kéo master nest sang sequence khác.
7. Lưu, đóng, mở lại project và kiểm caption/timeline.

Chỉ sau các bước này mới có thể gọi là nghiệm thu end-to-end; test tĩnh không được mô tả là đã kiểm phát lại hình/tiếng.

## Kiểm thử gộp hình 2.20.7

Ở 2.20.7, `Test-SpeedMergeTrial.ps1` kiểm hai hướng, weighted speed, gộp lặp/dừng ở ngưỡng, qua chapter, gap/voice gap, fallback giữ cảnh báo, nguyên vẹn baseline/A2/caption/marker và 80 trường hợp frame ở 30/29,97 fps. `speed-merge-host.js` chạy helper host thật bằng mock, kiểm kế hoạch hợp lệ và từ chối sai coverage/speed/gap/tail trước khi chạm Premiere. UI mock kiểm đường mặc định không dùng lựa chọn, cả hai bật, merge-only không có cut DTW mới, report sai, no-op và hủy. Những kiểm tra này không mô phỏng toàn bộ QE/Premiere.

Harness media `Test-DtwEditTrialMedia.ps1 -SpeedMerge` chạy wrapper mới bằng alignment đã nhận diện/audio thật, giữ file/job/baseline/DTW candidate và media nguyên vẹn. Mẫu ở 30 fps, voice 100%: hình 227→199, gộp 28 lần, cảnh báo 70–130% từ 24→0. Voice 110%: hình 229→211, 18 lần gộp, cảnh báo 15→0. Voice 90/110/125% ở 29,97 fps: hình 227→185, 42 lần gộp, cảnh báo 38→0. Không gộp qua chapter trên ba mẫu này; ca qua chapter kiểm riêng ở unit/host mock. Caption và toàn bộ A2 byte-equivalent theo JSON so với kế hoạch trước gộp. Đây là kiểm conservation/planning bằng scaled prior alignment, không phải fresh ASR hoặc nghe nhìn timeline sau gộp.

Đã qua toàn bộ 25 nhóm test, 71 PowerShell script parse; JS syntax, UI và host guard mock qua. Bộ cài được test trong fixture tạm, không thay panel thật. Chưa nghiệm thu đoạn hình gộp trong Premiere; không cập nhật panel hoặc merge main/Release tự động.

## Quy tắc một cặp duy nhất từ 2.20.8

Protocol v2 chặn gộp tiếp ở cả target và neighbor. Test đã đổi sang kiểm nhóm còn dưới/trên ngưỡng vẫn dừng sau một lần, cặp đạt không bị đoạn khác tái sử dụng, planner/host từ chối ba members hoặc protocol v1, và 80 ca frame đều có tối đa hai members. Toàn bộ 25 nhóm test/71 script parse và UI/host mock qua.

Harness media dùng voice 110% tại 30 fps: 229→215 đoạn hình, 14 cặp, cảnh báo 15→3. Mỗi nhóm tối đa hai đoạn đầu vào; A2/caption và tổng nguồn/thời lượng không đổi. Ba cảnh báo còn lại được giữ để host đặt marker khi dựng, không tiếp tục gộp. Đây là kiểm kế hoạch/coverage bằng scaled prior alignment, chưa nghiệm thu marker hoặc phát lại timeline Premiere.

## Bản thử tránh mở lại sequence 2.20.9

`Test-HostSequenceRestore.ps1` chạy JavaScript mock trên phần `finally` lấy từ host thật: cùng ID (kể cả khác kiểu number/string) không mở lại; khác ID hoặc không có sequence thì mở một lần; không có original thì không đọc app; lỗi đọc/mở vẫn được trả về cleanupError. Mock executor thật cũng kiểm đường preflight lỗi không gọi QE hoặc mở lại sequence đang hoạt động. Đây là kiểm logic guard, không mô phỏng thread/media engine hoặc chứng minh hết lag.

Kiểm cục bộ: 26 nhóm test qua, 72 script PowerShell parse; JS syntax, UI DTW mock và speed-merge host mock qua. Lần chạy sandbox đầu bị chặn rename fixture bộ cài; chạy lại toàn bộ ngoài sandbox với thư mục/registry fixture riêng đã qua, không cập nhật panel thật.

Nghiệm thu cần bắt đầu bằng nút dựng ổn định trên template chưa dựng của cùng project gây lỗi. Sau hoàn tất, kiểm scrubbing/Play trên Program Monitor và lưu project, trước khi đóng/mở lại Premiere. So với bản đang cài 2.20.7, bản 2.20.9 còn kế thừa giới hạn gộp một cặp của 2.20.8; không dùng DTW/gộp trong phép đối chiếu đầu tiên để tránh nhiễu. Người dùng sau đó xác nhận 2.20.9 vẫn lag; không coi guard này đã sửa nguyên nhân.

## Bản chẩn đoán chia đợt 2.20.10

`Test-DiagnosticExecutor.ps1` kiểm source sinh đồng bộ với host ổn định, native-call parity và toàn bộ report parity với 1/6/65 đoạn, cả trường hợp bỏ lát khoảng lặng rồi dồn A2. Test nhiều đợt, bốn checkpoint, duplicate/order/token, thay sequence/clip giữa đợt, abort trước/sau mutation, caption thiếu và không tự Save/xóa Undo. UI mock kiểm timer ngoài host, nhiều evalScript riêng, checkpoint tiếp tục/dừng, không retry lỗi evalScript, hash không khớp chặn trước mutation và không ghi dữ liệu riêng vào log hiệu năng.

Kiểm cục bộ: 27 nhóm qua, 73 script PowerShell parse; UI DTW, host gộp tốc độ, syntax/ID UI và package allowlist/hash qua. Mock cũng kiểm voice 90%/110% và proxy slice đã remove không được đọc lại. Test installer đầu tiên bị sandbox chặn rename fixture; chạy lại với fixture thư mục/registry riêng ngoài sandbox đã qua, không cập nhật panel thật.

Các kiểm thử trên không giả lập bộ xử lý audio/player hay chứng minh hết lag. Nghiệm thu trên Premiere: template sạch trong phiên Premiere mới, dừng từng nhóm, ghi thời điểm Preview/Play bắt đầu lag; nếu hết lượt thì kiểm Save. Không lưu timeline một phần, không tự force-close ứng dụng. Nút ổn định/DTW cũ vẫn kiểm riêng.

## Thử tối ưu chia đợt 2.20.11

Người dùng xác nhận chia đợt tự động 2.20.10 hoàn tất không đơ và Save bình thường. Đây là nghiệm thu lần chạy đó, không phải bảo đảm mọi project. Log đo phần executor 333,165 giây/296 lượt, trong đó timer 150 ms chiếm 44,4 giây; tổng host-call 274,713 giây còn bao gồm guard/rebind. Chưa có đo tách native work trong bản cũ.

Unit chạy full native editing-call/report parity giữa stable và cả baseline/fast với 1/6/65/130 đoạn, gap A2, voice 90%/110%, proxy đã remove. Kiểm fingerprint nguyên vẹn, đổi nguồn/speed/vị trí dừng trước mutation, giảm QE reads trong mock và mọi timing field không âm. Helper kiểm exact/nearest, duplicate, không thứ tự, gap, tolerance âm, số item thay đổi, stale index/proxy và snapshot byte-identical. UI kiểm profile/timer 20/150 ms, trace không chứa dữ liệu riêng, không retry/abort phiên khác. JSX string được escape Unicode; checkpoint giữ nguyên tiếng Việt.

Toàn bộ 27 nhóm test/73 PowerShell script parse qua; sandbox đầu chặn tạo junction fixture bảo mật, chạy đầy đủ ngoài sandbox với fixture riêng đã qua. JS syntax, UI DTW và speed-merge mock qua. Stable `host.jsx` và toàn bộ engine không đổi.

Tốc độ thực tế và Preview/Save của fast chưa được nghiệm thu trong Premiere. Cần cùng template/input, phiên mới, không scrub/Play trong lúc chạy, sau hoàn tất mới kiểm Preview/Play/Save. Log mới có các thành phần thời gian để xác định chi phí còn lại; `qeLookupMs` nằm trong `workMs`, không cộng trùng.

## Post-snapshot gia tăng 2.20.12

Sau đó người dùng xác nhận lần fast 2.20.11 Preview/Save bình thường. Log riêng phần executor: 245,397 giây/126 lượt; full guard 37,843 giây và post-snapshot 55,502 giây. Lần chạy nút chính tiếp theo không ghi đè file Performance riêng.

Test mới kiểm post-speed snapshot byte-equivalent với full scan, chỉ đọc chi tiết dirty clip; marker reuse đúng, fallback khi đổi count/track/order/ID, missing dirty hoặc duplicate IDs. Đổi nguồn ở track không được ghi nhận không bị hấp thụ vào expected state. Full executor mock kiểm thay speed/nguồn A2 sau đợt speed V1–A1 bị guard phát hiện trước edit kế tiếp, mọi source edits/cut/move/caption/audit vẫn full post-scan. Parity toàn bộ native editing calls và report với stable, baseline, fast giữ nguyên trên 1/6/65/130 đoạn và voice 90%/110%.

Đây không phải bằng chứng native Premiere không có side effect ngoài dirty clip. Cần nghiệm thu bản thử mới trên template sạch, kiểm timeline, Preview/Play và Save; không hứa mức tăng tốc trước log thực tế.

Kiểm cục bộ 2.20.12: toàn bộ 27 nhóm test/73 PowerShell script parse qua; JS syntax, UI DTW và speed-merge mock qua. Stable host và toàn bộ engine không đổi. Installer chỉ chạy ở fixture riêng trong phép test; cập nhật panel thật cần xác nhận đóng Premiere.


## Notification UX 2.20.65

`notification-ux.test.js` kiểm phân loại bằng model/renderer thật với DOM giả lập: nhật ký warn và CPU/cleanup không tự nâng cảnh báo; mặc định focus và lựa chọn đã lưu; đếm vùng đầu ra không lặp; thiếu marker vẫn có danh sách; marker xanh thông tin; lỗi thô chỉ ở chi tiết; đóng thông báo vẫn giữ khóa phục hồi. `Preview-Panel.js` kiểm hai chế độ ở 320/385/560 px với dữ liệu mô phỏng, không gọi Premiere. Nghiệm thu native còn phải kiểm panel hiện/ẩn, Windows/DND, Play và Save trên project sao lưu.


## Input UX 2.20.66

`caption-audio-ui.test.js` kiểm mặc định clip audio đang chọn, selection video, không selection, đổi selection, ưu tiên nguồn thủ công, disabled/ID không xác minh, guard topology và nhiều track. `srt-join.test.js` kiểm chọn từng file Project, tìm tên, thu gọn, không tự thêm khi mở/quét xong, thứ tự và snapshot job ở cả hai luồng. `srt-scan-ui.test.js` kiểm ưu tiên SRT Project ở hai luồng và giữ chọn ngoài/ASR-only. `Preview-Panel.js` kiểm bố cục/interaction bằng fixture riêng ở 320/385/560 px. Đây không phải nghiệm thu selection/export/import native trong Premiere.
