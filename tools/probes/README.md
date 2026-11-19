# Probe native marker

## TrackItem giữ qua hai lần gọi host — ghi trước marker không chạy

`Probe-StaleTrackItem.jsx` **chỉ đọc**: không sửa clip, marker, sequence hay project, không Save/Undo. Probe kiểm tra một TrackItem lấy ở một lần `evalScript` có còn báo đúng nguồn (`projectItem.nodeId`) ở lần gọi sau hay không. Mỗi stage của executor là một lần gọi riêng. Theo trace của 2.20.93–2.20.95, khoá nguồn tính từ TrackItem cũ không khớp, nên marker review không được ghi trước khi cắt (hậu kiểm báo `ownerIndex = -1`).

Mở sequence cần kiểm, chọn index track audio của voice (A1 là 0, A2 là 1). Mỗi lệnh dưới đây là một lần gọi host riêng:

```powershell
node tools/probes/run-probe.js load (Resolve-Path tools/probes/Probe-StaleTrackItem.jsx).Path
node tools/probes/run-probe.js stale-capture 1
node tools/probes/run-probe.js stale-compare
node tools/probes/run-probe.js stale-release
```

- `stale-capture` giữ các TrackItem của track đó cùng ProjectItem của chúng. Lệnh đọc mỗi trường hai lần trong cùng lần gọi (`sameCallHeldDiff`, `sameCallRefetchDiff` phải rỗng).
- `stale-compare` đọc lại TrackItem đã giữ và so với TrackItem mới tìm theo `nodeId`. `keyMatchesFresh: false` hoặc `keyMismatches > 0` xác nhận nguyên nhân. `heldVsFreshDiff` cho biết trường nào đổi. `keptProjectItemNodeId` cho biết ProjectItem giữ từ lần trước có còn dùng được không.
- Nếu project hoặc sequence đang mở đổi giữa hai lệnh, probe dừng. Giữa hai lệnh không cần thao tác gì trên timeline.
- `stale-release` bỏ các tham chiếu đã giữ.

Mock (`tests/unit/probe-stale-trackitem.test.js`) chỉ chứng minh cách probe đọc và báo cáo, chưa chứng minh hành vi của Premiere.

**Kết quả ngày 18/11/2026** trên sequence Sông Congo đã dựng, chạy Premiere 2026:

- **A2:** 100 clip. Sau 0,7 giây, cả 100 TrackItem giữ từ lần gọi trước vẫn đọc đúng mọi trường, gồm `projectItem.nodeId`, `treePath` và `getMarkers`. `keyMismatches` bằng 0, `heldVsFreshDiff` rỗng. ProjectItem giữ lại cũng còn dùng được.
- **Khác mock:** Premiere trả một object mới ở mỗi lần đọc `clips[i]`, kể cả trong cùng một lần gọi (`sameObject: false`). Mock thì trả cùng một object.
- **A1:** 130 clip, `nodeId` không trùng với A2.

Kết luận: TrackItem cũ **không** làm mất khoá nguồn, nên giả thuyết này bị loại. Nguyên nhân pre-commit không ghi vẫn chưa xác định.

## Kiểm tra thứ tự ghi start và end — issue #67

`Probe-MarkerMoveEnd.jsx` đo hai biên sau từng phép ghi trên ProjectItem đã chọn. Nạp probe, lấy `documentId` và `nodeId` từ `move-list`, rồi thay hai giá trị mẫu trong lệnh dưới đây.

```powershell
node tools/probes/run-probe.js load (Resolve-Path tools/probes/Probe-MarkerMoveEnd.jsx).Path
node tools/probes/run-probe.js move-list
$probeDoc = '<documentId>'
$probeItem = '<nodeId>'
$probeTag = '[PremiereVoiceSync:marker-move-end:v1]'
node tools/probes/run-probe.js move-run $probeDoc $probeItem $probeTag probe-tagged-only
node tools/probes/run-probe.js move-cleanup $probeDoc $probeItem $probeTag probe-tagged-only
```

