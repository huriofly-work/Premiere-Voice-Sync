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

## Kiểm tra lệch ánh xạ voice và khôi phục marker — 2.20.97

`Probe-MarkerRestore.jsx` **chưa chạy native**. Dùng cấu hình debug/Node 22+ bên dưới.
Mở sequence cần đo rồi chạy lệnh chỉ đọc. Index audio bắt đầu từ 0 (A2 là 1).

```powershell
node tools/probes/run-probe.js load (Resolve-Path tools/probes/Probe-MarkerRestore.jsx).Path
node tools/probes/run-probe.js restore-projection 1
```

- `restore-projection` đọc từng clip trên track đang chọn. `timebase` là số tick mỗi frame, `fps` tính từ timebase. Với `start`, `end`, `inPoint`, `outPoint`, kết quả có `seconds` và `ticks` Premiere trả về, `tickSeconds` đổi từ ticks, `frame` làm tròn từ seconds, và `frameSeconds` đổi lại từ frame. `deltaVsTicks` và `deltaVsRoundedFrameTicks` là độ lệch có dấu của `seconds` so với hai phép đổi, tính bằng tick. `speedSource` cho biết hệ số `speed` lấy từ hàm host hay bản sao.
- Báo cáo Auto edit có `voiceProjection.piecesCompared` và `firstMismatch` khi bước so ánh xạ chạy. Chỉ số lát bắt đầu từ 0. `deltaTicks` và `deltaFrames` bằng giá trị đọc từ clip trừ dự đoán. Khi lệch khoá nguồn, khoá dạng đường dẫn hiển thị là `path`. `firstMismatch: null` nghĩa là mọi lát đã so đều khớp.

Dùng project thử và media thử riêng cho phép đo ghi marker. Lấy `documentId` và `nodeId` từ `restore-list` rồi điền vào hai biến bên dưới. Với nguồn chưa có marker, các vị trí thử bắt đầu khoảng giây 41, cách nhau 6 giây. Media thử dài khoảng 65 giây đủ cho các vị trí mặc định. Nếu có marker sẵn gần vị trí thử, probe tìm vị trí xa hơn.

```powershell
node tools/probes/run-probe.js restore-list
$probeDoc = '<documentId>'
$probeItem = '<nodeId>'
$probeTag = '[PremiereVoiceSync:marker-restore:v1]'
node tools/probes/run-probe.js restore-run $probeDoc $probeItem $probeTag probe-tagged-only
# Chi chay cleanup neu can don tag con sot.
node tools/probes/run-probe.js restore-cleanup $probeDoc $probeItem $probeTag probe-tagged-only
```

- `restore-run` thử dời marker điểm, dời và đổi độ dài marker khoảng, xóa rồi tạo lại, và đổi màu. `requestedSeconds` là vị trí yêu cầu ban đầu. `prior` là giá trị Premiere đọc lại trước khi thay đổi, `modified` là trạng thái sau khi thay đổi và `actual` là trạng thái sau khôi phục. Theo thứ tự của host, ghi start trước rồi chỉ ghi end nếu end đọc lại còn khác. Khi tạo lại, ghi end nếu cần, rồi ghi name, comments và màu. `markerToolsSource` cho biết probe dùng hàm host đang nạp hay bản sao.
- `differences` liệt kê từng trường lệch, kể cả lệch dưới một tick. Với comments chỉ ghi độ dài và vị trí ký tự khác đầu tiên, tính từ 0. `fingerprintMatches` so nội dung theo host. Marker tạo lại nhận GUID mới, ngoài phép so này.
- Lệnh ghi chỉ dùng ProjectItem media khớp ID, tag và scope. Nếu còn marker mang tag từ lượt trước, lượt thử dừng. Khi kết thúc hoặc gặp lỗi, probe chỉ dọn marker mới có dòng đầu comments khớp tag và đối chiếu toàn bộ collection với ảnh chụp ban đầu. Nếu ghi tag thất bại thì marker chưa có tag được giữ để kiểm tra thủ công. `restore-cleanup` chỉ xóa marker mang đúng tag và kiểm tra các marker còn lại. Các lệnh ghi chỉ thao tác trên marker nguồn. Probe không Save/Undo.

Mock (`tests/unit/probe-marker-restore.test.js`) kiểm tra cách đọc, thứ tự ghi và dọn trong mô hình giả lập. Hai giả thuyết về sai khác số thực và đọc lại marker vẫn chờ kết quả Premiere.

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
