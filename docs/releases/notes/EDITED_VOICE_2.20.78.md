# Auto edit phục hồi chữ SRT trước chốt omission — 2.20.78

## Nguyên nhân và phạm vi

Project hòn đảo có 30 cue SRT. Whisper Small nhận câu 11 “Phần lớn trong số đó
là những loài có một không hai.” thành “…có 102.”: 12 từ tham chiếu chỉ có 10
mốc. `run-alignment.ps1` chuyển mọi cue qua resolver voice đã cắt, yêu cầu
khớp trọn chữ. Lỗi nhận diện ở tên riêng/chính tả và cue ngắn dẫn tới thông
báo `EDITED_REFERENCE_UNRESOLVED:cue-1,5,6,7,10,11,12,18,20,21,26,27`.

Đã tái hiện nguyên danh sách bằng primary/retry cache giữ hash và metadata
clip từ project đã lưu: voice 110%, mediaIn 0, timeline 0–103,266667 s. Thử
nhận diện mới riêng câu 11, không prompt, vẫn trả 102. Không gọi danh sách lỗi
là bằng chứng voice đã thiếu 12 câu, hoặc SRT là lời chuẩn đã nghe xác nhận.

## Bản sửa

- Trước resolver nghiêm ngặt, gọi `Select-PvsSubtitleReference` dùng chung
  với subtitle: projection, identity, ngữ cảnh và retry. Giữ nguyên các câu
  Auto edit đã căn đủ; chỉ thay cue chưa hoàn tất khi tất cả cue lỗi qua kiểm.
- Identity của subtitle chỉ là điều kiện nhận chữ. Auto edit kiểm thêm toàn
  bộ span quan sát, thứ tự, chapter, bounds, hai cue kề, cue trùng và đủ lời.
  Chữ bị thiếu ở đầu/giữa/cuối, lời thêm hoặc số khác không được bỏ qua.
- Một token chữ số có thể tương ứng một chuỗi tên chữ số tiếng Việt. Chỉ
  nhận khi toàn bộ ngữ cảnh ngoài chuỗi khớp chính xác, đủ ít nhất 4 từ, toàn
  bộ chữ số đúng theo thứ tự, một field duy nhất và identity cũ vẫn đạt.
  Đây là đối chiếu biểu diễn chữ, không suy nghĩa số hoặc coi 102 là
  lời chuẩn. Không hardcode câu, project, mốc thời gian hay 102.
- Giữ một span quan sát cho cụm viết gộp, đánh dấu estimated; không chia span
  thành ba timestamp hoặc nâng thành DTW. Cue phục hồi có
  `EditBoundaryReviewRequired`: planner gộp hai mép câu, acoustic refinement
  và DTW trial không tạo lại điểm cắt tại đó. Caption vẫn giữ nguyên chữ SRT.
- Metadata `autoEditReferenceRecoveredCueIndices`/`autoEditReferenceRecovery`
  nêu cue, kiểu và span. Marker dùng ánh xạ cue sang mọi caption cuối đã chia.
- Đường phục hồi mới không trả omission/source map. Cue thực sự thiếu hoặc
  chưa đủ căn cứ vẫn qua `Resolve-PvsEditedReference` và chốt cũ. Không đổi
  điều kiện của `New-PvsEditedSourceMap`, ngưỡng identity hay model Small.

Đây là tích hợp phục hồi có giới hạn; không tuyên bố mọi fallback cho caption
đều được phép dùng để cắt hình. Việc không tìm đủ cue trong subtitle selection
không làm mất các cue Auto edit đã căn được từ trước.

## Kiểm chứng

`tests/unit/Test-AutoEditReferenceRecovery.ps1` khóa 102 và 4206, SRT cuối qua
planner thật, sparse timing/offset/raw bất biến, prefix/suffix/interior bị
cắt, lời thêm/số sai, chapter/NaN/overlap/bounds/index, ngôn ngữ khác và lỗi
native. Phát hiện mảng bản sao dùng lại array gốc trên Windows PowerShell 5;
dùng Clone để sửa candidate không đổi baseline khi recovery bị từ chối.
Fixture silence và LegacyFinder chủ động mời cắt vẫn bị chặn ở cả hai mép.
Test marker kiểm từng caption cuối, không chỉ tọa độ cue trước dựng.

Lượt offline trên media thật chạy entrypoint không sửa của source 78:
`run-alignment` → planner → DTW trial → speed merge. Primary/retry có thể dùng
cache theo nội dung; thư mục cache/backend riêng trong workspace. Không đọc/
ghi timeline Premiere hoặc thay cache/model/job của người dùng.

Đã kiểm caption cuối qua cả speed merge và file SRT thật: **30/30 cue nguồn,
66 caption**, đúng nguyên dấu/chữ/số/dấu câu qua các lần chia; interval dương
không chồng. Không có source omission; toàn bộ frame hình được phân hoạch,
voice giữ nguyên qua speed merge. Nhóm chứa cue 10–12 giữ liền quanh câu 11;
không thêm điểm cắt DTW. SRT cuối SHA256
`266205D8D6FD43129418FB5E9A04A786294EAF3A23D4D5E65382EAE0532823F4`.
Project/SRT/MP3 gốc giữ nguyên hash so với lúc chẩn đoán.

Hồi quy đạt **64 nhóm / 140 script PowerShell**, bỏ qua 6 nhóm Windows
integration theo runner. Sandbox chặn junction ở lượt đầu; toàn suite đạt
khi chạy quyền phù hợp với TEMP/TMP/cache riêng, không đổi logic bảo mật.
Replay cache lịch sử giữ đúng 27 cue Short và 199 cue gồm nhãn A/C.
Full caption entrypoint Small trên audio Nam Cực dựng lại giữ 255/255 cue,
468 caption, **SRT giống từng byte 2.20.77**; 113 ASR cache hit, 0 miss.

Một ca có đồng thời omission thật và phục hồi chữ chưa đủ bằng chứng có
thể vẫn dừng ở resolver cũ. Không dùng thành công của ca này để bỏ chốt đó.
Package/install và GitHub được ghi riêng trong metadata phát hành.
Native Premiere import/razor/retime/playback/timing/marker và Save vẫn pending.