`move-run` yêu cầu đúng project, item, tag và scope. Nếu còn marker mang tag từ lượt trước, probe dừng. Sau khi thử, kể cả khi gặp lỗi, probe chỉ dọn marker mới có dòng đầu của comments trùng tag, rồi đối chiếu bộ marker còn lại với ảnh chụp ban đầu. Nếu tạo marker nhưng ghi tag thất bại, marker chưa có tag được giữ để kiểm tra thủ công. Lệnh `move-cleanup` dành cho tag còn sót trên item đã chọn và xác minh các marker ngoài tag sau khi dọn.

**Kết quả ngày 18/11/2026.** Trên ProjectItem voice của Premiere 26.2.2, số marker trước và sau là 59, `cleanup.verified` bằng `true`. Bảng dùng giây tính từ vị trí tạo marker. Đổi start giữ nguyên độ dài, đổi end chỉ dời biên cuối. Premiere cho phép thu marker về điểm.

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

## Kiểm tra ghi lại marker nguồn hình — issue #75

Trace 2.20.98 ghi 19 lượt dời start và 19 lượt ghi end trên nhóm marker hình. Hai phép đo dưới đây giúp kiểm tra vị trí marker đang có và cách ProjectItem của nest xử lý một lần ghi start.

**Kết quả ngày 19/11/2026** (Premiere 26.2.2, host panel 2.20.98, sequence Sông Congo vừa dựng xong và chưa Save, 30 fps):

- Lượt Dựng theo voice ngay trước đó chạy từ bản lưu cũ. Bước "Cập nhật marker nguồn" của nhóm hình vẫn dời 19 marker và ghi end 19 lần (14,3 s). Ghi trước marker review cũng dời 21 marker và ghi lại comments của chúng.
- `picture-plan 0` trên kết quả: 130 clip V1 dùng chung một nest (timebase 8.467.200.000, 30 fps). Cả 19 marker hình là marker điểm và nằm đúng frame giữa (lệch lớn nhất khoảng 1,7e-10 frame). Dự đoán: 19 `keep`, 0 `move`, 0 `endWrite`, 0 marker dư. Speed của các clip từ khoảng 46% đến 158%.
- Kết luận: chạy lại trên kết quả vừa dựng sẽ không phải dời marker hình. Lượt dời và ghi end là bước đổi marker cũ trong bản lưu, nhiều khả năng vì bản lưu có từ trước luật "marker điểm ở giữa đoạn" của 2.20.94 (chưa đối chiếu thời điểm lưu). Probe ghi trên nest vì vậy chưa cần chạy. Dữ liệu ở `_local/probe-picture-plan-20261119.json`.
- Lượt chạy lại thật (15:35, cùng project chưa Save, sequence template chưa dựng, nest đã mang marker của lượt trước) xác nhận dự đoán: nhóm hình 19 marker, 0 dời, 0 ghi end, commit 49 ms; "Cập nhật marker nguồn" 0,64 s thay vì 14,6 s.

Dùng cấu hình debug/Node 22+ bên dưới khi user đã cho phép chạy. Mở sequence cần kiểm tra. Lệnh `picture-plan` chỉ đọc track video theo index bắt đầu từ 0 (V1 là 0). Phiên bản cho 3.0.0 nhận marker Video theo tên và thẻ mới.

```powershell
node tools/probes/run-probe.js 8099 load (Resolve-Path tools/probes/Probe-PictureMarkerPlan.jsx).Path
node tools/probes/run-probe.js 8099 picture-plan 0
```

