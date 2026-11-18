# Bộ nhớ hồi quy của project

## Issue #67 — Giữ đúng vị trí khi dời marker (18/11/2026)

- **Lỗi native ở 2.20.94.** Auto edit báo `Marker position/notes verification failed` sau khi dựng. Nhóm hình có 19 marker, trace ghi nhận 38 lần dời, 34 lần ghi end, 19 lần ghi name và 19 lần ghi comments qua hai lượt ghi và bù. Nhóm review có 21 marker, 42 lần dời. Khi khôi phục, host báo `Marker restoration: source snapshot differs`.
- **Nguyên nhân.** Khi dời sang phải, host ghi end trước. Premiere giữ độ dài khi đổi start nên end vừa ghi lại dịch theo. Mock cũ coi hai biên độc lập.
- **Quy tắc.** Ghi start trước, đọc lại rồi mới ghi end; mock marker phải giữ độ dài khi đổi start. Khi dời, chỉ ghi end nếu độ lệch vượt ngưỡng hiện hành. Khi khôi phục, so đúng từng biên với ảnh chụp gốc. Marker mới là điểm.
- **Phép đo.** Probe trên ProjectItem voice trong Premiere 26.2.2, ngày 18/11/2026. Các giá trị bên dưới tính bằng giây so với vị trí tạo marker. Trước và sau đều có 59 marker, đã đối chiếu sau dọn. JSON gốc ở `_local/probe-move/move-run.json`.

| Trạng thái đầu | Phép ghi theo thứ tự | [start, end] sau từng phép ghi |
| --- | --- | --- |
| Mới tạo | Tạo tại 0 | [0, 0] |
| [0, 1] | start = 0.5 | [0.5, 1.5] |
| [0, 1] | end = 0.5, start = 0.5 | [0, 0.5] → [0.5, 1.0] |
| [0, 1] | start = 0.5, end = 0.5 | [0.5, 1.5] → [0.5, 0.5] |
| [0, 1] | start = 2 | [2, 3] |
| [0, 1] | start = -0.5, end = -0.5 | [-0.5, 0.5] → [-0.5, -0.5] |
| [0, 1] | end = 0 | [0, 0] |
| [0, 0] | start = 0.5 | [0.5, 0.5] |
| [0, 0] | start = -0.5 | [-0.5, -0.5] |
| [0, 0] | end = 0.5 | [0, 0.5] |

- **Hồi quy.** Với mock đã sửa và host cũ, thu [1, 2] về điểm 1.5 tái hiện lỗi xác minh. `marker-moves.test.js` kiểm tra dời hai chiều, vượt end cũ, giữ khoảng, khôi phục đúng hai biên sau lỗi và chạy lại không ghi. `diagnostic-executor.test.js` đối chiếu 42 fixture qua bốn chế độ và kiểm tra khôi phục bằng nhật ký. Sau sửa, 28 ca dời marker đạt, toàn bộ hash timeline giữ nguyên. Hash marker của fixture số 3 và 12–23 (đếm từ 0) đổi do marker điểm có sẵn trong mock nay có end bằng start. Bộ chuẩn đạt 73 nhóm, bỏ qua sáu nhóm tích hợp Windows. Log ở `_local/marker-move-order/suite.log`. Chờ chạy lại Auto edit trên Premiere.

## Issue #63 — Cảnh báo trên clip hoặc trong panel (18/11/2026)

- **Quyết định.** Lượt Auto edit native 2.20.93 gắn được 22/22 marker review lên clip. Trước đây các lỗi mapping/ghi/đọc lại và chế độ mix hoặc nhiều track có thể tạo marker trên thước. Quy tắc mới: không ghi marker lên thước timeline; cảnh báo không gắn được clip thì báo trong panel.
- **Chọn clip.** Dùng danh sách track đã đóng băng khi xuất audio. Với mix hoặc nhiều track, xét A1, A2, … đến track đầu tiên có clip giao với vùng cảnh báo. Trên lát đã chọn vẫn gộp theo loại và lấy điểm giữa. Cảnh báo thiếu marker không làm hỏng caption đã tạo. Khi chạy lại, chỉ dọn marker cũ trên thước đúng dấu sở hữu và phạm vi.
- **Hồi quy.** Trước sửa, mock caption thiếu binding tạo một marker thước thay vì 0. Mock caption, review, reconciliation, thông báo và executor kiểm tra chọn track, báo từng cảnh báo, dọn marker cũ và khôi phục khi lỗi hoặc Dừng. 42 fixture qua bốn executor giữ nguyên hash timeline và marker. Standard suite đạt 73 nhóm, parse 133 file PowerShell, bỏ qua sáu nhóm tích hợp Windows. Log ở `_local/remove-ruler-fallback/suite.log`. Chờ nghiệm thu hành vi mới trên Premiere.

## Issue #62 — Gộp cảnh báo cùng loại trên từng lát clip (18/11/2026)

- **Quyết định.** Mỗi loại marker một marker cho mỗi đoạn trên một layer; khác loại đặt cạnh nhau. Trước đây host gom theo frame bắt đầu nên hai cue chồng nhau có thể tạo hai điểm, còn hai cảnh báo cùng frame bắt đầu có thể bị gom trước khi biết chúng thuộc lát clip nào.
- **Quy tắc.** Với từng cảnh báo SRT, chọn lát voice theo phần giao dài nhất. Trong mỗi lát, gộp các khoảng chồng hoặc chạm nhau trên lưới frame rồi lấy điểm giữa phần giao của đoạn gộp với lát. Giữ các lý do, bỏ ghi chú trùng và dùng màu lỗi nếu có lỗi. Khoảng cách một frame và ranh giới lát đều tách marker. Cảnh báo căn voice lấy giữa lát A2, cảnh báo tốc độ/gộp hình lấy giữa lát V1.
- **Thứ tự.** Cả trước cắt và sau dựng đều lập marker căn voice trước. Nhóm SRT đọc marker trên ProjectItem cùng các vị trí nhóm voice vừa dành trên nguồn đó. Khi vướng điểm đã dùng, tìm frame trống trong đoạn cue, ưu tiên phía sau khi cách đều.
- **Hồi quy.** Trước sửa, mock trên một nguồn tạo 6 marker thay vì 4; fixture 65 lát tạo 2 marker SRT thay vì 1. `marker-reconciliation.test.js` kiểm tra cả Auto edit và Tạo phụ đề. `diagnostic-executor.test.js` kiểm tra hai loại cách nhau một frame, ghi trước cắt, hậu kiểm và chạy lại không ghi, khôi phục khi lỗi/Dừng. Chờ nghiệm thu trên Premiere.

## Issue #59 — Marker điểm ở giữa đoạn cảnh báo (18/11/2026)

- **Quyết định.** Marker có độ dài che sóng âm và các lớp khi dựng. Theo quyết định ngày 18/11, marker của tool là điểm ở giữa đoạn cảnh báo (In = Out), thay quy tắc hiển thị bằng độ dài của #36.
- **Vị trí.** Trên clip, lấy giữa phần giao với đoạn clip thực tế rồi làm tròn theo frame timeline (nửa frame chọn phía sau) trước khi đổi sang giây nguồn. Trên thước, dùng toàn đoạn cảnh báo. Khi vướng marker, thử từng khoảng cách một frame, phía sau trước rồi phía trước, luôn ở trong đoạn. Khi hết chỗ, giữ luồng dự phòng/báo lỗi hiện có.
- **Ghi và khôi phục.** Dùng cùng bộ lập vị trí khi ghi trước lúc cắt và khi đối chiếu sau dựng. Đọc Out của marker mới và chỉ ghi khi sai quá nửa dung sai nhóm hoặc thiếu Out. Marker cũ được thu về điểm khi chạy lại. Nhật ký vẫn giữ chính xác hai mép gốc để trả lại khi lỗi hoặc Dừng.
- **Kiểm chứng.** Mock review và reconciliation kiểm tra va chạm, mép clip, đổi tốc độ và chạy lại. Mock executor kiểm tra thứ tự ghi của fixture 65 lát, khôi phục marker cũ, parity của các profile và số lần ghi Out. Standard suite đạt 73 nhóm, parse 133 file PowerShell, bỏ qua 6 nhóm tích hợp Windows. Log ở `_local/point-markers/suite.log`. Chờ chạy trên Premiere để xác nhận Out mặc định, hiển thị trên timeline và chi phí ghi thật.

## Issue #58 — Thay marker review cũ trên nguồn voice dùng chung (18/11/2026)

