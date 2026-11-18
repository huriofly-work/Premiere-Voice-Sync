# Probe chi phí ghi marker — chuẩn bị 16/11, chạy 17/11/2026

Issue #49. **Đã có hai lượt native trên Premiere 26.2.2**, kết quả lưu tại
`_local/marker-probe/cost-run.json` và `cost-run-101clips.json`.
[Probe/quy trình](../../tools/probes/README.md). Đây là số đo từng lệnh trên
ProjectItem thử, chưa phải nghiệm thu transaction move hoặc benchmark sau #53.

## Bằng chứng gốc

Lượt 2.20.92 Sông Congo: `Cập nhật marker nguồn` 25.192 ms trong một host call,
một owner A2 voice, 19 marker mong muốn; before 24/after 19; readPasses 3/readMs 74;
creates 18, nameWrites 18, commentsWrites 19, endWrites 19, colorWrites 18,
colorReads 103, deletes 23; verificationMs 191. Stage 0,09 s của 2.20.90 trước
chuyển review sang clip voice không phải A/B kiểm soát.

## Điều kiện lượt thử

| Điều kiện | Lượt 1 | Lượt 2 |
| --- | --- | --- |
| Ngày/Premiere | 17/11/2026, 26.2.2 | 17/11/2026, 26.2.2 |
| Sequence theo ghi nhận người chạy | Final t | Final |
| Số clip A2 | 1 | 101 |
| JSON | cost-run.json | cost-run-101clips.json |
| scope/tag | throwaway-project / `[PremiereVoiceSync:marker-write-cost:v1]` | giống lượt 1 |
| documentId/nodeId | cùng định danh trong hai JSON | giống lượt 1 |
| N/sourcePositions | 10 / 11,13,15,17,19,21,23,25,27,29 s | giống lượt 1 |
| Collection trước/sau | 37/37 | 37/37 |

JSON không ghi Node/revision nguồn, thời lượng media, người thao tác hay quan
sát thủ công; không tự điền các mục này. Tên sequence/số clip/Premiere theo
bằng chứng người chạy cung cấp; probe không truy cập sequence. Không chạy lại
Premiere trong đợt sửa #53.

## Thời gian native

Mỗi ô là **count / totalMs / averageMs**. Tag setup, snapshot và cleanup
không nằm trong số đo property; collectionRead là một lượt đọc đầy đủ.

| Thao tác | Final t, 1 clip A2 | Final, 101 clip A2 |
| --- | ---: | ---: |
| createMarker | 10 / 147 / 14,7 | 10 / 451 / 45,1 |
| name | 10 / 107 / 10,7 | 10 / 473 / 47,3 |
| comments | 10 / 144 / 14,4 | 10 / 347 / 34,7 |
| end | 10 / 206 / 20,6 | 10 / 442 / 44,2 |
| setColorByIndex | 10 / 252 / 25,2 | 10 / 426 / 42,6 |
| getColorByIndex | 10 / 65 / 6,5 | 10 / 232 / 23,2 |
| deleteMarker | 10 / 146 / 14,6 | 10 / 354 / 35,4 |
| collectionRead | 1 / 32 / 32 | 1 / 52 / 52 |

Ở lượt 101 clip, name có average cao nhất 47,3 ms, kế đến create 45,1 ms và
end 44,2 ms. Giảm create/delete và tránh ghi field không đổi có cơ sở chi phí;
hai lượt này chưa đủ kết luận mức tăng tốc toàn workflow hay quan hệ nhân quả
giữa số clip và chi phí lệnh.

## Thử di chuyển marker

Hai lượt có cùng kết quả:

| Dạng gán start | before | requested | after | assignmentError / readError | accepted |
| --- | ---: | ---: | ---: | --- | --- |
| Time | 11 | 11,25 | 11 | Illegal Parameter type / null | false |
| seconds | 11 | 11,5 | 11,5 | null / null | true |

Chỉ dùng gán số giây cho #53. Probe dịch start khi end vẫn ở sau start mới;
**chưa chứng minh native chuyển start vượt end hiện tại**. Mã #53 ghi end
trước khi sang phải, start trước khi sang trái; mock kiểm start <= end sau
từng ghi, nghiệm thu transaction/compensation trên Premiere vẫn pending.

## Dọn và đối chiếu

Cả hai JSON có `ok=true`, `deletionVerified=true`, `cleanup.verified=true`,
beforeCount 37/afterCount 37. Cleanup finally: attempted 0/totalMs 0/errors[] vì
các marker thử đã được xóa trong pha đo delete. Verification xác nhận collection
giữ GUID/start/end/name/comments/type/color như snapshot trước.

JSON không ghi quan sát thủ công hoặc việc gỡ debug tạm; các phần đó chưa có
bằng chứng. Quy trình không Save/Undo và probe không truy cập sequence.
