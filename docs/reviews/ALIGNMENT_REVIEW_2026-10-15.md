# Rà soát căn SRT với voice — 2.20.42

## Quyết định

Kế thừa cơ chế đã chạy ổn của Auto edit ở phần chuẩn hóa, gán timestamp và phục hồi cue thiếu. Giữ hai chính sách xử lý phần không khớp: Auto edit dựng theo SRT; Chỉ tạo subtitle bám audio đang có. Nội suy cue SRT chỉ được gọi trong planner Auto edit, làm phương án cuối sau căn từ và phục hồi bằng ASR. Không mở rộng nội suy sang subtitle.

Nội suy cue không xác nhận được câu đó đã được đọc: nó phân chia một khoảng thời gian theo độ dài cue SRT gốc. Vì vậy phù hợp hơn với việc giữ cấu trúc kịch bản/hình của Auto edit. Nó vẫn là timing ước lượng, không phải phép căn chính xác. Ở subtitle, video/audio giữ nguyên; chèn một câu SRT chưa được xác nhận có thể hiện chữ không được đọc, che mất lời khác hoặc lời đăng ký kênh.

## Dùng chung và hoạt động riêng

| Công đoạn | Dùng chung | Chính sách riêng |
| --- | --- | --- |
| Chuẩn hóa chữ | `ReferenceAlignment.ps1`: chữ thường, Unicode Form C, tách chữ/số, giữ dấu tiếng Việt | Subtitle có tách ký tự cho ngôn ngữ CJK |
| Đọc ASR | Cùng parser và cấu trúc Words | Edit giữ cách phân bố legacy tối thiểu 20 ms; Subtitle giới hạn trong đoạn audio, bỏ metadata và đoạn có thời lượng bằng 0 |
| Lập danh sách từ SRT | Cùng layout từ, vị trí từ trong cue và ranh giới cue | Subtitle giữ chỉ số SRT gốc khi chỉ lấy đoạn giữa |
| Tìm mapping | Cùng nguyên tắc khớp theo thứ tự, chi phí exact/substitution/deletion/insertion và thứ tự xử lý hòa | Auto edit căn toàn bài bằng mapper hiện tại; Subtitle cần chọn scope nằm trong SRT dài, dùng semiglobal/checkpoint có bảo vệ bộ nhớ và kiểm các phạm vi ứng viên |
| Mapping thành cue | Cùng `Convert-PvsReferenceMappingToCues`: chữ SRT, timing từ ASR, offset chapter, confidence, cue thiếu | Subtitle xác nhận thêm coverage, scope, timing và biến thể chính tả ngắn có neo |
| Cue bị thiếu hoàn toàn | Cùng `Repair-PvsMissingCueWordTimings`: nhận diện lại vùng nhỏ có neo mạnh; chỉ nhận khi đủ coverage, confidence và timing | Subtitle chuyển phần chưa khôi phục được sang ASR bổ sung; Auto edit có thể dùng nội suy planner sau đó |
| Timestamp phục hồi | Cùng `Test-PvsReferenceCueTiming`: hữu hạn, thời lượng dương, thứ tự từ, giới hạn nguồn và chapter | Subtitle cũng dùng kiểm tra này trước khi chấp nhận cue tham chiếu, kể cả cue khớp chữ cao |
| Phần lời khác/ngoài SRT | Không ép dùng cùng chính sách | Subtitle nhận diện và ghép bổ sung, gồm intro/outro/CTA; không đưa chính sách thêm chữ ASR vào kế hoạch dựng Auto edit |
| Nội suy cue | Hàm còn ở lõi để giữ adapter hiện tại | Chỉ planner Auto edit gọi; Subtitle không có lối gọi |
| Thay đổi timeline | Không dùng chung planner/executor | Auto edit dựng hình/voice; Subtitle xuất SRT/caption trên audio đã có |

Hai bộ tìm mapping không bị hợp nhất cưỡng ép: căn toàn bài và tìm một đoạn trong tài liệu dài có điều kiện biên khác nhau. Thay mapper Auto edit chỉ để giảm dòng mã sẽ tăng rủi ro thay kết quả ở đoạn lặp hoặc từ thừa/thiếu. Giữ recurrence/mapper đang tốt và kiểm đối chiếu bằng oracle; dùng chung phần chiếu kết quả về cue và bước phục hồi có cùng ý nghĩa.

## Luồng khi thiếu hoặc không khớp