- **Nguyên nhân.** Hai lượt Auto edit dùng sequence khác nhau nhưng cùng ProjectItem voice. Host chỉ nhận tag của sequence hiện tại nên số marker trên nguồn tăng từ 15 lên 37 rồi 59. Lượt cuối tạo 22 marker và xóa 0.
- **Quy tắc.** Marker review trên ProjectItem thuộc tool bất kể sequence khi đúng loại Comment, đúng tên và có tag v2 hợp lệ của cùng workflow. Auto edit và Tạo phụ đề đều ghi review lên voice và quản lý hai bộ riêng. Lượt mới tái sử dụng marker phù hợp, ghi tag của sequence hiện tại và dọn marker dư, kể cả khi danh sách review rỗng. Marker trên thước vẫn theo sequence và vùng xử lý.
- **Khôi phục.** Với kế hoạch rỗng, lượt hậu kiểm có thể là lần đầu sửa marker review trên nguồn. Mock tiêm lỗi tạo caption sau khi dọn đã tái hiện mất marker cũ. Executor lấy snapshot của nhóm review ở lượt hậu kiểm nếu nguồn chưa có giao dịch ghi trước, rồi dùng cùng nhật ký để hoàn tác khi lỗi hoặc Dừng.
- **Hồi quy.** Trước sửa, mock hai sequence giữ hai bộ và executor bỏ qua GUID review cũ khi ghi trước. `marker-reconciliation.test.js` kiểm tra tái sử dụng, dọn khi chạy rỗng và giữ marker thủ công, tag sai, workflow khác, marker thước. `diagnostic-executor.test.js` kiểm tra dời, dọn và khôi phục cả tag cũ sau lỗi hoặc Dừng. Marker còn tồn tại giữ GUID, marker đã xóa được tạo lại với các trường gốc. Chờ nghiệm thu trên Premiere.

## Issue #55 — Ghi marker voice trước khi cắt, đối chiếu trên timeline cuối (18/11/2026)

- **Bằng chứng.** Sông Congo 2.20.92 mất 25,2 giây để commit 19 marker voice sau cắt (18 tạo, 23 xóa), thêm khoảng 5 giây cho 22 marker review. Probe trên cùng ProjectItem đo 14,7/45,1 ms mỗi lần tạo và 14,6/35,4 ms mỗi lần xóa với 1/101 clip A2. [Số đo native](reviews/MARKER_WRITE_COST_PROBE_2026-11-16.md).
- **Ánh xạ.** Sau khi đọc snapshot, trước razor đầu tiên, lấy đoạn lời ở frame voice gốc, in point và speed của chapter, rồi chiếu sang đoạn lời ở vị trí đích. Marker căn voice và review trong kế hoạch dùng lại quy tắc chọn vị trí, màu, duration, nhãn cue và tránh va chạm của lượt cuối. Mỗi call chỉ ghi một owner. Ánh xạ thiếu bằng chứng được để lại cho hậu kiểm. Cảnh báo V1 dùng speed V1/A1 đọc lại sau hội tụ. Fallback ruler chỉ chạy sau dựng.
- **Đối chiếu.** Post-pass tính lại theo TrackItem thật. Nếu ánh xạ voice đổi, trả lại marker ghi trước rồi lập yêu cầu theo timeline. Khi có thêm issue native, trả các marker review ghi trước về vị trí cũ trước khi phân bổ lại. Dời marker review trên ProjectItem dùng kiểm chứng của #53. Giữ marker dư tới lần đối chiếu cuối để Premiere còn GUID cũ cho yêu cầu mới.
- **Lỗi và Dừng.** Mỗi nguồn có snapshot đầy đủ trước khi ghi. Nhật ký theo dõi các marker thực sự sửa, tạo và xóa. Khôi phục ngược thứ tự transaction, đọc lại GUID/ref và các trường trước khi ghi, bảo vệ marker thủ công, dời lại marker còn tồn tại và tạo lại marker owned đã xóa. Marker tạo lại nhận GUID do Premiere cấp. Sai khác hoặc lệnh khôi phục lỗi được đưa vào báo cáo. Panel giữ token recovery trước call ghi đầu tiên và chỉ chấp nhận kết quả sau khi kiểm Dừng. Mở lại panel có thể dùng phiên host còn sống để khôi phục. Nếu mất cả phiên host, panel giữ cảnh báo để đối chiếu marker nguồn với project đã lưu.
- **Hồi quy.** Test đỏ trên host `9dc6534` vì marker voice đầu tiên được tạo sau razor. Bộ mock đối chiếu trường marker, GUID cũ và lệnh sửa timeline với host gốc trên direct/baseline/fast/no-delay. Tiêm lỗi razor, speed, move, caption, hậu kiểm, Dừng giữa hai chapter và Dừng ở call cuối. Kiểm tra cả sửa tay khi pause, lỗi khôi phục và thử lại. Log ở `_local/markers-before-cuts/`. Nghiệm thu di chuyển/khôi phục marker, độ chính xác source time và thời gian thực trên Premiere vẫn pending.

Kết quả ngoại tuyến: 42 fixture × 4 executor khớp host gốc, kể cả khi source time đổi sau razor và phát sinh issue native. Fixture 65 lát có 0 lần ghi lại marker voice/review sau dựng. Ca chạy lại đã khớp toàn bộ marker từ đầu vẫn khôi phục đúng snapshot khi issue native làm đổi review rồi hậu kiểm thất bại (đỏ trước sửa trong `rerun-red.log`). Standard suite với `-NoWindowsIntegration` đạt 73 nhóm, parse 133 file PowerShell. Sáu nhóm bỏ qua gồm InstallerLifecycle, InstallRollback, PanelRegistry, NotificationShortcut, NativeNotifications và IncidentNotifications.

## Issue #53 — Đổi vị trí marker clip thuộc phạm vi thay vì xóa/tạo (17/11/2026)

- **Nguyên nhân/bằng chứng.** Matching chỉ giữ marker gần vị trí mong muốn;
  marker owned ở vị trí khác luôn tạo mới rồi xóa cũ. Lượt Sông Congo 2.20.92:
  owner A2 before/after 24/19, creates 18/deletes 23, name/comments/end/color
  writes 18/19/19/18, colorReads 103, commitMs 25192. Probe 17/11 Premiere 26.2.2
  có 1 và 101 clip A2, ProjectItem 37 marker, cleanup 37 → 37 cả hai lượt.
  Lượt 101 clip: ms/lệnh create 45,1; name 47,3; comments 34,7; end 44,2;
  setColor 42,6; getColor 23,2; delete 35,4. Start số giây đọc lại 11 → 11,5;
  Time ném `Illegal Parameter type`. Chưa probe chuyển start vượt end cũ.
- **Invariant/sửa.** `allowMove` mặc định false, chỉ bật tại
  `prepareClipMarkerGroup` (ProjectItem V1/A2). Ba caller còn lại giữ false:
  `prepare` trong `_applyReviewMarkers` (ProjectItem review riêng),
  `sequenceGroup` trong `_applyReviewMarkers` (ruler),
  `commitOwnedMarkerFallbacks` (ruler). Caption-only không đổi. Ưu tiên match
  tolerance trước; ghép unmatched với owned obsolete theo vị trí và thứ tự
  ban đầu khi hòa. Không ghép marker thiếu snapshot end/màu. Snapshot đầy đủ
  trước mọi ghi; start dùng số giây, sang phải ghi end trước, sang trái ghi
  start trước để giữ start <= end. Chỉ ghi field khác; end mặc định là điểm
  tại start khi spec không có end, giống tạo mới. `moves/moveMs` tính lần thử
  ghi start, cả compensation; field timers #50 giữ nguyên. Không thay scope,
  fingerprint, available/reserved, foreign/manual, một commit mỗi owner.
  Mọi replacement phải qua target.verify/tolerance và move phải không va chạm
  collection trước xóa obsolete còn lại. Lỗi đọc bounds thực tế (kể cả call
  mutate rồi throw), bù start/end đúng thứ tự, khôi phục field, xóa created,
  tạo lại deleted và đối chiếu toàn bộ collection như trước.
- **Regression trước sửa.** `_local/reuse-clip-markers/red.log`: mock đỏ
  đúng thiếu moves, N vị trí khác dùng N creates + N deletes. Test so toàn
  state với đường allowMove=false, trừ GUID. Bao phủ phần dư hai phía, foreign
  gần, hòa vị trí, matching trước pairing, reserved/conflict, move sớm/muộn
  qua end/start cũ, point end mặc định, chỉ ghi field khác và rerun không ghi.
  Lỗi start/end trước hoặc sau mutate, name/comments sau mutate, verify,
  lệch read-back/va chạm, delete sau mutate đều khôi phục state. Giữ các ca
  reconciliation/sequence fallback cũ. Executor thêm hai owner có move để so
  measured/unmeasured native reads và direct/baseline/fast/no-delay mutations.
- **Kiểm tra.** 23 ca move/compensation và reconciliation cũ đạt. Executor
  sinh lại bằng generator; parity measured/unmeasured và các profile đạt,
  không sửa vùng sort gần executePlan. Generator `--check`, syntax
  main/security, Acorn ES3 host/executor/caption-input và `git diff --check`
  đạt. Suite đầu phát hiện tên biến nội bộ `plan` trùng mẫu quét field input;
  đổi thành `markerPlan`, không đổi projection/runtime để chiều test.
  Standard suite trên mã cuối đạt **73 nhóm/133 script PowerShell parse**,
  exit 0; log `_local/reuse-clip-markers/suite.log`, TEMP/TMP ở `temp` cùng
  chỗ. Log lỗi đầu giữ tại `suite-first.log`. Sáu Windows integration skipped:
  InstallerLifecycle, InstallRollback, PanelRegistry, NotificationShortcut,
  NativeNotifications, IncidentNotifications.
- **Nghiệm thu.** Native acceptance pending, kể cả thứ tự bounds khi vượt end
  cũ và thời gian sau sửa. Không chạy Premiere/commit/push/build release/cài
  đặt; không sửa runtime/dist/AppData. Tự rà diff, không review độc lập.

## Issue #51 — Đọc key bắt đầu clip một lần khi sort (17/11/2026)

