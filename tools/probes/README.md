# Probe marker trên clip voice — issue #34

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
