# Vùng khó cần sửa tay trong Auto edit — 2.20.79

## Vấn đề và hành vi

2.20.78 phục hồi được chữ SRT có đủ bằng chứng (kể cả cách viết gộp), nhưng
resolver vẫn dừng toàn tác vụ nếu chưa phân biệt được ASR sai với voice đã
cắt giữa câu. Việc cố khớp toàn bộ SRT hoặc coi mọi câu thiếu là omission
đều có thể dựng sai. 2.20.79 cho phép giữ vùng khó để sửa tay theo
[chính sách nghiệm thu](../../ASR_ACCEPTANCE_POLICY.md).

Chỉ sau khi resolver nghiêm ngặt trả unresolved, `New-PvsAutoEditManualReview`
xác định các vùng bằng những câu neo duy nhất, đúng thứ tự, khớp nguyên chuỗi
ít nhất bốn từ. Cần tối thiểu hai neo trong job; đầu/cuối có thể dùng mép
clip khi chỉ có một chapter. Không nối vùng bất định qua hai chapter.
Mỗi khối tối đa 30 giây voice, 40 cue và 800 từ quan sát. Không đủ neo,
bounds không hợp lệ, lời đảo thứ tự hoặc vượt giới hạn vẫn dừng.

Mỗi vùng trở thành một đơn vị dựng với `ManualEditBlock` và
`EditBoundaryReviewRequired`. Toàn bộ khoảng hình nguồn và voice được giữ;
hình vẫn được retime theo voice. Không tạo omission/source map cho job dùng
fallback này. Những omission có thể có trong báo cáo cũ cũng được giữ lại
để rà; chỉ job đã được resolver chứng minh hoàn toàn mới dùng đường bỏ hình.
Planner, acoustic refinement và DTW trial không tạo điểm cắt bên trong khối.
Speed merge có thể gộp hình bên ngoài nhưng không chia nhỏ khối.

## Chữ và timing độc lập với quyền cắt

Trong khối, chữ SRT chỉ giữ khi có bằng chứng identity và coverage riêng.
Phần khác dùng chữ ASR gốc, giữ hoa/dấu câu/số viết gộp qua metadata surface
chỉ được bật ở Auto edit. Không chèn câu chưa nghe được hoặc khôi phục đuôi
câu đã bị cắt. Chữ ASR có thể vẫn sai: đó là việc người dùng cần sửa tay.

Caption chia theo các cell hiển thị có khoảng voice quan sát được; điểm chia
hiển thị trong cell là ước lượng. Không tạo `WordTimings`, không bật
`VoiceBoundaryAligned`/`IndependentSpeechEdges` hoặc nâng thành DTW.
`manualReviewBlocks` ghi đầy đủ cue nguồn, cue giữ được, cue chưa xác minh,
cell chữ và trạng thái `manual-review-pending`. Không gọi đây là hoàn tất
nghiệm thu chữ. Marker được ánh xạ sang mọi caption cuối sau dựng; thông báo
hoàn tất ghi rõ số vùng cần sửa tay. Không đổi chính sách thông báo hệ thống.

## Các đường đã kiểm

| Đường | Invariant |
|---|---|
| Auto edit phục hồi đủ lời 78 | Giữ nguyên kết quả, không chuyển sang manual nếu recovery đã đủ |
| Resolver omission | Resolved vẫn dùng chốt cũ; unresolved không được cấp omission mới |
| Legacy planner, acoustic/DTW trial | Giữ khối hình/voice; timing caption không được thành quyền cắt |
| Speed merge và marker | Bảo toàn metadata/text; marker theo tọa độ caption cuối |
| Subtitle-only/shared recognition | Surface opt-in; lời và timing mặc định không thay đổi |

## Bằng chứng và giới hạn

`Test-AutoEditManualReview.ps1` tái hiện tên lạ/số viết gộp, mất đuôi câu,
omission đã chứng minh, bounds/NaN/order/chapter/language, input bất biến và
raw token một từ. Chạy planner thực với silence detector fixture cố mời cắt,
kiểm file SRT cuối, DTW, speed merge, và chủ động làm hỏng hình/voice/chữ/
timing/omission/metadata để yêu cầu từ chối. Marker suite kiểm từng caption
cuối và thông báo việc rà tay còn lại.

Replay offline đủ bốn entrypoint trên MP3 đảo và metadata clip đã lưu từ
lượt chẩn đoán: SRT gốc vẫn giữ **30/30 → 66 caption**, SRT cùng SHA-256
`266205D8D6FD43129418FB5E9A04A786294EAF3A23D4D5E65382EAE0532823F4`
với 78. Không omission, không điểm cắt quanh câu phục hồi 11.

Ca thứ hai dùng chính media đó nhưng **bản sao SRT cố ý đổi “một không hai”
thành “một không ba”**, không sửa file người dùng. Pipeline hoàn tất với
**5 khối rà tay / 65 caption**, pending chữ ở cue 7,11,20. Caption giữ raw
“có 102”, không chèn chữ sai “một không ba”; các cell SRT đã xác minh và
các cue ngoài khối giữ nguyên. Kiểm toàn bộ file SRT/caption cuối, khoảng
dương không chồng, mọi frame hình nguồn và voice, không điểm cắt trong khối.
Đây là phép thử cơ chế với reference cố ý sai, không là nhãn đúng nội dung
audio hoặc bằng chứng ASR đã tốt hơn.

File project trên máy đã thay đổi sau chẩn đoán 78; replay dùng metadata
cũ, không gọi đó là timeline hiện tại. MP3/SRT gốc giữ hash chẩn đoán; project
được chụp hash mới để kiểm đọc. Không Save/Undo hay gọi host Premiere.
Hồi quy đạt **65 nhóm / 142 script PowerShell**; bỏ qua sáu nhóm Windows
integration theo runner. Replay lịch sử giữ27 cue Short và199 cue A/C.
Full Small Nam Cực giữ255/255→468 caption, cùng byte78,113 ASR cache hit/0 miss.
Package/install được ghi riêng trong metadata phát hành.
Native Premiere import/razor/retime/playback/timing/marker/Save còn pending.