- **Bằng chứng/nguyên nhân.** Trace native 2.20.92 do user cung cấp: chuẩn bị
  sau Cắt V1–A1 có 260 clipItems, 2 sort, 17.028 comparator, 34.316 lượt đọc
  `start.seconds`, propertyReadMs 2.522, sortMs 2.641, workMs 2.757. Chuẩn bị
  hậu kiểm có 1 sort, 8.514 comparator, 17.028 lượt đọc, sortMs 1.390.
  Comparator cũ đọc hai property Premiere mỗi lần so sánh.
- **Invariant/sửa.** Sort trên key đọc một lần mỗi item; cùng thứ tự; không
  đổi native mutation. Helper ES3 cục bộ `sortItemsByStart` tạo `{item,key}`,
  sort bằng đúng `a.key - b.key`, ghi lại cùng mảng. Đổi đủ ba chỗ:
  `videoPieces`, `audioPieces` sau cắt và `coverageItems` khi hậu kiểm.
  Không thêm tie-break hoặc chuẩn hóa NaN/Infinity; giữ collection/filter,
  các check, snapshot, rebind, hậu kiểm và `_markerTools`. Generator tự đưa
  helper vào executor; counter vẫn đo key reads, sort và comparator.
- **Regression trước sửa.** Mock production sort 260 item đỏ: 3.502 lượt đọc
  cho 1.751 comparator; log `_local/cache-sort-keys/red.log`. Test host và
  executor kiểm identity mảng, item identity/thứ tự và chuỗi cặp comparator
  so với phép sort cũ trong cùng runtime: rỗng, một item, distinct, ties,
  sorted/reverse, nhiều ties, NaN, ±Infinity, ±0 và giá trị qua `Number()`.
  Sau sửa đúng một lượt đọc/item, comparator không đọc Premiere.
- **Đối chiếu hành vi.** `diagnostic-executor.test.js` so 16 tổ hợp fixture/
  profile direct/baseline/fast/no-delay với comparator cũ; mutations cùng
  tham số/thứ tự, actions và report giữ nguyên, native reads giảm. Đã chạy
  thêm với source nguyên trạng tại bc7f81a lưu trước sửa; log
  `_local/cache-sort-keys/targeted.log`. Digest có/không counter vẫn khớp
  trong cùng runtime, không khóa hash. No-delay mutations vẫn bằng baseline.
- **Khảo sát riêng, không sửa.** Stage sau Cập nhật marker nguồn còn gọi
  `commitOwnedMarkerFallbacks`, duyệt kiểm liên kết/speed V1/A1 và gọi
  `_applyReviewMarkers`. Đây là các native calls/marker transactions không
  được bao trọn bởi counter property của helper được generator chép.
  Chi tiết trong `PERFORMANCE_REVIEW.md`; chưa có số đo tách từng call.
- **Kết quả.** Targeted mocks, Acorn ES3 host/executor, syntax main/security,
  generator `--check` và `git diff --check` đạt. Standard suite đạt **72 nhóm/
  132 script PowerShell parse**, exit 0; log `_local/cache-sort-keys/suite.log`,
  TEMP/TMP trong thư mục `temp` cùng chỗ. Sáu Windows integration skipped:
  InstallerLifecycle, InstallRollback, PanelRegistry, NotificationShortcut,
  NativeNotifications, IncidentNotifications. Tự rà diff, không có review độc
  lập. **Native pending**; không chạy Premiere, commit/push/build/install;
  không sửa runtime/dist/AppData.

## Issue #49 — Tách chi phí từng thao tác marker (16/11/2026)

- **Bằng chứng/thiếu số đo.** Lượt 2.20.92 ngày 16/11: một owner A2 voice,
  19 marker mong muốn, `commitMs=25192` trong một host call không phản hồi;
  before/after 24/19, readPasses/readMs 3/74, creates/nameWrites 18/18,
  commentsWrites/endWrites 19/19, colorWrites/colorReads 18/103, deletes 23,
  verificationMs 191. 2.20.90 trước chuyển marker review sang voice clip có
  stage 0,09 s; chưa đủ để quy chi phí cho operation nào.
- **Đo/invariant.** Thêm createMs/nameWriteMs/commentsWriteMs/endWriteMs/
  colorWriteMs/colorReadMs/deleteMs vào timings, gồm cả thao tác ném lỗi và
  compensation, không thêm native read/write. Giữ scope, tolerance, đọc lại
  mọi replacement trước xóa marker cũ, xác minh xóa và một commit mỗi owner.
  readMs/verificationMs bao gồm một phần colorReadMs nên không cộng tất cả
  timer thành tổng độc lập. Host giữ ES3, executor sinh lại, không sửa generator
  hay batch conditions đang được xử lý ở PR #48.
- **Rà ghi dư.** Không bỏ thao tác: marker cũ đã được so giá trị trước ghi;
  màu đọc ngay sau set có colorFailures riêng, snapshot màu của toàn collection
  phục vụ fingerprint/compensation. Chưa chứng minh hai lượt đọc đó thay thế
  nhau được khi native/proxy lỗi. Ghi khôi phục giữ nguyên vì native có thể
  mutate rồi throw, không chỉ thay field đã dự định. Không tuyên bố giảm thời
  gian native khi chưa có số đo từng loại.
- **Regression trước sửa.** Marker mock đỏ đúng thiếu createMs; log
  `_local/marker-write-cost/timing-red.log`. Clock xác định tính từng native
  operation và so counters/tổng ms, gồm update/create/delete mutate rồi throw,
  xóa giả thành công, lỗi màu và compensation. Giữ các ca reconciliation cũ.
  Probe/runner mock đỏ vì chưa hỗ trợ cost-list; log `probe-red.log` cùng chỗ.
- **Probe riêng.** `Probe-MarkerWriteCost.jsx` đo N lần bảy thao tác và một
  collection read, thử start kiểu Time và seconds rồi đọc lại, chỉ dọn đúng
  tag trên ProjectItem media trong project bỏ đi với documentId/nodeId/scope
  rõ ràng. Snapshot đầy đủ và dọn trong finally; marker không gắn được tag
  được báo để kiểm tra thủ công, không xóa. Không truy cập sequence/Save/Undo.
  Test kiểm ES3, arithmetic, N/giới hạn duyệt, tag/scope, lỗi/false-success,
  cleanup và pre-state. Mẫu native tại
  [MARKER_WRITE_COST_PROBE_2026-11-16](reviews/MARKER_WRITE_COST_PROBE_2026-11-16.md).
- **Kết quả.** Targeted marker/probe và executor parity measured/unmeasured
  đạt, generator `--check`, syntax main/security, ES3 host/executor/probe và
  `git diff --check` đạt. Standard suite đạt **73 nhóm/133 script PowerShell
  parse**, exit 0; log `_local/marker-write-cost/suite.log`, TEMP/TMP ở thư mục
  `temp` cùng chỗ. Sáu Windows integration skipped: InstallerLifecycle,
  InstallRollback, PanelRegistry, NotificationShortcut, NativeNotifications,
  IncidentNotifications. Đối chiếu thêm với host gốc `552bb75`: 10 ca thành
  công/lỗi cho cùng thứ tự ghi native, lượt đọc collection, state mọi field và
  kết quả/compensation; log `host-parity.log` cùng chỗ. Ví dụ clock xác định
  trong `timing-example.json`: create/name/comments/end/color-write/color-read/
  delete = 2/3/10/14/22/156/17 ms, tổng 224 = commitMs; chỉ là mock.
  Native acceptance và số đo mới pending; không chạy Premiere/build release/
  install/commit/push. Chỉ tự rà mã/diff, chưa có review độc lập.

## Issue #47 — No-delay chạy hết loop stage, bỏ batch caps (16/11/2026)

- **Quyết định/nguyên nhân.** User chốt ngày16/11/2026 đảo batch caps của
  2.20.87 cho no-delay mặc định Auto edit. Lần treo2.20.86 là native call
  không trả về; chia batch không thể giải cứu call đó. Số đo native2.20.92
  user cung cấp:76 calls/85,4s timeline, overhead cộng dồn khoảng27s
  (checks10,4s, snapshots6,4s, Premiere ngoài script10,5s, số làm tròn).
- **Invariant.** Generator bỏ count/time/pair yield chỉ ở no-delay, mỗi loop
  stage hoàn tất trong một host call. Baseline20 iteration/200ms, fast100
  iteration/600ms và cap4 cặp speed của cả hai giữ nguyên. Marker-owner giữ
  `batchCount >= 1`: một owner group mỗi call, transaction riêng. Giữ stage
  boundaries, signature/snapshot check giữa stage, rebind, `postMode`
  snapshots, hậu kiểm cuối, thứ tự/tham số mọi native mutation và recovery.
  Trace panel ghi no-delay true/null cho `batchLimitsDisabled`/
  `nativeSpeedPairsPerBatch`; baseline/fast false/4.
- **Đánh đổi.** Dừng/Tạm dừng chỉ có hiệu lực ở ranh giới stage (riêng marker
  vẫn giữa các owner); timeline không vẽ lại trong stage dài. Không ngắt
  native call đang chạy, không tự Save/Undo hay retry.
