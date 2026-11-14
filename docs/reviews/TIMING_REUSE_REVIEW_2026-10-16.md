# Phạm vi dùng chung cơ chế timing 2.20.43

## Quyết định sau phản hồi người dùng

Người dùng xác nhận cho phép điểm cắt dựng thay đổi để hưởng lợi từ timing chính xác hơn. Đề xuất giữ nguyên điểm cắt trong giai đoạn caption bên dưới đã được thay thế. Bản 2.20.45 dùng chung bước đo âm học, cập nhật cả caption và Start/End/WordTimings của cue có đủ bằng chứng trước planner. Tiêu chí đối chiếu là giữ đủ nguồn/voice, đúng thứ tự và giới hạn frame, không phải khớp điểm cắt của 2.20.44. Không thêm một luồng bằng chứng cũ chỉ để khóa kết quả dựng. Vùng chỉ có timing ước lượng vẫn được phân biệt với mốc đã xác minh theo từ.

Phần dưới là ghi nhận lần rà soát ban đầu, trước khi người dùng điều chỉnh phạm vi. Trạng thái triển khai/kiểm chứng mới xem `NOTIFICATIONS_2.20.45.md`.

Rà soát ngày 16/10/2026, checkout và panel đang cài 2.20.44. Bản 2.20.44 chỉ thêm phép đo xuất audio, giữ thuật toán subtitle của 2.20.43. Người dùng đã kiểm sơ luồng Chỉ tạo subtitle và xác nhận chính xác hơn rất nhiều, gần như không tìm thấy lỗi trong phần đã xem. Đây là xác nhận trên phần đã kiểm, chưa phải đo sai số của mọi từ trên toàn bài hoặc nghiệm thu Auto edit.

Lượt rà soát này chỉ đọc mã và ghi tài liệu. Không sửa engine, panel, thiết lập hay project; không đóng gói/cài bản mới hoặc điều khiển Premiere.

## Kết luận theo phạm vi

| Phần | Hiện tại | Khả năng áp dụng |
| --- | --- | --- |
| Caption trong Auto edit | `Prepare-PvsAutoCaptionTimings` dùng DTW cũ, không có envelope RMS; một lỗi trong chapter có thể bỏ timing caption DTW của chapter đó | Ưu tiên đầu tiên: retry theo cửa sổ, giữ từ tốt, tìm đáy gần từ đứng trước, báo vùng ước lượng |
| Retry mép caption và caption quanh số trong Auto edit | Có nhận diện cửa sổ nhưng còn parser/timing cũ | Dùng cùng lõi âm học, giữ nguyên chữ SRT và phân biệt timing theo từ với ước lượng |
| Chỉ tạo subtitle: nhận diện chính, phục hồi và bổ sung | Đã gọi cơ chế mới qua `Convert-CaptionRecognitionWithTiming` | Duy trì cùng cơ chế; tránh viết thêm nhánh riêng lệch chính sách |
| Phục hồi cue thiếu để dựng, mốc `Start/End` và `WordTimings` chính | Được dùng để nhóm câu, chia voice và tính kế hoạch dựng | Có thể nâng cấp sau, nhưng là thay đổi dựng; kiểm A/B và bảo toàn nguồn/voice riêng |
| Điểm cắt voice giữa câu | Đang yêu cầu khoảng nghỉ, hai phía có bằng chứng lời nói và biên an toàn | Dùng timing tốt hơn để xác định ứng viên; một đáy RMS ngắn chưa đủ để cho phép cắt |
| Tính speed/gộp video, executor, xuất WAV/Encoding, thông báo | Không phải bộ đo ranh giới từ | Không thay trực tiếp bằng RMS/DTW; nhận lợi ích từ dữ liệu tốt hơn ở phía trước nếu có |

## Liên kết cần tách trước khi triển khai

`run-alignment.ps1:217` gọi `Prepare-PvsAutoCaptionTimings` trong `CaptionTiming.ps1:350`. Hàm này gắn `CaptionWordTimings` vào cue. Các trường `Start/End/WordTimings` chính được giữ, nhưng như vậy chưa đủ để kết luận điểm cắt dựng không đổi.

