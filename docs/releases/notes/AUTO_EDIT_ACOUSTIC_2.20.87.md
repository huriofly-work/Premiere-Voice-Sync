# 2.20.87 — Chia đợt native có giới hạn và dữ liệu gọn

Native86 Alien bắt đầu21:05:10, alignment246307ms/CUDA/248 cache hit,
planning89687ms, vào timeline21:10:54. Performance trace bật
`batchLimitsDisabled:true`. Lượt chuẩn bị273734ms; một số lượt host9/23ms
nhưng wall112289/113050ms. Call7 “Tăng speed V1–A1” lúc21:24:00 chưa có
response khi kiểm tra. Panel báo gần30 phút không phản hồi; người dùng
bấm Dừng cũng không trả về. Quan sát cửa sổ không thấy modal; Windows
Responding=true, CPU tăng rất ít trong lúc chờ. Không đủ chứng cứ xác định
chính xác QE lookup, setSpeed hay một native accessor đang giữ lệnh.

## Lỗi xác định được và thay đổi

Generator bỏ cả giới hạn đợt trong profile no-delay. Với302 hình, vòng speed
có thể xử lý toàn bộ trong một lần `evalScript`, không có ranh giới nhận
yêu cầu hủy. Không-delay giờ chỉ bỏ thời gian ngủ: mọi vòng giữ giới hạn,
no-delay tối đa20 iteration/250ms (không thể ngắt giữa iteration), speed
tối đa4 cặp/đợt cho cả baseline/fast/no-delay. Một cặp V1–A1 vẫn nguyên tử,
thứ tự/đối số native không đổi. Native đơn lẻ có thể lâu hơn budget.

Kế hoạch đầy đủ còn mang proof DTW, manual cells và caption text vào
ExtendScript dù executor không sử dụng chúng. Tạo `timeline-executor.json`
riêng, JSON compact, allowlist toàn bộ field native đang dùng; giữ nguyên
segments/visual/picture/anchor/settings/identity/omission/marker. Native chỉ
cần số caption; SRT thật và chữ/các proof vẫn trong kết quả đầy đủ. Không
sửa cache, model hoặc input. Caption-only tạo `caption-executor.json`, giữ
snapshot, source identity, caption path/count và marker/scope.

Đo trực tiếp plan native86 còn lưu:3874932→889562 byte,12208→1212 object;
302 hình/234 voice/695 caption/231 proof trong full output; geometry/voice/
marker/settings bằng nhau tuyệt đối. Đây là giảm payload đo được, chưa
phải chứng minh GC là nguyên nhân treo hoặc thời gian chạy native giảm.

Native ghi `native-progress.jsonl` trước/sau đọc/kiểm plan, snapshot,
QE lookup, setSpeed, move, razor; chỉ append file đã tạo trong cùng thư mục executor. Lỗi trace không
hủy dựng. Panel đọc tối đa2048 byte đuôi, serial mới mới tính là tiến độ;
không làm mới watchdog bằng dòng cũ. Nếu còn chờ một lệnh, thông báo nêu
lệnh và giải thích yêu cầu dừng phải chờ trả về. Không tự retry, bỏ qua
postcheck, timeout bỏ host call, hoặc giả vờ đã hủy lệnh còn chạy.

## Kiểm chứng và phạm vi

[Payload](../../../tests/unit/host-executor-input.test.js) khóa mọi `plan.field`
native và `result.field` caption để field mới bắt buộc được rà; kiểm proof
không gửi, đầu vào không đổi, owned file/wx, stale/partial trace và IO.
[Executor](../../../tests/unit/diagnostic-executor.test.js) kiểm full/compact giống
từng call/report, omission map, cue picture, A2/gap/frame/marker; no-delay
trả quyền trong vòng speed dài, tối đa4 cặp và abort không thêm chỉnh sửa.
Trace direct/staged cùng thứ tự, lỗi trace/file ngoài job không gây write
hoặc hủy, lỗi speed giữ bản ghi entered cuối. [Caption native mock](../../../tests/unit/caption-only-host.test.js)
kiểm compact không đổi import/snapshot/cleanup/review. [UI scheduling](../../../tests/unit/performance-trial-ui.test.js)
giữ no artificial sleep, báo đúng giới hạn, không retry hoặc hủy session khác.

Full suite72 nhóm/150 PS, `-NoWindowsIntegration`;21 Node suite trên package.
Rà Auto edit mặc định/diagnostic, direct/staged baseline/fast/no-delay,
caption-only, DTW/speed/cue/omission, cancellation/pause/recovery và metrics.
Engine/model/timing/cut/omission thresholds không đổi.

## Giới hạn còn mở

Đây là prerelease, **chưa chứng minh hết treo trong Premiere**. Stop nhận ở
ranh giới đợt; không thể ngắt an toàn một lệnh native đơn lẻ đã bị kẹt.
Tác vụ86 đang chạy không thể được vá nóng an toàn. Premiere/helpers phải
đóng thủ công trước cài; không tự Save/Undo/ép đóng hoặc sửa project nguồn.
Native timing/playback/marker và responsiveness/cancel còn chờ nghiệm thu.