- **Regression trước sửa.** Mock đỏ tại `No-delay must complete every loop
  stage in one host call, except marker owners`; trace panel đỏ false/true.
  Log `_local/remove-batch-limits/red-executor.log`, `red-panel.log`.
  So native set/call rows làm thay đổi timeline, đủ tham số/thứ tự và actions
  theo clip giữa no-delay/baseline trên fixture merge, gap, speed voice và
  6/65/130 đoạn; giữ report/checkpoints và digest measured/unmeasured trong
  cùng Node runtime, không khóa sha256. Clock cố định kiểm iteration cap,
  clock nhảy kiểm time budget; speed kiểm4 cặp baseline/fast, hết stage
  no-delay. Stop yêu cầu trong speed call chờ hết stage, abort không thêm
  mutation; marker lifecycle vẫn hủy giữa owner. Pause/cancel panel giữ kiểm
  chờ call hiện tại và chặn stage kế tiếp.
- **Kết quả.** Executor, trace panel, workflow pause/cancel, syntax main/security,
  generator `--check`, Acorn ES3 host/executor/caption-input và `git diff --check`
  đạt. So thêm digest toàn bộ native reads/writes/calls baseline/fast với
  executor tại HEAD trên fixture merge/gap: không đổi. Standard suite đạt
  **72 nhóm/132 script PowerShell parse**, exit0; log
  `_local/remove-batch-limits/suite.log`, TEMP/TMP trong `temp` cùng chỗ.
  Sáu Windows integration skipped: InstallerLifecycle, InstallRollback,
  PanelRegistry, NotificationShortcut, NativeNotifications, IncidentNotifications.
  Tự rà diff, không có review độc lập. **Native pending**; không chạy Premiere,
  commit/push/build/install, không sửa runtime/dist/AppData.

## Issue #44 — Đo chi tiết staged timeline, không đổi hành vi (16/11/2026)

- **Thiếu số đo.** `workMs` chưa tách quét/property/sort clip và transaction
  marker; không thể quy thời gian dài cho một native operation cụ thể.
- **Invariant.** Chỉ đo điểm truy cập hiện có; giữ short-circuit, comparator,
  native calls/arguments/order, guard/hậu kiểm, batch limits, bốn speed pairs,
  transaction và compensation. `_markerTools.commit` trả thêm `timings`;
  executor sinh thêm `detail` từng host call, panel chuyển nguyên vào finish.
  Không sửa logger panel hoặc phép ghi wall/host.
- **Test.** Marker mock thiếu counters đỏ trước sửa. Thêm đối chiếu counter
  create/update/delete và timer dùng clock xác định; giữ các ca rollback cũ.
  Staged mock kiểm tổng clip/property/comparator/owner và marker commit;
  tám fixture direct/baseline/fast/no-delay với merge marker hoặc gap voice
  so digest chuỗi native reads/writes/calls/arguments giữa executor có counter
  và bản sinh `generate(..., {measure:false})` trong cùng runtime. Panel mock
  kiểm detail nguyên vẹn và lỗi trace không dừng tác vụ.
- **CI Node 22 khác Node 26.** Bản đầu khóa sha256 cứng chụp trên Node 26; CI
  Node 22 ít hơn 36 dòng ở cả bốn profile có gap, kể cả direct không qua
  generator. Proxy mock ghi cả lượt đọc nội bộ của engine (vd. lúc `sort`),
  nên hash cứng phụ thuộc phiên bản Node, không phải hành vi tool. Sửa: so hai
  bản build cùng lần chạy; thử chèn thêm `app.project` vào bản đo thì test đỏ
  đúng `deepStrictEqual`.
- **Kết quả.** Targeted mock, generator `--check`, syntax main/security,
  Acorn ES3 host/executor/caption-input và `git diff --check` đạt. Standard
  suite trên bản mã cuối đạt **72 nhóm/132 script PowerShell parse**, exit 0;
  log `_local/timeline-metrics/suite.log`, TEMP/TMP trong thư mục `temp` cùng
  chỗ. Sáu Windows integration skipped: InstallerLifecycle, InstallRollback,
  PanelRegistry, NotificationShortcut, NativeNotifications, IncidentNotifications.
  Dòng finish mock đầy đủ: `_local/timeline-metrics/mock-finish.jsonl`.
  Tự rà diff, không có review độc lập. Native measurement pending; không chạy
  Premiere/build bản phát hành/install/commit/push, không sửa runtime/dist/AppData.

## Sentence planner — Checker trộn decimal/double làm lệch frame (16/11/2026)

- **Nguyên nhân.** `ConvertFrom-Json` trên PowerShell 5.1 trả số lẻ dạng
  `[decimal]`. Planner tạo acoustic groups với giờ `[double]`, nhưng
  `Assert-PvsAcousticPartitionPlan` cộng mép reference JSON chưa ép kiểu vào
  midpoint. End 174.533/Start 174.767 ở 30 fps cho planner
  5239.4999999999991 → 5239; checker decimal cho 5239.500 → 5240 và báo nhầm
  `ACOUSTIC_PARTITION_SOURCE_BOUNDARY_CHANGED`.
- **Invariant/sửa.** Checker tính frame bằng cùng phép toán `[double]` và
  đúng thứ tự như planner; không trộn decimal từ `ConvertFrom-Json` vào phép
  tính frame. Ép kiểu mép reference, main clip, ngưỡng gap và mép voice trước
  phép toán; midpoint luôn cộng mép trái rồi mép phải, chia 2.0 rồi nhân fps.
  `Assert-PvsManualReviewPlan` cũng ép bốn mép source/voice sang `[double]`
  trước nhân fps. Giữ nguyên mã/đầu ra planner, ngưỡng và toàn bộ check/proof.
- **Test trước sửa.** `Test-AutoEditAcousticPartitions.ps1`, ca
  `JSON_DECIMAL_HALF_FRAME`: reference qua `Copy-Json`, xác nhận kiểu decimal,
  tạo groups bằng helper production và dùng đúng phép toán planner; frame
  đầu `[5052,5239]`, mép chung 5239. Đỏ đúng
  `ACOUSTIC_PARTITION_SOURCE_BOUNDARY_CHANGED`, log
  `_local/partition-decimal/red-tests.log`. Audit thêm bốn ca
  `JSON_DECIMAL_MANUAL_SOURCE` chạy shipping planner cho sourceEnd 2.05,
  sourceStart 4.15, voice end 32.05 và voice start 4.15: cả bốn đỏ
  `MANUAL_REVIEW_BLOCK_WAS_CUT_OR_LOST` trước sửa manual checker, log
  `_local/partition-decimal/audit-red-tests.log`.
- **Test sau sửa.** Nhóm acoustic đạt, gồm hai mép midpoint, từ chối frame
  bị sửa và cả bốn ca manual với frame planner 61/125/961/125 giữ nguyên;
  log `_local/partition-decimal/green-tests.log`. Standard suite đạt
  **72 nhóm/132 script PowerShell parse**, exit code 0, log
  `_local/partition-decimal/suite.log`; TEMP/TMP đặt dưới
  `_local/partition-decimal/temp`. Sáu nhóm Windows integration bỏ qua:
  InstallerLifecycle, InstallRollback, PanelRegistry, NotificationShortcut,
  NativeNotifications, IncidentNotifications. `git diff --check` đạt.
- **Audit giữ nguyên.** `Add-PvsCuePicturePlan` còn phép trừ gap và midpoint
  source/word-time chưa ép kiểu (264–267); đây là bên tạo picture plan, chưa
  có regression chứng minh checker lệch nên không đổi đầu ra. Trong
  `Assert-PvsCuePicturePlan`, giờ/speed từ JSON còn tham gia tính sai số
  (phép nhân fps và tính lại speed), nhưng frame/duration là số nguyên và
  dung sai hiện có chưa tái hiện lỗi. `Test-PvsAcousticReferenceCut` còn cộng voice start với word
  time JSON và kiểm margin; checker whole-cue đã ép hai mép word sang double.
  `Split-PvsManualReviewCaptionCue` và guard display-cell trong
  `New-PvsAutoEditManualReview` còn nhân giờ cell chưa ép kiểu với fps; đó
  là đường tạo caption, chưa có regression so với checker nên giữ nguyên.
- **Nghiệm thu.** Chỉ kiểm ngoại tuyến với dữ liệu tổng hợp;
  **native acceptance pending**. Không chạy Premiere, build, cài, commit
  hoặc push; không sửa runtime/dist/AppData. Tự rà diff và các path liên
  quan, không có lượt review độc lập.

## Nghiệm thu native 2.20.91 (15/11/2026)

User cài 2.20.91 (gói SHA-256 `2C9F66FB…71CEDE`) và chạy lại Dựng theo voice
trên project thật đã báo 21 lỗi, Premiere 26.2.2: **chưa phát hiện lỗi**. Thư mục
job giữ lại (#33) cho thấy 83 caption, 6 marker review đều trên clip voice (0 về
thước timeline, 0 lỗi), 20 marker tốc độ V1, 0 lỗi marker clip; khớp số replay.
Đây là bằng chứng native cho #23, #25, #27, #29, #31, #33, #37 trên **một** project;
các entry bên dưới ghi "Native Premiere pending" được hiểu là đã có lượt chạy này.
Chưa đo: nest V1, speed khác 110%, reverse, time remap, caption-only native.
User nâng 2.20.91 lên stable/Latest cùng ngày.

## Issue #36 — Marker review đi theo clip voice, đúng giờ nguồn khi đổi speed (15/11/2026)