Auto edit: ASR → chuẩn hóa → mapping toàn bài → gán cue/từ → nhận diện lại nhóm thiếu có neo → tinh chỉnh timing caption → planner nội suy cue còn thiếu → dựng. Bước nội suy giữ nguyên cách chia theo thời lượng SRT gốc và lượng tử theo frame; không vượt chapter hoặc tạo khoảng không đủ frame. Cue nội suy có confidence 0 và đánh dấu `TimingRecovered`, không tạo word timing giả.

Subtitle: xuất audio timeline theo phạm vi chọn → ASR → tìm scope SRT theo từng nguồn → gán cue/từ bằng lõi chung → phục hồi nhóm thiếu bằng cùng cơ chế Auto edit → xác nhận cue → ASR bổ sung vào các khoảng chưa được xác nhận có dấu hiệu lời nói hoặc có cue thiếu → ghép, đánh số lại, tinh chỉnh và xuất SRT/caption. Chữ SRT đã xác nhận được giữ; ASR bổ sung không dùng chữ SRT làm prompt. Nếu một scope không đủ an toàn thì nhận diện nguồn đó thay vì gán tùy tiện chữ SRT.

Phải phân biệt nội suy **cue SRT chưa xác nhận** với chia timing cho các **từ trong đoạn ASR đã nhận diện**. Khi ASR chỉ trả timestamp cấp câu, parser vẫn chia thời gian của câu cho các từ để mapping và tách caption. Đây là ước lượng bên trong đoạn có bằng chứng lời nói, không dùng timestamp SRT cũ và không chứng minh chính xác từng ranh giới từ. Chất lượng cuối cần nghe/Play trên media thật.

## Sửa sau rà soát

1. Bỏ fallback toàn bộ job khi chỉ một nguồn không khớp. `AllowUnmatchedRanges` cho phép ghi riêng lý do mismatch, partial cue, ambiguous, order hoặc no speech; giữ SRT hợp lệ từ nguồn khác. Caller strict vẫn giữ lỗi như trước. Lỗi bộ nhớ/compiler/native không bị chuyển thành lỗi chữ không khớp.
2. Nguồn không có từ ở lượt đầu được đánh dấu để thử lại, kể cả khi toàn bộ lượt đầu rỗng và đã cung cấp SRT. Nếu lượt bổ sung vẫn rỗng, ghi vùng trống; không dùng nội suy để chèn chữ. Khi không có caption nào, workflow vẫn báo không tạo được caption.
3. Bổ sung kiểm timing độc lập với độ khớp chữ. NaN, Infinity, thời lượng bằng 0, từ chồng/đảo thứ tự hoặc vượt nguồn không được coi là cue tham chiếu tốt. Kiểm hữu hạn cũng áp dụng cho phục hồi chung, giữ nguyên đầu ra hợp lệ của Auto edit.
4. Log kết quả có `referenceFallbackRanges` để truy nguồn vì sao một vùng phải dùng ASR. Giữ `referenceRecoveredCueIndices`, các vùng đã bổ sung và vùng nhận diện rỗng.

Không đổi ngưỡng căn toàn bài, thuật toán nội suy, điểm cắt, planner, nhận diện chính hoặc executor Auto edit. Không thêm cache cửa sổ riêng trong lượt này: ASR đã có cache audio; chưa có đo đạc cho thấy cần thêm một lớp cache có trạng thái.

## Kiểm chứng và giới hạn

`Test-SharedReferenceAlignment.ps1` so toàn bộ đối tượng cue/từ với snapshot thuật toán Auto edit 2.20.40 trên 100 ca có seed; so parser, projection chung và phục hồi chung. Nội suy được so ở 30 và 29,97 fps. Kiểm A/B planner so toàn bộ plan và SRT của 10 ca với gói 2.20.40, chỉ chuẩn hóa `createdAt` và đường dẫn fixture.

`Test-SubtitleRangeFallback.ps1` kiểm giữ SRT ở hai nguồn tốt bao quanh một nguồn sai; vùng rỗng và toàn bộ ASR rỗng; strict caller; lặp/đảo thứ tự; timing NaN/Infinity/zero/overlap/outside; phục hồi chung từ chối timestamp vô hạn. Các nhóm cũ vẫn kiểm SRT dài, CTA, phần khác ở giữa, phục hồi thất bại và cấm nội suy subtitle.

Đây là chứng cứ tự động với fixture, không phải nghiệm thu chất lượng ASR hoặc caption trên project người dùng. Chưa nhận diện mới media người dùng, chưa mở/đóng hoặc điều khiển Premiere, chưa xác nhận Play/Save/import trên project thật. SRT thiếu hoàn toàn ở một vùng không có tín hiệu ASR/cue thiếu vẫn phụ thuộc chất lượng nhận diện đầu vào; rà soát mã không thể chứng minh đã tìm đủ mọi lời nói.
