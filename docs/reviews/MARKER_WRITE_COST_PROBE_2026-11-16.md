# Probe chi phí ghi marker — 16/11/2026

Issue #49. **CHƯA CHẠY NATIVE — pending.** Không suy ra native capability hay
tỷ lệ tăng tốc từ mock. [Probe/quy trình](../../tools/probes/README.md).

## Bằng chứng gốc

Lượt 2.20.92 ngày 16/11: `Cập nhật marker nguồn` 25.192 ms trong một host call,
Premiere không phản hồi. Một owner A2 voice, 19 marker mong muốn; before 24,
after 19; readPasses 3/readMs 74; creates 18, nameWrites 18, commentsWrites 19,
endWrites 19, colorWrites 18, colorReads 103, deletes 23; verificationMs 191.
2.20.90 trước khi marker review chuyển sang clip voice: 0,09 s. Đây không phải
A/B kiểm soát; chưa biết thao tác nào chiếm phần lớn chi phí.

## Điều kiện lượt thử

| Điều kiện | Giá trị / bằng chứng |
| --- | --- |
| Ngày chạy / người thao tác / quyền native | Pending |
| Premiere / Node / revision nguồn | Pending |
| Project bỏ đi, media thử riêng, không dùng nguồn thật | Pending |
| documentId / nodeId / tag / scope | Pending |
| N (mặc định 10), sourcePositions, độ dài media thử | Pending |
| Snapshot marker trước / log JSON sau | Pending |

## Thời gian native

Ghi count/totalMs/averageMs từ metrics. Tag setup, snapshot và cleanup không
nằm trong số đo property; collectionRead là một lượt đọc đầy đủ.

| Thao tác | count | totalMs | averageMs |
| --- | ---: | ---: | ---: |
| createMarker | Pending | Pending | Pending |
| name | Pending | Pending | Pending |
| comments | Pending | Pending | Pending |
| end | Pending | Pending | Pending |
| setColorByIndex | Pending | Pending | Pending |
| getColorByIndex | Pending | Pending | Pending |
| deleteMarker | Pending | Pending | Pending |
| collectionRead | Pending | Pending | Pending |

## Thử di chuyển marker

| Dạng gán start | before | requested | after | assignmentError / readError | accepted |
| --- | ---: | ---: | ---: | --- | --- |
| Time | Pending | Pending | Pending | Pending | Pending |
| seconds | Pending | Pending | Pending | Pending | Pending |

Không coi không ném lỗi là đã di chuyển. Ghi cả trường hợp mutate rồi throw,
bỏ qua gán hoặc không đọc lại được. Kết quả chỉ áp dụng cho bản Premiere và
ProjectItem đã đo; host chưa dùng khả năng này.

## Dọn và đối chiếu

- `ok`, `deletionVerified`, `cleanup.verified`, beforeCount/afterCount: Pending.
- Cleanup attempted/totalMs/errors, marker không tag nếu có lỗi setup: Pending.
- Collection còn đúng GUID/start/end/name/comments/type/color như trước: Pending.
- Quan sát thủ công, không truy cập sequence/Save/Undo, gỡ debug tạm: Pending.
- Kết luận thao tác tốn thời gian nhất và hướng tối ưu có bằng chứng: Pending.