- **PR #37, sửa review (15/11/2026).** Test failing-first xác nhận: V1/A2 mất
  cảnh báo khi mapping không đọc được; read-back nguồn lỗi không có fallback;
  caption-only mix/nhiều track có thể gắn vào nhạc/SFX; caption padding chọn gap
  hoặc đuôi clip trước; collection ruler thiếu API chặn cả clip/empty run;
  cleanup đoán speed 100%; nhánh v1 review trên ProjectItem không có provenance
  lịch sử; normalization speed bị lặp. Log đỏ: `_local/pr37-review/red-*.log`.
  Adapter **2 passed/10 failed**, cleanup **1/3**, caption binding **0/4**,
  executor fallback/caveat **0/13**; notification fail `fallback count must be logged`.
  Mục 4 chính xác với collection có tồn tại nhưng thiếu API; `seq.markers` không
  tồn tại vốn đã được guard, song chỉ báo một lỗi chung khi nhiều fallback thiếu.
- **Invariant sau review.** Chỉ clip được chọn rõ (`clips`) hoặc đúng một track
  (`tracks`) của caption-only mới là nguồn voice đủ rõ để ghi ProjectItem dùng
  chung; mix/nhiều track dùng ruler và đếm fallback. Chọn overlap timeline lớn
  nhất, hòa hoặc nhiều clip đồng thời phủ vùng issue thì fallback, clamp cả hai
  mép trong clip thắng, không bắc qua gap. Commit clip trước khi chuẩn bị ruler;
  thiếu API ruler không cản clip/empty run, báo riêng từng issue cần fallback.
  Chỉ v2 review được dọn trên ProjectItem; v1 review chỉ dọn trên ruler.
  `_speedFactor` dùng chung cho đọc speed và mapping (<=10 ratio, >10 percent,
  invalid/unreadable là null). Cleanup dùng chính mapping placement, không góp
  range cho item chưa ánh xạ được; giữ snapshot không nhận ownership nếu không
  có range. Adapter nest V1/A1 giữ nguyên, A2 không có ngoại lệ nest/remap.
- **Fallback V1/A2.** Mapping/placement lỗi hoặc transaction ghi/read-back nguồn
  lỗi đã compensate: đặt marker ruler trong đúng timeline segment, giữ tên/màu,
  duration, tag riêng `[PremiereVoiceSync:owned-marker:sequence:v1:<sequenceId>]`.
  Rerun reconcile/dọn tag trong vùng dựng; giữ manual/unknown/sequence khác.
  Đếm `ownedMarkerSequenceFallbackCount`, cộng vào tổng/sequence (không vào clip),
  lưu `ownedMarkerSequenceFallbacks` để log count, vị trí và lý do. Restoration
  chưa đủ hoặc conflict vẫn báo lỗi ngay cả khi ruler fallback thành công.
- **V1 nest: Native Premiere pending.** Probe #34 chỉ WAV 110%, chưa chứng minh
  khả năng hiển thị marker trên nest. Không đổi adapter nest; đọc lại sai chuyển
  sang ruler như fallback trên. Mock/ES3/parity không phải nghiệm thu native.
- **Kiểm chứng review trước suite dài.** Tám file JS yêu cầu đạt **8/8**:
  review-markers, marker-reconciliation, marker-ownership, diagnostic-executor,
  caption-only-host, host-executor-input, notification-ux, probe-voice-clip-markers.
  Aggregate mới **37/37** (adapter 12, cleanup 4, binding 4, executor/caveat 17),
  thêm lifecycle fallback collision/duration/rerun/empty cleanup, log count/reason;
  giữ **17/17** voice review và **24/24** speed-range cases cũ. Executor sinh bằng
  generator, parity và syntax main/security đạt. Entry cập nhật **trước standard
  suite**. Codex sửa và tự rà path/transaction, không có lượt
  review độc lập. Không chạy Premiere/install/release, không commit/push/đổi branch
  và không đụng AppData. Log targeted: `_local/pr37-review/green-*.log`.
- **Kết quả suite sửa review.** Standard suite đạt **72 nhóm/132 PS parse** ngay
  lần chạy này, TEMP/TMP dưới `_local/pr37-review/temp`; log
  `_local/pr37-review/standard-suite.log`. Sáu Windows integration **skipped**:
  InstallerLifecycle, InstallRollback, PanelRegistry, NotificationShortcut,
  NativeNotifications, IncidentNotifications. Syntax main/security, generator
  `--check`, Acorn ES3 host/executor/caption-input và `git diff --check` đạt.
  Đây là automated/mock acceptance; native workflow và visibility nest V1 vẫn
  pending. Không có code change sau suite, chỉ chốt tài liệu kết quả.

- **Yêu cầu/nguyên nhân.** Review trước đây ở thước sequence nên không đi theo
  voice. Marker clip V1 tốc độ/A2 căn voice lấy phân số của in/out như giờ nguồn
  thật, sai khi speed khác 100%. Dùng kết quả native #34 trên Premiere 26.2.2:
  chỉ ProjectItem có API marker; in/out TrackItem đã chia speed; marker dùng giờ
  nguồn thật. Probe chỉ xác minh đến frame ở 110%, không suy ra nghiệm thu speed khác.
- **Invariant.** `src(t) = (t - start + inPoint) * speed`, chiếu ngược
  `start + marker/speed - inPoint`; getSpeed <=10 là ratio, >10 là phần trăm.
  Ghi cả start/end, đọc lại duration và hai mép chiếu timeline trong issue/clip.
  V1 phủ đoạn retime thật; A2 căn voice dùng cùng công thức. Va marker thủ công
  thì dịch đầu marker đến frame trống trong đoạn, giữ mép cuối và marker thủ công.
- **Review và fallback.** Auto edit dùng speechPieces A2 cuối; caption-only
  truyền binding track/clip đã đóng băng của nguồn nhận diện, không đọc selection
  hiện tại. Issue qua nhiều clip chọn overlap lớn nhất, clamp trong clip, không phủ
  qua gap. Gap, reverse, speed lỗi, time remap (kể cả tĩnh), nest, thiếu
  ProjectItem API, nguồn chồng nhau hoặc ghi/đọc kiểm chứng lỗi dùng marker sequence
  như trước. Count riêng `reviewMarkerClipCount` và
  `reviewMarkerSequenceFallbackCount`; tổng giữ `reviewMarkerCount`. Không có
  binding (kết quả cũ, native failure/recovery) vẫn dùng sequence. Nếu fallback
  cũng lỗi thì báo lỗi marker như cũ; không bỏ issue im lặng.
- **Ownership/cleanup.** Giữ tên, màu và ghi chú ngắn #28. Tag mới
  `[PremiereVoiceSync:review-marker:v2:<workflow>:<sequenceId>]` (ID encodeURIComponent)
  dùng cho clip lẫn fallback. Trên các ProjectItem voice đang xử lý, dọn v2 cùng
  workflow/sequence kể cả vị trí nguồn cũ đã ngoài clip; không dọn workflow/sequence
  khác. Sequence chỉ dọn trong ranges của lượt chạy. Nhận v1 cùng workflow trong
  ranges sequence hiện tại; v1 review không từng có trên nguồn nên không nhận/xóa
  trên ProjectItem. V2 tách provenance theo sequence. Marker vẫn hiện ở mọi sequence dùng cùng file voice.
  Giữ manual/unknown/non-Comment. Giữ snapshot/verify/compensate/commit theo nguồn,
  thêm snapshot/khôi phục duration; lỗi phục hồi vẫn báo riêng. Không đổi journal,
  failure recovery, Save/Undo, edit/caption timing hay quyền cắt/DTW.
- **Test trước sửa.** `VOICE_CLIP_REVIEW_CASES:passed=0;failed=13`, gồm speed
  1/1.1/110, mapping mẫu probe 15.079 → 16.3667, gap/reverse/unreadable/remap/nest,
  API/position/end read-back, clamp và scoped rerun; lỗi count `undefined == 1`.
  Ca V1 145% fail `No free source position for clip marker on 'Nest'.` Log gốc:
  `_local/voice-clip-markers/red-review.log`, `red-speed.log` (ignored).
- **Trước suite dài.** Chín file JS marker/host/notification/probe đạt 9/9;
  17 ca review mới, một ca V1 145% chạy mặc định, bốn tổ hợp caption-only
  tracks/clips × full/compact; thêm duration compensation, unsupported rerun,
  same-media nhiều clip và mixed sources. Mock executor sửa in/out speed-divided
  theo probe, vẫn khóa parity stable/baseline/fast/no-delay và 24 ca speed #30.
  Executor sinh từ host bằng generator, không sửa tay. Entry ghi **trước khi chạy
  standard suite**. Lần suite đầu dừng tại `Test-HostInvariants` vì bốn assertion
  tĩnh vẫn khóa midpoint/phân số nguồn cũ; đã đổi sang công thức probe, duration
  và read-back hai mép. Suite chạy lại đạt **72 nhóm/132 PS parse**. Tự rà phát
  hiện cần chặn cả remap tĩnh trên voice: test mới fail `fallback static-remap:
  0 == 1` trước chốt, sau sửa 17/17 ca review đạt. Adapter V1 giữ hỗ trợ nguồn
  nest/static component vốn có; review voice và A2 căn voice không dùng ngoại lệ
  này. Suite cuối sau chốt remap đạt **72 nhóm/132 PS parse**; chín file JS
  marker đạt 9/9. Sáu nhóm Windows integration bỏ qua: InstallerLifecycle,
  InstallRollback, PanelRegistry, NotificationShortcut, NativeNotifications,
  IncidentNotifications. Syntax main/security, executor parity, Acorn ES3 cho
  host/executor/caption-input và `git diff --check` đều đạt. Log cuối ở
  `_local/voice-clip-markers/standard-suite-final.log` và `marker-tests-final.log`.
