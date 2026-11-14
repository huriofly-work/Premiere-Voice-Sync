# 2.20.76 — giữ outro ASR ban đầu khi lượt bổ sung mất lời

Đã xác nhận lỗi đường xử lý, không phải Large-v3 luôn không nghe được voice
ngoài SRT. Cùng lượt toàn engine 2.20.75, raw recognition ban đầu có lời cảm
ơn; sau căn acoustic còn đủ 75 từ có quality DTW, vẫn còn ngay trước bước
bổ sung. Nhưng nhận diện lại cửa sổ có ngữ cảnh chỉ trả câu SRT trước đó.
Sau bỏ ngữ cảnh, không còn từ mới; chương trình chỉ dùng kết quả lần bổ sung,
bỏ qua phần primary còn hợp lệ và báo thiếu 748,7–766,5s.

## Sửa có giới hạn

Chỉ khi lượt bổ sung không trả được chữ mới hợp lệ, thử giữ nguyên đuôi ASR
ban đầu đã qua đường kiểm acoustic. Yêu cầu đồng thời:

- Đây là đuôi tới cuối source, nằm ngoài cue SRT đã giữ; không lấp khoảng
  trong SRT, không phục hồi cue unresolved hoặc phạm vi đã cắt.
- Ngữ cảnh câu SRT bên trái khớp duy nhất, ít nhất bốn từ; không chấp nhận
  ngữ cảnh lặp, cue quá ngắn hoặc đầu source không có mốc trái.
- Có ít nhất bốn từ mới; mọi từ đều có quality DTW, origin và anchor hữu hạn
  trong bounds, đúng source/chapter, thứ tự và thời lượng hợp lệ. Không cắt
  ngang từ ở ranh giới, không dùng estimated timing làm DTW.
- Bộ kiểm hỗ trợ âm thanh hiện hành chấp nhận toàn bộ đuôi; không giữ một
  mảnh sau khi phần khác bị từ chối. Raw recognition không bị sửa.

Snapshot primary được tách trước bước so SRT/projection; không lấy chữ SRT
đã thay vào mapping rồi gọi đó là chữ ASR. Giữ chữ hoa/dấu câu từ surfaces,
source offsets và timing origin, đồng thời ghi `primarySupplementReuseRanges`
để truy vết. Lỗi native vẫn được báo; không dùng đường lui để nuốt lỗi kỹ
thuật. Lượt bổ sung có chữ hợp lệ giữ hành vi cũ, không bỏ phiếu bản chép
hoặc so confidence khác model. Auto edit omission và model locks không đổi.

## Kiểm chứng

Ca tái hiện mới thất bại trên entrypoint 2.20.75 với lỗi
`PRIMARY_DTW_OUTRO_LOST_AFTER_EMPTY_CONTEXT_RECOGNITION`, rồi đạt sau sửa.
Kiểm estimated/mất origin/anchor sai, NaN, source/chapter, overlap/overrun,
im lặng, ngữ cảnh thiếu/lặp, khoảng giữa, cue unresolved, raw bất biến,
offset nhiều chapter và lỗi native không bị nuốt.

| Whole engine | Giữ SRT | Kết quả outro sau sửa |
|---|---:|---|
| Small | 255/255 | Caption giống từng byte 2.20.75 |
| Medium | 254/255 | Caption giống từng byte 2.20.75; còn cụt đầu |
| Turbo | 254/255 | Caption giống từng byte 2.20.75; lời sai nonempty còn nguyên |
| Large-v3 | 255/255 | Khôi phục 75 từ, 467 caption toàn bài; hết vùng thiếu outro |

Theo 77 token lời chuẩn người dùng: Large-v3 từ thiếu toàn bộ 77/77 lỗi
xuống 3/77 lỗi ở caption cuối. Đây là giảm mất nội dung của pipeline, không
phải đổi weights hay chữa chính tả tên Null Seek. Timing native vẫn cần
nghe kiểm. Các kết quả so model trước sửa được giữ nguyên theo phiên bản,
không đổi nhãn thành model không có khả năng đọc voice ngoài SRT.

Bộ hồi quy đạt 59 nhóm, 132 script PowerShell parse local; lịch sử giữ đúng
27 cue Short và 199 cue nhãn A/C. Gói/cài và CI ghi ở metadata phát hành.
[Số đo và source hash](../../benchmarks/SRT_REGRESSION_2.20.76.json).

Bản cài vẫn dùng Whisper Small. Chưa nâng Large-v3/Medium/Turbo/Qwen vào
production: Large-v3 còn lỗi quiz ở corpus cũ; các model còn sai tên riêng;
Qwen timing tiếng Việt chưa được nghiệm thu. Nghiệm thu Premiere 2.20.76
còn chờ; offline replay không chứng minh import/playback/marker/word timing.
