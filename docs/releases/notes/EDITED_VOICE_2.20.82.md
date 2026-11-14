# Auto edit nhiều file voice và phục hồi từng câu — 2.20.82

## Nguyên nhân và hành vi

Lượt Alien 02 ngày 2026-10-21, bản 81, có319cue tiếng Việt/3file voice.
Replay metadata project đã lưu với cache sao chép tái hiện đúng159cue
unresolved,149hit/0miss. Source và bản cài của bốn file căn lời/phục hồi
trùng hash. Không coi159cue là159câu đã nghe xác nhận bị mất.

Primary scale timestamp nhưng chưa giới hạn theo mép clip trước resolver;
clamp cue sau resolver quá muộn. Hai từ cuối vượt69,162/142,424ms làm
manual fallback từ chối. Retry đã giới hạn cửa sổ. Helper mới dùng chung
cho primary/CUDA→CPU/retry, sao chép word object, giữ raw/cache/surface và
không nâng timing. NaN/Infinity/âm/đảo span vẫn lỗi. Từ nằm hoàn toàn ngoài
clip không được phục hồi vào phần voice đã chọn.

Recovery trước đây all-or-nothing: một cue không đạt làm bỏ các cue đã
qua kiểm. Nay giữ độc lập candidate đạt toàn bộ identity/coverage/unique/
neighbor/bounds/chapter; Repaired chỉ true khi toàn bộ pending đã đạt.
Partial vẫn qua resolver nghiêm ngặt. Manual fallback kiểm lại candidate
theo Words hiện tại trước khi dùng chữ; không cấp quyền omission hoặc DTW.

Manual fallback cũ từ chối mọi vùng nhiều chapter và gộp dây chuyền qua
neo dùng chung. Nay phân chapter chỉ khi câu neo nguyên vẹn, duy nhất,
đúng thứ tự sở hữu từ quan sát cuối chapter trước; đuôi chưa chắc vẫn dừng.
Nhóm quá lớn được phân hoạch tại cuối neo nguyên câu, sở hữu neo đúng một
lần, giữ liên tục hình/voice. Neo và phần chia không thành word DTW mới.
Giữ nguyên giới hạn30s/40cue/800từ mỗi block. Lời thêm trước/sau neo ở mép
chapter được giữ trong caption review, không bị loại vì ngoài span neo.

## Hồi quy và giới hạn

- [Partition](../../../tests/unit/Test-AutoEditPartition.ps1): primary bounds,
  raw bất biến, neo một lần, chapter có proof/đuôi unknown bị từ chối,
  30s không đổi, lời thêm hai mép, SRT cuối và speed conservation qua planner thật.
- [Partial recovery](../../../tests/unit/Test-AutoEditPartialRecovery.ps1): cùng
  job có một cue số phục hồi được và một cue thiếu đuôi; giữ riêng cue tốt,
  không dựng lại đuôi thiếu hoặc cấp omission.
- Cả hai ca thất bại trên hàm của81 trước sửa, đạt sau sửa. Giữ nguyên các
  ca [78](../../../tests/unit/Test-AutoEditReferenceRecovery.ps1) và
  [79](../../../tests/unit/Test-AutoEditManualReview.ps1), không sửa kỳ vọng lịch sử.
- Rà caption-only/shared parser, caption DTW primary/retry và acoustic:
  caption-only/acoustic đã giới hạn theo PCM/window trước khi scale;
  không dùng helper Edit để đổi contract hoặc nâng timing của chúng.
  Legacy planner/DTW/speed/marker tiếp tục dùng metadata manual/recovery cũ.

**Alien chưa hoàn tất.** Replay mới149hit/0miss,157cue unresolved; hai từ
vượt mép clip không còn chặn. Vùng đầu không thể chia là35–44,
146,927273–188,181818s voice (41,254545s), chưa có neo đủ chắc bên trong.
Thông báo giữ EDITED_REFERENCE_UNRESOLVED và thêm reason/manual-window-limit,
cueIndices/chapter/start/end/maximumSeconds. Không tăng giới hạn để ép dựng,
không xuất kế hoạch giả thành công hoặc gọi đây là ASR nâng cấp.

Replay hòn đảo qua alignment/planner/DTW/speed hoàn tất; giữ30/30→66caption, SRT giống byte81; giữ27gap/1review và proof cắt voice34,4s. Reference cố ý sai vẫn5khối/65caption, raw102 được giữ, không phục hồi chữ sai. Lịch sử giữ27Short/199cue có nhãn chữ. Đạt68nhóm/145PS và20bộNode trong gói;73payload/74ZIP entries khớp nguồn. Metadata phát hành lưu hash/số đo. Sandbox chặn
junction của Test-Security ở lượt đầu; chạy lại đúng quyền, không đổi runtime
để né môi trường. Dữ liệu chẩn đoán/caches/media nằm ngoài Git.

Các giới hạn còn lại của Alien là pending; cần thêm bằng chứng nhận diện/
neo độc lập để chia vùng, không dùng caption identity thay bằng chứng cắt.
Native Premiere import, razor, retime, playback, timing, marker và Save
chưa được nghiệm thu. Không tự merge PR hoặc quảng bá stable.