- **Nghiệm thu.** Codex viết code và tự rà các path chung/fallback; Claude đọc
  diff và chạy lại standard suite (72 nhóm) cùng 9 test JS marker. Native riêng
  phần độ dài marker (15/11, probe): gán `marker.end` bằng số giây được Premiere
  26.2.2 nhận, đọc lại đúng, user thấy dải marker đúng vị trí trên clip A2 (lệch
  hiển thị 1 frame do làm tròn). Toàn workflow mới (review/speed/voice marker)
  vẫn **Native Premiere pending**.

## Issue #34 — Phép thử native: marker trên clip voice (15/11/2026)

User muốn marker review gắn vào clip voice A2 để đi theo cue khi dịch chuyển.
Phép thử khả thi chạy trên Premiere 26.2.2 (CEP 12) với sequence bản sao.

- **Kết quả.** `ProjectItem.getMarkers().createMarker()` tạo và đọc lại đúng giờ
  nguồn; marker hiện trên clip A2 và đi theo clip khi user kéo/trim (khớp đến
  frame ở hai lượt đo); `deleteMarker` xóa đúng marker có tag. TrackItem không có
  API marker. Chi tiết:
  [VOICE_CLIP_MARKER_PROBE_2026-11-15](reviews/VOICE_CLIP_MARKER_PROBE_2026-11-15.md).
- **Nguyên nhân lượt đầu tưởng thất bại.** `TrackItem.inPoint/outPoint` của clip
  đổi speed được báo theo đơn vị đã chia cho speed, còn giờ marker ProjectItem là
  giờ thật trong file. Dự đoán theo giờ in/out làm marker rơi vào khoảng trống
  giữa hai clip nên không hiện.
- **Invariant.** Giờ nguồn thật của điểm timeline `t` = `(t − start + inPoint) ×
  speed`; vị trí timeline của marker `m` = `start + m/speed − inPoint`. Chưa đo
  speed khác 110%, reverse, time remapping hay nest. Marker dùng chung cho mọi
  sequence dùng cùng file.
- **Hệ quả cần sửa.** `planOwnedClipMarker` (marker tốc độ V1 của #31, marker
  "Kiem tra can voice" A2) đặt marker theo tỉ lệ `inPoint/outPoint` rồi dùng như
  giờ nguồn thật: với speed khác 100% marker lệch, có thể ra ngoài clip.
- **Công cụ.** `tools/probes/` (probe ES3, runner CDP, README) và test
  `probe-voice-clip-markers.test.js`; không nằm trong gói phát hành.

## Issue #32 — Giữ dữ liệu lượt chạy gần nhất cho từng workflow (15/11/2026)

- **Nguyên nhân.** `finally` của Auto edit và caption-only xóa job cả khi
  thành công/lỗi/hủy, làm mất JSON/SRT/plan cần tìm nguyên nhân; stale cleanup
  cũng chưa phân biệt job chẩn đoán cần giữ với job sót quá 24 giờ.
- **Sửa.** Mỗi workflow giữ job cuối cùng với `last-run.json`: workflow
  `edit`/`captions`, outcome `success`/`failed`/`cancelled`, `finishedAt` ISO và
  `toolVersion`. Khi đã tạo job mới, chỉ xóa các job có dấu `last-run.json`
  cùng workflow. Stale cleanup vẫn dọn job khác quá 24 giờ, luôn giữ job có dấu
  mới nhất của mỗi workflow (theo finishedAt, fallback mtime nếu dấu hỏng).
  Lỗi dọn/trim chỉ ghi cảnh báo, không đổi kết quả workflow. Không thêm UI.
- **Thu gọn.** Chỉ WAV/PCM trong job và thư mục con qua `removeTreeSafe` →
  `security.removeOwnedTree`; giữ text/JSON/SRT/plan/log. Caption tạo
  `timeline-*.wav`, `recognition-*.wav`, các cửa sổ `reference-*`,
  `dtw-caption-*`, `numeric-caption-*`, `*-edge.wav`, `*-timing-*.wav`.
  Auto edit nhận diện bằng WAV dưới TEMP/PremiereVoiceSync/job-* và tự dọn
  ở engine `finally`; phần này không đổi, không mở rộng xóa ngoài Jobs.
- **Invariant/recovery.** Vẫn từ chối junction/symlink bằng `assertNoLinks`
  và safe deletion; không chạm workflow kia, job đang chạy hoặc media gốc.
  Job còn `job.json.audio-recovery.json` không bị xóa hay trim bất kỳ file nào.
  Host dùng journal để khôi phục mute/enable/In/Out, kiểm snapshot rồi mới
  xóa journal; scan vẫn phát hiện từng journal và giữ khóa `pvs.recovery.v1`.
  `last-run.json` không tham gia recovery. Auto edit dùng baseline snapshot;
  hướng dẫn Undo/đóng không lưu không đọc dữ liệu job. Không đổi Save/Undo,
  native recovery hoặc điều kiện mở khóa. Lượt dừng trước khi tạo job giữ
  dữ liệu lần trước; journal pending có thể khiến có hơn một job được giữ.
- **Test trước sửa.** `last-run-data.test.js`: **0/13 đạt**, gồm ENOENT do
  Jobs/job đã bị xóa, `previous kept job must be removed`, stale `6 == 3`,
  thiếu `last-run.json`; log gốc ở `_local/last-run-data/red-tests.log`.
- **Test sau sửa.** **13/13 đạt** trên filesystem tạm riêng: success/failed/
  cancelled ở hai workflow; thay đúng workflow; journal; stale 24 giờ/newest;
  active/current; trim lỗi; junction khi trim/prune/stale và sentinel ngoài job.
  Mock Auto edit, workflow notice/cancel, SRT join, caption recovery và metrics
  đều đạt. Các mock luồng cũ stub tại ranh giới retention thay vì giả xóa job;
  test mới kiểm filesystem và safe helpers thật. Entry được ghi **trước khi
  chạy standard suite**.
- **Kết quả cuối.** Standard suite đạt **71 nhóm/131 PS parse** ngay lần đầu;
  test mới **13/13**, security Node **15**/PowerShell **14** checks. Sáu nhóm
  Windows integration bỏ qua: InstallerLifecycle, InstallRollback, PanelRegistry,
  NotificationShortcut, NativeNotifications, IncidentNotifications. Syntax
  `main.js`/`security.js`, executor parity và `git diff --check` đều đạt.
  Codex viết sửa và tự rà; Claude đọc diff và chạy lại standard suite. Khi
  review, Claude khôi phục dòng nhắc "Giữ lại nhật ký khôi phục audio…" trong
  thông báo lỗi của Chỉ tạo subtitle khi journal còn (bản đầu bỏ mất dòng này).
- **Nghiệm thu.** **Native Premiere pending**. Không chạy Premiere, cài,
  build release, commit hay push; không sửa dữ liệu AppData/runtime/dist.

## Issue #30 — Khôi phục marker tốc độ ngoài ngưỡng cho cue-picture (15/11/2026)

- **Yêu cầu/nguyên nhân.** User chủ động đảo chính sách marker tốc độ của
  2.20.86: kế hoạch `srt-cue-picture-v1` phải cảnh báo khi hình ngoài ngưỡng
  đã chọn, kể cả speed native đúng kế hoạch. `_shouldMarkSpeed` trước đây
  bỏ qua `outside`, chỉ marker khi không đọc được speed hoặc lệch >0,01%.
  Panel cũng bỏ vùng cảnh báo v1 và ghi log chỉ giữ retime trong chẩn đoán,
  trái mô tả marker ngoài ngưỡng trong USER_GUIDE.
- **Sửa.** V1 dùng `outside || native unreadable/mismatch`; legacy giữ
  `outside || merged`. Clip marker tốc độ dùng một dòng ngắn theo issue #28,
  ví dụ `Cue 12–13: tốc độ hình 145% (ngưỡng 70–130%) – kiểm tra`.
  Nhãn lấy `plan.captions.Index` phủ khoảng timeline cuối của đoạn hình,
  sắp xếp/bỏ trùng/gộp số liên tiếp; không có caption thì bỏ nhãn, viết hoa
  đầu câu. Không dùng số target cue nội bộ. Speed sai/không đọc được có lý do
  ngắn riêng. Panel lấy vùng từ `pictureSegments` cho v1 và báo một dòng số
  đoạn ngoài ngưỡng, kèm hướng dẫn xem marker đỏ/cam.