- Mỗi clip có `index`, `name`, `projectItemNodeId`, `isSequence`, `start`, `end`, `inPoint`, `outPoint`, `speed.raw` và `speed.factor` chuẩn hóa theo host. Mỗi mốc có giây và ticks gốc nếu Premiere trả về. `timebase` là số tick mỗi frame, `fps` tính từ timebase. `nest` ghi timebase/fps của sequence nguồn tìm theo nodeId. `nest: null` trên sequence ProjectItem nghĩa là chưa đọc được timebase nguồn.
- Mỗi marker hình có tên, GUID, hai biên và `isPoint` (so ticks nếu đọc được cả hai biên). `timelineSeconds` là start ánh xạ lên timeline. `insideClipRange` dùng khoảng nửa mở từ start đến end. `distanceToMiddleFrames` là vị trí đã ánh xạ trừ `middleOutputFrame`, tính theo frame của sequence ngoài. `nestGridDeltaTicks` và `outerGridDeltaTicks` so start **nguồn** với frame gần nhất trên mỗi lưới. `timelineGridDeltaTicks` so start **đã ánh xạ** với lưới ngoài. Số 0 nghĩa là trùng lưới, `null` nghĩa là thiếu dữ liệu. Phép tính delta timeline dùng giây nên có thể lẻ tick.
- `desiredSourceSeconds` là frame giữa ánh xạ bằng công thức của host. `verify` ghi riêng hai biên có nằm trong vùng hay không, end có sát start trong nửa dung sai hay không, start có cách mục tiêu không quá nửa frame nguồn hay không, và kết quả chung. `nearMatch` dùng khoảng cách nhỏ hơn `0.25/fps` so với mục tiêu giữa.
- `targetSourceSeconds` là vị trí `point()` chọn khi xét các marker đang có. `commitSourceSeconds` là vị trí sau `add()`, có thể trùng vị trí marker cũ (`snappedToStoredPosition`). `commitNearMatch` cho biết marker đang xét có khớp tại vị trí đó. `predictedAction` là `keep`, `move`, `endWrite` hoặc `null` kèm `reason`. Với `move`, việc ghi thêm end phụ thuộc vào giá trị Premiere trả về sau khi dời start. `markerToolsSource` cho biết `point()` và `add()` chạy từ host đã nạp hay bản sao có test đối chiếu. `mappingSource` cho biết nguồn của hàm ánh xạ.
- `summary` đếm dự đoán theo cặp clip/marker và ghi độ lệch tuyệt đối lớn nhất ở `maxAbsDelta`. Nest dùng chung một bộ marker cho nhiều clip, nên mỗi clip chỉ liệt kê marker rơi vào vùng của clip đó; `outsideClip` đếm số cặp đã bỏ qua. Marker hình không rơi vào clip nào trên track nằm ở `unmatchedPictureMarkers` (đếm ở `summary.unmatchedPictureMarkers`): đây là marker dư mà bước ghi có thể ghép với một yêu cầu rồi dời đi. `sequenceOwners` và tổng `otherOwnedMarkers` đếm theo ProjectItem. Probe chỉ trả tổng cho tên marker căn voice/review, không xuất ghi chú. `markerReadError` cho biết collection nào chưa đọc được.

Mỗi dự đoán dùng một yêu cầu tại khoảng timeline hiện tại của clip, với tên và comments của marker đang xét để thử nhánh snap. Kết quả vì vậy phụ thuộc vào giả định metadata giữ nguyên. Có thể so hai JSON theo `documentId`, `sequenceId`, nodeId, GUID, ticks và frame giữa để xem trạng thái marker hoặc clip đã đổi qua các lần mở/chạy. Probe không có `NewStartFrame`, `VisualDurationFrames` hoặc danh sách yêu cầu của lần Auto edit tiếp theo. Clip reverse hoặc time remap không đọc được sẽ thiếu dự đoán.

Phép thử ghi dùng **nest trong project bỏ đi**. ProjectItem dùng chung marker với các clip lấy cùng nguồn, kể cả khi duplicate sequence ngoài. Chọn nest đủ dài cho các vị trí thử (khoảng 17 giây nếu collection trống, xa hơn nếu các vị trí đầu đã có marker).

```powershell
node tools/probes/run-probe.js 8099 load (Resolve-Path tools/probes/Probe-MarkerMoveEnd.jsx).Path
node tools/probes/run-probe.js 8099 move-list probe-tagged-nest
$probeDoc = '<documentId>'
$probeItem = '<nodeId>'
$probeTag = '[PremiereVoiceSync:marker-move-end:v1]'
node tools/probes/run-probe.js 8099 move-run $probeDoc $probeItem $probeTag probe-tagged-nest
# Chi chay lenh don neu con marker mang tag va da duoc phep.
node tools/probes/run-probe.js 8099 move-cleanup $probeDoc $probeItem $probeTag probe-tagged-nest
```