`build-dtw-trial-plan.ps1:39` đưa `alignment.cues` vào `Get-PvsDtwBoundaryTrial`. Trong `DtwEditTrial.ps1:19–20` và `54`, bộ kiểm bằng chứng và chọn điểm cắt đọc trực tiếp `CaptionTimingRevision`/`CaptionWordTimings`. Bản mặc định Auto edit cũng chạy bước này. Thay overlay caption có thể đổi ứng viên cắt và kế hoạch retime dù không sửa mốc cue chính.

Vì vậy cần tách dữ liệu phục vụ hiển thị caption và chứng cứ phục vụ cắt dựng trước khi thay overlay. Hai phần có thể dùng chung bước đo âm học nhưng phải có chính sách chấp nhận riêng. Không coi timestamp cấp câu hoặc cue nội suy là chứng cứ cắt chính xác theo từ.

## Trình tự triển khai đề xuất

1. Giữ baseline 2.20.44. Tách phần đo PCM/RMS, kiểm DTW theo cửa sổ và kết quả chất lượng thành lõi dùng chung; giữ adapter subtitle và đầu ra đang được người dùng xác nhận. Không đổi ngưỡng/thuật toán trong bước tách.
2. Tách luồng chứng cứ cắt hiện tại khỏi overlay caption. Nâng caption Auto edit, retry mép và caption quanh số bằng lõi mới. Mốc dựng chính, danh sách điểm cắt, voice, speed, nhóm video và toàn bộ thời lượng phải khớp baseline trong giai đoạn này.
3. Chạy đối chiếu ngoại tuyến trên các chapter/media thật, sau đó kiểm trong Premiere phần caption Auto edit. Tinh chỉnh âm học phải thực hiện trên PCM nguồn trước khi quy đổi speed, offset chapter và frame; không nhân/chia tốc độ hai lần.
4. Nâng chứng cứ phục vụ cắt/ghép dựng trong một bước riêng. Giữ yêu cầu nghỉ đủ dài, biên an toàn, thứ tự, chapter, độ khớp chữ và bảo toàn mọi frame nguồn/voice. So sánh danh sách điểm cắt và đoạn retime trước/sau; không tự hạ các điều kiện chỉ vì tìm được đáy sóng.

## Tiêu chí kiểm chứng

- Luồng Chỉ tạo subtitle: cùng dữ liệu nhận diện và audio phải cho kết quả timing/chữ tương đương baseline được xác nhận; không đưa phần nội suy cue dựng sang subtitle.
- Auto edit giai đoạn caption: caption có thể đổi timing/chia dòng, nhưng các đoạn dựng và mốc voice/video phải khớp baseline. Cần kiểm cả bước chọn điểm cắt DTW và gộp speed, không chỉ planner đầu tiên.
- Có case anchor trùng/thiếu, cửa sổ retry thất bại, số thập phân, từ lặp, chapter dài, vùng im lặng, lời ngoài SRT và lỗi native. Chỉ lỗi timing được fallback cục bộ; lỗi kỹ thuật không bị che thành timing cũ.
- Kiểm nhiều chapter có offset, speed voice khác 100%, 30 và 29,97 fps, ranh giới sát mép clip và ánh xạ caption sau khi voice được chuyển chỗ. Giữ guard từ chối media In chưa hỗ trợ.
- Vùng ước lượng phải có provenance và vị trí rõ ràng trong báo cáo. Không gắn nhãn DTW đã xác minh hoặc dùng để mở thêm điểm cắt.
- Cache tiếp tục dựa vào audio/model/runtime/tham số nhận diện; không lưu kế hoạch timeline làm kết quả dùng lại. Không cần xóa cache/model người dùng để áp dụng bộ tính timing mới.
- Fixture và kiểm ngoại tuyến không thay nghiệm thu cắt/retime, caption, Play và Save trong Premiere. Xác nhận của người dùng ở luồng subtitle hiện tại không tự trở thành nghiệm thu Auto edit.

Các vị trí liên quan khác: `run-alignment.ps1:179,216` (phục hồi/caption số), `build-sentence-plan.ps1:48,211` (chọn khoảng nghỉ), `345–399` (tách và ánh xạ caption theo voice), `CaptionTiming.ps1:402–416` (retry mép caption), `ReferenceAlignment.ps1` (phục hồi và nội suy), `SpeedMergeTrial.ps1` (bảo toàn kế hoạch khi gộp hình).