- **Invariant.** Không đổi đoạn retime, speed, cut, A2, chặn speed merge cho
  cue-picture, vị trí marker, tên marker, màu đỏ(1)/cam(3)/xanh dương(6),
  ownership/reconciliation hay review marker. Giữ dung sai 0,01% hiện có;
  `speedWarningCount` tại host/`speedWarningSentenceCount` đếm đoạn ngoài
  ngưỡng, không đếm thêm marker mismatch/unreadable trong ngưỡng hay gộp xanh.
  Số planned trong summary engine vẫn là chẩn đoán của bước lập kế hoạch;
  số observed của host là số cảnh báo thực tế. Host giữ ES3; executor chỉ
  sinh lại bằng `Build-DiagnosticExecutor.js`, không sửa tay.
- **Test trước sửa.** diagnostic-executor fail `Exact per-cue retime outside
  the warning band still needs markers`, **0 !== 1**; notification-ux fail
  vùng cảnh báo v1, **0 thay vì 2**. Log host cũ chỉ ở `_local/`.
- **Kiểm chứng trước suite dài.** Bảy file JS review-markers,
  marker-reconciliation, marker-ownership, diagnostic-executor,
  caption-only-host, host-executor-input, notification-ux đều đạt.
  Thêm 24 tổ hợp 150% đỏ/60% cam/100% không marker × full/compact ×
  stable/ba profile, kiểm count/name/tag/nhãn caption cuối; tám ca ghi chú
  phủ mismatch V1/A1, unreadable, merged, không caption và số không liên tiếp.
  Khóa riêng điều kiện mismatch/unreadable và legacy. Entry này được ghi
  **trước khi chạy standard suite**.
- **Kết quả cuối.** Standard suite đạt **70 nhóm/130 PS parse** ngay lần đầu.
  Sáu nhóm Windows integration bỏ qua: InstallerLifecycle, InstallRollback,
  PanelRegistry, NotificationShortcut, NativeNotifications, IncidentNotifications.
  Sau suite chạy lại đúng bảy file JS marker nêu trên, **7/7 đạt**; syntax
  main/security, executor `--check`, Acorn ES3 cho host/executor/caption-input
  và diff whitespace đều đạt. Codex viết sửa và tự rà; Claude đọc diff và
  chạy lại standard suite cùng bảy test JS marker. Báo cáo replay/ghi chú từng đoạn giữ riêng trong `_local/`, không
  đưa dữ liệu người dùng vào file tracked.
- **Nghiệm thu.** Chỉ kiểm chứng tự động/mock/local; **Native Premiere pending**.

## Issue #28 — Rút gọn ghi chú marker theo số Cue cuối (15/11/2026)

- **Yêu cầu/nguyên nhân.** User chạy thật thấy ghi chú dài, lặp vùng giây và
  nhãn “Đoạn phân tích” không tương ứng caption nhìn thấy trong Premiere.
  Panel sinh lý do dài; host thêm số khối nội bộ và khoảng thời gian vào mỗi dòng.
- **Định dạng mới.** `Cue 4: chữ khác SRT – nghe lại`, hoặc `Cue 20–24:
  timing ước lượng – kiểm mép`. Lấy `Index` của caption cuối phủ vùng issue;
  caption-only dùng caption cuối có sẵn, thiếu thì dùng indices cue sẵn có.
  Không có caption phủ vùng thì bỏ nhãn, viết hoa đầu câu. Không trích nguyên
  lời người dùng, không thêm khoảng giây hay số khối phân tích. Giữ confidence
  đến ba chữ số thập phân như trước, bỏ số 0 cuối; giữ số frame/SRT cần thiết.
  Lý do engine chỉ giữ chi tiết ngắn về La Mã/số hoặc nhãn chữ cái khi có.
- **Gộp chữ.** Các issue cùng frame vẫn tạo đúng một marker. Bỏ dòng trùng
  nhãn/lý do dù bounds khác nhau; gộp cùng nhãn nếu dòng <=65 ký tự. Cặp chữ
  khác SRT + timing ước lượng thành `chữ khác SRT, timing ước lượng – nghe lại`;
  cặp khác giữ cả hai hành động nếu khác nhau. Dòng dài giữ riêng, không mất lý do.
- **Invariant.** Giữ nguyên tên marker, ownership tag, vị trí, màu, nhóm frame,
  scope và reconciliation. Marker định dạng cũ cùng name/tag vẫn được nhận và
  thay thế. Không đổi clip marker tốc độ, điều kiện sinh issue, caption/engine,
  quyền DTW/cut/omission hay nhật ký phục hồi. Native postcheck dùng caption
  phủ vùng; failure trên timeline dựng dở không suy nhãn từ plan chưa hoàn tất.
  Lỗi gốc vẫn ở report, marker failure chỉ ghi lỗi thao tác và hướng dẫn thử lại.
  Plan rút gọn chỉ giữ thêm `Index/Start/End` của caption để native postcheck
  có nhãn; vẫn bỏ Text/proof. Host giữ ES3; executor sinh lại từ nguồn, không sửa tay.
- **Test trước sửa.** Năm ca mới fail với `SHORT_MARKER_REGRESSION_FAILED`:
  khối manual có timing + chữ cùng Cue, range Cue 20–24, vùng không caption,
  dòng trùng khác bounds và thay marker cũ. Log chỉ ở `_local/short-marker-text/`.
- **Kiểm chứng trước suite dài.** Năm file JS review-markers,
  marker-reconciliation, marker-ownership, diagnostic-executor và notification-ux
  đều đạt. Có 12 ca format mới và hai ca native caption phủ/không phủ; kiểm cả
  caption-only, confidence, chi tiết engine, dòng dài, duplicate sau gộp và parity
  executor ở ba profile. Entry này được ghi trước khi chạy standard suite.
  Suite lần đầu dừng ở assertion “number review” cũ trong caption-only-host
  (nay ghi hoa đầu dòng khi không có Cue); đã cập nhật fixture/assertion theo
  định dạng thật. Thêm regression plan rút gọn fail trước sửa vì mất nhãn;
  sau giữ geometry thì đạt cả full/compact x stable/ba profile (8 tổ hợp).
  Suite lần hai dừng ở assertion `[null,null]` cũ của host-executor-input;
  đã cập nhật để khóa đúng geometry và không mang Text sang host.
  Test caption-only-host và host-executor-input đều đạt; tổng bảy file JS liên quan.
  Standard suite cuối đạt **70 nhóm/130 PS parse**; sáu nhóm Windows integration
  bỏ qua (InstallerLifecycle, InstallRollback, PanelRegistry, NotificationShortcut,
  NativeNotifications, IncidentNotifications). Syntax main/security, executor parity
  và Acorn ES3 cho host/executor/caption-input đều đạt; diff không lỗi whitespace.
- **Replay local.** Dựng ghi chú bằng host mock từ alignment/plan near-match sẵn có:
  6 issue vẫn thành 6 marker; bounds issue, vị trí, tên và màu bằng trước sửa.
  Ba comment trước/sau chỉ ở `_local/short-marker-text/replay-comments.md`, không
  đưa lời người dùng vào repo. Không chạy lại engine/media/Premiere.
  Codex viết sửa và một lượt tự rà diff/shared/fallback paths; Claude đọc diff
  và chạy lại standard suite cùng bảy test JS marker. Chữ marker nay có tiếng
  Việt có dấu sinh trong host: executor sinh lại đã escape `\uXXXX`, còn
  `host.jsx` vốn đã có chuỗi tiếng Việt; hiển thị thật vẫn cần kiểm trên
  Premiere. **Native Premiere pending**.

## Issue #26 — Khôi phục SRT gần khớp một từ trong khối sửa tay (15/11/2026)

- **Yêu cầu/nguyên nhân.** Sau #22, manual cell vẫn giữ ASR khi chỉ sai một
  dấu/từ vì restore surface đòi exact; restore observed đòi đủ từ DTW và
  >=85% sequential. User phê duyệt nới riêng điều kiện chữ ngày 15/11/2026.
- **Luật.** Helper chung `Restore-PvsNearMatchManualReferenceCell` trong
  `ReferenceAlignment.ps1`, dùng từ cả hai restore path: cue/chuỗi cue liên
  tiếp của chính khối, duy nhất, chưa giữ; bằng số từ >=4, khác đúng một vị
  trí, từ khác không có số, toàn chuỗi số giống nhau; bỏ dấu NFD/đ rồi bằng
  nhau hoặc Levenshtein <=2 và nhỏ hơn độ dài từ ngắn hơn. Không lọc ứng viên
  đã giữ trước khi xét ambiguity. Có ứng viên exact thì để đường exact xử lý.
- **Invariant.** Bounds khối/cell lân cận giữ nguyên; chỉ đổi Text, indices,
  provenance `near-match-one-word`; giữ RecognitionOriginalText và mọi timing.
  Không cấp DTW/cut/omission từ chữ mới. Cell near-match không được đưa vào
  caption-derived cut evidence; đường raw DTW độc lập giữ nguyên. Marker chữ
  tự biến mất qua indices; timing ước lượng còn nguyên. Không thay ngưỡng khác; caption-only không có
  restore exact-only tương đương, không đổi identity/coverage của luồng đó.
- **Test trước sửa.** `Test-AutoEditManualReview` fail với
  `NEAR_MATCH_REGRESSION_FAILED`: 22 ca nhận ở hai path thiếu SRT/provenance.
  Sau sửa mở rộng thành 90 ca (30 x manual/observed rỗng/observed DTW) đạt:
  bảy dạng thay từ, hai cue một/hai khác biệt, NFD/đ, distance 2,
  giữ số/metadata; từ chối hai khác biệt, số, thừa/thiếu, ngắn, distance 3,
  ambiguity/đã giữ, tên tách, bounds và cue không liên tiếp. Nhóm manual,
  acoustic và JS marker đều đạt; marker chữ mất, marker timing còn.