- `move-list probe-tagged-nest` liệt kê sequence ProjectItem với `isSequence: true`. Lượt ghi yêu cầu đúng documentId, nodeId, tag và scope, đồng thời cần đọc được timebase nest. Scope thường `probe-tagged-only` dành cho media như trước.
- Ba case dời start từ marker điểm mới thêm theo 0,37 frame, 1,37 frame và đúng một frame của nest. `created` là hai biên sau khi tạo. `initial` là hai biên trước khi dời start. Mỗi `steps` ghi `requested` theo giây, `requestedTicks` quy đổi, lỗi ghi/đọc và start/end đọc lại theo giây/ticks. So `requestedGridDeltaTicks` với `startGridDeltaTicks` để xem có làm tròn không. So start/end với `initial` để xem end có dời theo start không. Các delta lưới bằng 0 nghĩa là trùng frame, `null` nghĩa là Premiere chưa cung cấp ticks cho biên đó.
- Probe từ chối đo khi còn tag cũ. Probe chỉ sửa marker mới sau khi gắn và đọc lại tag. Trong `finally` probe dọn marker mới có đúng tag và kiểm tra toàn bộ collection so với ảnh chụp ban đầu (`cleanup.verified`). Marker không tag được giữ để kiểm tra thủ công. `move-cleanup` chỉ dọn đúng tag và đối chiếu phần còn lại với trạng thái ngay trước lệnh dọn. Không Save/Undo. Sau lỗi hoặc timeout, chờ host trả quyền điều khiển và kiểm tra marker trước khi gọi tiếp.

## Kiểm tra lệch ánh xạ voice và khôi phục marker — 2.20.97