- **Regression quyền cắt.** Test acoustic mới fail trước chốt cuối với
  `near-match-indices-must-not-add-cut-evidence`: indices mới có thể cấp
  caption-derived cut evidence sau timing refinement. Đã chặn theo provenance;
  ba assertion khóa caption DTW còn hợp lệ, không thêm evidence, raw DTW độc
  lập vẫn dùng được. Nhóm manual/acoustic và JS marker đều đạt trước suite.
- **Replay.** Alignment + sentence plan trên mẫu cũ: 83 caption/6 khối như
  #22; exact SRT 51/65 → 57/65, review 12 issue/12 vị trí → 6/6, pending
  metadata 20 → 14. Sáu cue gần khớp được phục hồi. Cue chứa món ăn vẫn ASR:
  cell gộp hai cue có hai từ khác nhau, đúng luật phải review; tên riêng tách
  từ cũng giữ ASR. Không ép đạt bảy cue. Bảng chữ đầy đủ chỉ trong `_local/`.
  Segment hình/voice, 48 quyền cắt và omission không đổi; timing provenance
  giữ nguyên, một timing region manual vẫn còn. Hash media/SRT nguồn trùng.
- **Kiểm chứng.** Standard suite đạt 70 nhóm/130 PS parse, sáu nhóm Windows
  integration bỏ qua; JS syntax hai file, executor parity và JS marker đạt.
  Suite cuối sau chốt quyền cắt cũng đạt 70 nhóm/130 PS parse; replay giữ
  kết quả trên. Codex viết sửa và tự rà; Claude đọc diff và chạy lại
  standard suite (70 nhóm đạt).
  Chỉ output ignored; không thay media/SRT/cache gốc. **Native Premiere pending**.

## Issue #24 — Khôi phục nới mép caption 5 frame (15/11/2026)

User chạy thật thấy caption bắt đầu/kết thúc quá sát sóng âm voice và yêu cầu
quay lại hành vi 2.20.88. Quyết định này đảo quyết định S6 ngày 25/10 đã port
vào 2.20.89 (mục "2.20.89: caption bỏ padding 5 frame ở mép" bên dưới).

- **Nguyên nhân.** `Add-PvsCaptionEdgePadding` (`Srt.ps1`) mặc định 0 frame
  từ 2.20.89; hai caller (`build-sentence-plan.ps1`, `New-PvsStandaloneCaptions`)
  dùng mặc định nên mép caption trùng đúng mốc từ đã căn.
- **Sửa và invariant.** Mặc định đổi thành 5 frame, nên cả Dựng theo voice
  lẫn Chỉ tạo subtitle nới tối đa 5 frame mỗi mép khi còn chỗ; hai caption
  sát nhau chia đều khoảng trống, chạm nhau thì không nới mép trong. Miền
  0–30 giữ nguyên; gọi tường minh 0 frame vẫn gỡ chồng lấn 1 frame và từ
  chối chồng lấn lớn hơn. Padding chạy sau mapping caption; không đổi mép
  hình/voice, không vượt giới hạn voice/sequence/vùng chọn.
- **Test.** Bốn test đang khóa "không padding" đổi sang khóa 5 frame và đều
  fail trên code cũ trước khi sửa: `Test-CaptionOnly` (mép 300/338),
  `Test-CaptionVoiceAlignment` (mặc định 5, tường minh 0, gap 4 frame chia
  2/2, caption chạm nhau, miền 0–30, planner sau mapping voice),
  `Test-CaptionDtwTiming` (mép quanh khoảng nghỉ 23/43),
  `Test-MissingWordTimingRecovery` (gỡ chồng lấn 1 frame và từ chối chồng
  lấn lớn hơn ở cả 5 và 0).
- **Replay đo được.** Planner chạy lại trên alignment đã lưu của mẫu thực
  (issue #22): 83 caption, 61 mép đầu và 83 mép cuối được nới (tối đa 5 frame),
  0 chồng lấn, chữ/metadata caption, đoạn hình/voice, marker và luật khoảng
  không lời không đổi.
- **Kiểm chứng.** Standard suite 70 nhóm đạt, 130 script parse; sáu nhóm
  Windows integration bỏ qua. JS syntax và executor parity đạt. Codex viết
  sửa; Claude đọc diff và chạy lại suite. **Native Premiere pending**.

## Issue #22 — Từ trùng Start bị đảo thứ tự, caption kết thúc sớm (15/11/2026)

- **Nguyên nhân.** Whisper `-ml 1 -sow` sinh nhiều packet đầu cửa sổ cùng
  `from`, có packet zero-length. Cache của mẫu thực có 569 segment/43 span
  bằng không. `Sort-Object Chapter,Start` trên Windows PowerShell 5.1 không
  ổn định, đảo packet trước khi resolver/manual fallback ghép chữ. Các sort
  theo Start trong numeric identity/coverage/supplement cũng có cùng nguy cơ.
  Cue/cell lấy End của phần tử cuối có thể bỏ mất End lớn hơn ở packet trước.
  Strict matcher thực tế yêu cầu span dương **và không overlap**, không chỉ
  Start tăng; không được nới điều kiện đó để chữa chữ.
- **Sửa và invariant.** Sort thời gian của word/cue dùng vị trí trong chuỗi
  đầu vào làm khóa cuối, không sửa packet nguồn hoặc dùng End để xếp word.
  Cue/cell và surface subtitle lấy End lớn nhất. Giữ zero span trong dữ liệu
  lexical cả primary/retry; adapter riêng cho timing repair giữ hợp đồng
  positive-span cũ. Retry zero/overlap chỉ unresolved cục bộ, không cấp recovery
  hoặc omission; NaN/backward/outside vẫn bị từ chối. Retry đã xác minh thay
  cả zero packet ở mép trái cửa sổ, không để lại bản sao từ. Giữ mọi ngưỡng identity,
  số, lời thêm, ambiguity, DTW/quiet/cut/omission và provenance ước lượng.
  Rà mọi sort Start trong engine; các sort còn lại chỉ xếp clip, silence hoặc
  hình học frame, không xếp chữ. Unit projection kiểm toàn span raw đóng góp,
  kể cả component số không còn trong mapping: test overlap cũ lộ ra sau khi
  sửa sort ổn định, không được dựa vào đảo chữ tình cờ để từ chối timing sai.
- **Regression.** `Test-EditedReference` thất bại trên code cũ với
  `TIED_WORD_DECODE_ORDER_LOST` (ba packet đầu bị đảo); khóa cả retry zero,
  input bất biến và không omission; thêm ca tái hiện
  `RETRY_LEFT_EDGE_ZERO_PACKET_DUPLICATED` trước khi sửa merge cửa sổ.
  `Test-AutoEditManualReview` tái hiện
  `TIED_CUE_END_NOT_MAXIMUM:expected=16.6;actual=15.8`, sau sửa giữ nguyên SRT
  khi cell khớp đủ chữ, End lớn nhất tới caption cuối và vẫn estimated.
  `Test-CaptionOnly` khóa thứ tự numeric identity và End hợp của surface.
  Test cũ `Test-SubtitleUnitProjection` tiếp tục từ chối raw overlap.
- **Replay đo được.** Toàn voice gốc, một clip 100%, template đơn giản 30 fps;
  chạy entrypoint alignment và sentence planner cũ/mới, runtime hash-pinned,
  bản sao cache/backend trong vùng ignored; không ghi dữ liệu người dùng.
  Kết quả: 83 caption ở cả hai phía, 17 vùng yêu cầu hết đảo thứ tự;
  chuỗi caption nguyên cue khớp chính xác 37/65 → 51/65, unresolved metadata
  28 → 20 (cell nhiều cue có thể giữ chữ đúng nhưng metadata vẫn pending).
  Marker builder production: 34 issue/17 vị trí frame → 12 issue/12 vị trí dự kiến.
  Tên riêng/ASR khác thật còn review, không chép SRT để ép điểm. End thay đổi
  theo DTW đo lại, không phải mọi cue đều kéo dài. Replay template khác native
  gốc: caption timing retry 3 → 0, estimatedRangeCount 0 → 0 không có nghĩa
  mọi manual cell đều đã có timing xác minh. Không dùng cache hit/miss khác
  nhau để kết luận tốc độ. Bảng 17 cue và JSON/log chỉ ở `_local/`.
- **Kiểm chứng.** Bảy nhóm liên quan đạt; standard suite đạt 70 nhóm/130
  script PowerShell parse, sáu nhóm Windows integration bỏ qua. Hai JS syntax
  check và executor parity đạt; `git diff --check` sạch. SHA-256 voice/SRT
  nguồn không đổi, primary cache dùng lại trùng bản gốc. Codex viết sửa và tự
  rà; Claude đọc diff và chạy lại standard suite (70 nhóm đạt). **Native
  Premiere pending**.
- **Còn lại.** Tám cue trong khối sửa tay vẫn hiện chữ ASR vì khác SRT một dấu
  hoặc một từ (ví dụ thanh điệu, tên riêng): khôi phục chữ SRT trong khối này
  đòi khớp chính xác. Giữ marker review; đổi luật đó cần user quyết riêng.

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