**Đã gỡ (#94/#95):** bản mới không còn bước khôi phục marker nên `Probe-MarkerRestore.jsx` và test mock của nó đã xoá. Phần dưới giữ làm lịch sử đo.

`Probe-MarkerRestore.jsx` dùng cấu hình debug/Node 22+ bên dưới.
Mở sequence cần đo rồi chạy lệnh chỉ đọc. Index audio bắt đầu từ 0 (A2 là 1).

```powershell
node tools/probes/run-probe.js load (Resolve-Path tools/probes/Probe-MarkerRestore.jsx).Path
node tools/probes/run-probe.js restore-projection 1
```

- `restore-projection` đọc từng clip trên track đang chọn. `timebase` là số tick mỗi frame, `fps` tính từ timebase. Với `start`, `end`, `inPoint`, `outPoint`, kết quả có `seconds` và `ticks` Premiere trả về, `tickSeconds` đổi từ ticks, `frame` làm tròn từ seconds, và `frameSeconds` đổi lại từ frame. `deltaVsTicks` và `deltaVsRoundedFrameTicks` là độ lệch có dấu của `seconds` so với hai phép đổi, tính bằng tick. `speedSource` cho biết hệ số `speed` lấy từ hàm host hay bản sao.
- Ngày 19/11/2026, Premiere 26.2.2, sequence mẫu ở 30 fps có một clip A2 speed 1.1 với hai mép timeline trên lưới frame và `outPoint` thấp hơn lưới một tick. Sequence đã dựng có 101 clip A2 cùng speed 1.1. Cả 101 `start` và `end` nằm đúng lưới frame, với `.seconds` đúng bằng ticks đổi ra giây. Có 100/101 `inPoint` lệch lưới tối đa khoảng 80 tick và 101/101 `outPoint` lệch tối đa khoảng 2 tick. Số đo xác nhận giả thuyết A về việc phép so tuyệt đối ở `input` báo lệch giả. Dữ liệu ở `_local/probe-restore-projection-built.json`.
- Báo cáo Auto edit có `voiceProjection.piecesCompared`, `firstMismatch` và `maxAbsDeltaTicks` cho `start`, `end`, `input` trên các lát đã so. Chỉ số lát bắt đầu từ 0. `deltaTicks` và `deltaFrames` bằng giá trị đọc từ clip trừ dự đoán. Khi lệch khoá nguồn, khoá dạng đường dẫn hiển thị là `path`. `firstMismatch: null` nghĩa là mọi lát đã so đều trong dung sai.

Dùng project thử và media thử riêng cho phép đo ghi marker. Lấy `documentId` và `nodeId` từ `restore-list` rồi điền vào hai biến bên dưới. Với nguồn chưa có marker, các vị trí thử bắt đầu khoảng giây 41, cách nhau 6 giây. Media thử dài khoảng 65 giây đủ cho các vị trí mặc định. Nếu có marker sẵn gần vị trí thử, probe tìm vị trí xa hơn.

```powershell
node tools/probes/run-probe.js restore-list
$probeDoc = '<documentId>'
$probeItem = '<nodeId>'
$probeTag = '[PremiereVoiceSync:marker-restore:v1]'
node tools/probes/run-probe.js restore-run $probeDoc $probeItem $probeTag probe-tagged-only
node tools/probes/run-probe.js restore-journal $probeDoc $probeItem $probeTag probe-tagged-only
# Chi chay cleanup neu can don tag con sot.
node tools/probes/run-probe.js restore-cleanup $probeDoc $probeItem $probeTag probe-tagged-only
```

- `restore-run` thử dời marker điểm, dời và đổi độ dài marker khoảng, xóa rồi tạo lại, và đổi màu. `requestedSeconds` là vị trí yêu cầu ban đầu. `prior` là giá trị Premiere đọc lại trước khi thay đổi, `modified` là trạng thái sau khi thay đổi và `actual` là trạng thái sau khôi phục. Theo thứ tự của host, ghi start trước rồi chỉ ghi end nếu end đọc lại còn khác. Khi tạo lại, ghi end nếu cần, rồi ghi name, comments và màu. `markerToolsSource` cho biết probe dùng hàm host đang nạp hay bản sao.
- Ngày 19/11/2026, `restore-run` dùng hàm host trên ProjectItem voice thật trong Premiere 26.2.2. Cả bốn ca đều có `fingerprintMatches=true`, không ghi nhận sai khác và dọn xong vẫn đủ 59 marker gốc. Start yêu cầu 41.1745078411745 giây đọc lại thành 41.1745078411714 giây. Khôi phục theo giá trị đã đọc lại cho kết quả chính xác. Các ca một giao dịch với comments ASCII chưa tái hiện lỗi `Original marker fields differ.` của giả thuyết B. Dữ liệu ở `_local/probe-restore-run.json`.
- `restore-journal` cần host của panel đã nạp `$._PVS._markerTools`. Probe tạo marker điểm và marker khoảng có ghi chú tiếng Việt nhiều dòng. Giao dịch voice dời hai marker và tạo thêm một marker, dùng `keepSurplus=true` như lúc ghi trước khi cắt. Giao dịch review dùng cùng collection, cùng nhật ký và các vị trí voice đã đặt chỗ. Để thử đường xóa rồi tạo lại, probe tắt ghép dời và cho xóa marker review dư như lượt đối chiếu cuối. Lượt ghi trước của Auto edit cho phép ghép dời và giữ marker dư. Probe đặt vị trí nguồn trực tiếp, rồi gọi đúng `restore(journal)` như nhánh lệch của Auto edit.
- Ngày 19/11/2026, `restore-journal` chạy trên ProjectItem voice thật đó (host panel 2.20.96). Giao dịch voice dời 2 và tạo 1 marker. Giao dịch review tạo 2 và xóa 2. Khôi phục không báo lỗi, không còn mục nhật ký nào, `fingerprintMatches=true`, comments tiếng Việt khớp từng ký tự, không có marker lạ. Dọn xong vẫn đủ 59 marker gốc. Giả thuyết B vẫn chưa tái hiện được. Dữ liệu ở `_local/probe-restore-journal.json`.
- `differences` liệt kê các trường lệch, kể cả lệch dưới một tick. Với comments, kết quả ghi độ dài, chỉ số và mã UTF-16 của từng ký tự khác nhau, tính từ 0. `restore-journal` ghi lỗi từ host, số mục nhật ký còn lại, `fingerprintMatches` cho toàn bộ ảnh chụp và `commentsByteIdentical` cho từng marker lẫn toàn bộ lượt thử. Khi tạo lại, phép so dùng GUID thay thế do host ghi nhận.
- Lệnh ghi chỉ dùng ProjectItem media khớp ID, tag và scope. Nếu còn marker mang tag từ lượt trước, lượt thử dừng. Khi kết thúc hoặc gặp lỗi, probe chỉ dọn marker mới có dòng đầu comments khớp tag và đối chiếu toàn bộ collection với ảnh chụp ban đầu. Nếu ghi tag thất bại thì marker chưa có tag được giữ để kiểm tra thủ công. `restore-cleanup` chỉ xóa marker mang đúng tag và kiểm tra các marker còn lại. Các lệnh ghi chỉ thao tác trên marker nguồn. Probe không Save/Undo.

Mock (`tests/unit/probe-marker-restore.test.js`) kiểm tra cách đọc, thứ tự khôi phục hai giao dịch, báo mã ký tự khi sai dấu tiếng Việt và dọn theo tag.

## Đo chi phí ghi marker — issue #49

`Probe-MarkerWriteCost.jsx` là phép đo riêng, **chưa chạy native**. Không dùng
project/media thật, kể cả bản duplicate sequence: ProjectItem chia sẻ marker
với mọi sequence dùng cùng nguồn. User tự tạo project bỏ đi, import media thử
riêng và chọn ProjectItem từ `cost-list` theo `nodeId`. Probe chỉ duyệt cây
ProjectItem, không truy cập sequence, Save hoặc Undo. Bắt buộc truyền đúng
`documentId`, `nodeId`, tag `[PremiereVoiceSync:marker-write-cost:v1]` và scope
`throwaway-project`; scope là xác nhận của người chạy về project thử, không
phải cơ chế tự phát hiện media thật. Mỗi lượt native cần được user cho phép.

Dùng cấu hình debug/Node 22+ bên dưới. Sau khi user đã cho phép phép đo:

```powershell
$probePath = (Resolve-Path tools/probes/Probe-MarkerWriteCost.jsx).Path
node tools/probes/run-probe.js 8099 load $probePath
node tools/probes/run-probe.js 8099 cost-list
# Thay hai ID bang gia tri cost-list tra ve cua project/media thu.
$documentId = '<documentId>'
$nodeId = '<nodeId>'
$probeTag = '[PremiereVoiceSync:marker-write-cost:v1]'
node tools/probes/run-probe.js 8099 cost-run $documentId $nodeId $probeTag throwaway-project
# Co the them N cuoi lenh, so nguyen 1..100; mac dinh 10.
```

Probe dành sẵn N vị trí nguồn không trùng marker cũ, cách nhau 2 giây, bắt đầu
tìm từ giây 1, giới hạn 100.000 giây; cần media thử đủ dài cho
`sourcePositions` (với collection trống, N=10 cần ít nhất 20 giây, N=100 cần
ít nhất 200 giây). Cây project tối đa 10.000 item/32 cấp, collection tối đa
10.000 marker. Không chọn sequence ProjectItem; thiếu API xác định media/màu
thì dừng. Có tag probe tồn tại từ trước thì từ chối đo tiếp.

JSON `metrics` ghi `count`, `totalMs`, `averageMs` cho N lần `createMarker`,
`name`, `comments`, `end`, `setColorByIndex`, `getColorByIndex`, `deleteMarker`
và **một** lượt đọc toàn collection (gồm start/end/name/comments/type/color).
Gắn tag ban đầu, snapshot, hậu kiểm và cleanup nằm ngoài các số đo này;
không cộng `collectionRead` với đọc màu thành tổng độc lập. Đọc metadata và
kiểm tra sau ghi không phải native proof về tốc độ hoặc UI.

`moves` ghi riêng hai lần thử gán start của marker đã có tag: `Time` và số
giây; mỗi lần có before/requested/after, assignmentError/readError và accepted.
Gán không ném lỗi vẫn có thể bị bỏ qua; gán ném lỗi vẫn có thể đã đổi vị trí.
Chưa dùng kết quả giả lập này để triển khai di chuyển marker trong host.

Probe luôn thử dọn các marker mới có tag trong `finally`, rồi so toàn bộ
collection với snapshot trước phép thử, gồm GUID và mọi field đã đọc.
`deletionVerified` kiểm riêng kết quả N lần xóa đo được; nếu chúng thất bại
nhưng cleanup cứu được thì `ok` vẫn false. Thành công cần `ok: true`,
`deletionVerified: true`, `cleanup.verified: true`, không có cleanup errors.
Native tạo rồi ném lỗi trước khi gắn tag, hoặc ghi tag thất bại, có thể để lại
marker không tag: script báo collection khác và **không xóa** marker đó.
User kiểm tra thủ công trong project bỏ đi; không chạy lặp mù khi lỗi/timeout.
Runner chờ tối đa 10 phút cho `cost-run`/`cost-cleanup` (các lệnh cũ giữ 30 giây),
timeout không hủy native call. Chờ host trả quyền điều khiển, kiểm tra trạng
thái trước mọi lệnh tiếp theo. Lệnh dọn riêng chỉ xóa đúng tag trên item/scope:

```powershell
node tools/probes/run-probe.js 8099 cost-cleanup $documentId $nodeId $probeTag throwaway-project
```

Lệnh dọn riêng xác nhận phần không tag giữ nguyên so với trạng thái ngay trước
khi dọn, không thay thế snapshot của lượt `cost-run` bị gián đoạn. Ghi JSON và
quan sát vào [mẫu kết quả](../../docs/reviews/MARKER_WRITE_COST_PROBE_2026-11-16.md),
kiểm tra collection còn nguyên, rồi gỡ cấu hình debug tạm. Mock chỉ chứng minh
phép tính, giới hạn và cleanup giả lập; chưa đo Premiere.

## Marker trên clip voice — issue #34

Phép thử nhỏ trước khi làm feature: tạo/đọc marker Comment tại thời gian SOURCE
trên ProjectItem voice, so vị trí dự đoán trên timeline, quan sát khi kéo/trim bằng
tay, kiểm tra media dùng chung và xóa riêng marker có tag
`[PremiereVoiceSync:probe:v1]`. Mock chỉ kiểm tra phép tính và giới hạn thao tác;
chưa chứng minh Premiere hiển thị đúng. Ghi kết quả vào
[mẫu native](../../docs/reviews/VOICE_CLIP_MARKER_PROBE_2026-11-15.md).

## Chuẩn bị thủ công, khi user đã cho phép chạy native

Node 22+ dùng global `fetch`/`WebSocket`, không cần npm. PlayerDebugMode của CEP
phải bật. Trong thư mục panel đã cài, tạo tạm file `.debug` với nội dung:

```xml
<ExtensionList><Extension Id="com.premierevoicesync.local.panel"><HostList><Host Name="PPRO" Port="8099"/></HostList></Extension></ExtensionList>
```

Maintainer/user tự chuẩn bị cấu hình và mở/nạp lại panel theo quyền đã duyệt;
script không sửa registry, bản cài hay khởi động Premiere. Xóa `.debug` tạm sau
khi xong và khôi phục cấu hình debug trước đó nếu có thay đổi.

## Quy trình

1. User **duplicate sequence bằng tay trước**; dùng bản thử và kiểm tra đúng A2.
   ProjectItem vẫn dùng chung: marker có thể xuất hiện trên mọi track item và
   **mọi sequence dùng cùng media**, kể cả sequence gốc. Duplicate không cô lập
   marker source. Ghi lại marker thủ công có sẵn để đối chiếu sau khi xóa.
2. Chạy `load`, rồi `list 1`; index bắt đầu từ 0, A2 là 1. Chọn clipIndex từ
   kết quả thực tế; các lệnh dưới minh họa clip 0. Chỉ `create`/`remove` ghi marker.
3. Chọn offset SOURCE nằm trong `[inPoint, outPoint)`, không trùng marker cũ.
   Ví dụ `2.0` tạo tại `inPoint + 2`, không nhân speed. Mỗi lần `create` tạo một
   marker mới, không tự dọn marker cũ; không chạy lặp mù khi timeout/lỗi.
4. So `marker.start`, `requestedSourceTime`, `sourceTimeDelta` và vị trí nhìn thấy.
   `expectedTimelineTime = clip.start + (sourceTime - clip.inPoint) / speed.factor`.
   `speed.raw` giữ số API trả về; factor theo cách chuẩn hóa của host (<=10 là
   ratio, >10 là percent/100). Unknown/reverse trả vị trí `null`; công thức không
   chứng minh time remapping. Không coi dự đoán là quan sát native.
5. User kéo clip rồi trim bằng tay; chạy lại `list` để xác định clipIndex và
   `read` sau mỗi bước. Giữ source marker trong vùng trước, rồi thử trim qua nó:
   `insideSourceRange` cho biết trong/ngoài `[inPoint, outPoint)`. Probe không
   di chuyển/trim clip. Quan sát cả Source Monitor và clip timeline nếu cần.
6. Kiểm tra các track item dùng chung trong sequence hiện hành (audio và video
   đều có trong `trackItems`). User mở sequence khác dùng media đó bằng tay và
   chạy `list`/`read` với index phù hợp; probe chỉ quét sequence đang active.
7. `remove` chỉ xóa marker có đúng tag probe, kể cả ngoài vùng clip đã trim;
   đọc lại để xác nhận `remaining: 0`, marker thủ công/marker workflow khác còn
   nguyên. Hoàn tất bảng kết quả và gỡ `.debug` tạm.

**Xóa marker probe trước khi lưu. Không Save giữa phép thử, trừ khi user tự
quyết định.** Probe không Save/Undo, không đụng sequence markers. Nếu native API
lỗi giữa lúc tạo/xóa, có thể đã ghi một phần; kiểm tra bằng `read` và quan sát,
chỉ gọi `remove` rõ ràng để dọn tag. Marker chưa gắn được tag phải được user
kiểm tra thủ công; script không xóa marker không có tag, không tự retry/rollback.

Chạy tại root repo trong PowerShell (đổi port/clipIndex/offset khi cần):

```powershell
node tools/probes/run-probe.js 8099 load "F:/Tools/Premiere Voice Sync/tools/probes/Probe-VoiceClipMarkers.jsx"
node tools/probes/run-probe.js 8099 call list 1
node tools/probes/run-probe.js 8099 call create 1 0 2.0
node tools/probes/run-probe.js 8099 call read 1 0
# User keo/trim bang tay, sau do chay lai list/read.
node tools/probes/run-probe.js 8099 call list 1
node tools/probes/run-probe.js 8099 call read 1 0
node tools/probes/run-probe.js 8099 call remove 1 0
node tools/probes/run-probe.js 8099 call read 1 0
```

Có thể bỏ port, mặc định 8099. Runner đọc `http://localhost:<port>/json`, chọn
đúng một target loại `page` có WebSocket và id panel trong URL/title, hoặc
`index.html` kèm tên/id Premiere Voice Sync. Không tìm thấy hoặc có nhiều target
khớp thì dừng. Runner dùng CDP `Runtime.evaluate` với `awaitPromise:true` để gọi
`window.__adobe_cep__.evalScript`, in JSON đẹp và báo lỗi rõ ràng; không tự chạy
probe khi load. Không gọi runner vào debugger thật trong kiểm thử tự động.

Các file ở đây chỉ dành cho dev. `installer/build-release.ps1` dùng
`Copy-PvsReleaseExtension` từ `installer/release-common.ps1` với allowlist runtime
trong `extension/`, cộng các file tài liệu/script được chỉ định riêng; không copy
`tools/`, `tests/` hay `docs/reviews/`. Không cần sửa allowlist hoặc build ZIP.
