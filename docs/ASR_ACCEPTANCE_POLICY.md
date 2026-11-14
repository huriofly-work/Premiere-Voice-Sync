# Tiêu chí nghiệm thu ASR và caption

## Không hủy tác vụ chỉ vì lỗi nhận diện — 2026-10-21

Người dùng yêu cầu lỗi khó mà model hiện tại chưa nhận đúng phải được báo
và chuyển sang review; chương trình tiếp tục phần có thể xử lý. Không yêu
cầu nhận diện chính xác hoàn toàn để xuất kết quả hữu ích.

Auto edit giữ đủ hình/voice của vùng chưa chắc thành khối cần sửa tay;
không tạo điểm cắt bên trong hoặc cấp omission từ timing/text ước lượng.
Khi luồng DTW độc lập xác định duy nhất ngữ cảnh hai bên một ranh giới và
có frame cắt trong khoảng lặng đã đo, có thể chia hình/voice tại ranh giới
đó; quyền này tách riêng với caption chưa khớp. Chữ chưa chắc không làm vô
hiệu toàn bộ ranh giới đã xác minh trong khối. Caption được thử căn lại cục
bộ, chỉ phần vẫn thiếu bằng chứng mới dùng timing ước lượng/cần xem lại.
Khối bảo toàn có thể dài hơn giới hạn retry/khối tự động 30 giây. Không xác định
được vùng tương ứng thì giữ template, trả kết quả phân tích cần dựng thủ công;
không bịa kế hoạch hoặc báo đã dựng xong. Caption-only giữ phần primary hữu
ích, đánh dấu phần chưa xác minh; không có caption dùng được thì hoàn tất
với cảnh báo, không import file/track rỗng.

Lỗi đọc/ghi file, runtime thất bại sau fallback, hủy tác vụ, timeline thay
đổi hoặc hậu kiểm không bảo toàn vẫn ngăn thao tác liên quan. Chỉ phân loại
các mã chất lượng nhận diện đã biết thành review; không catch mọi lỗi để
biến thành thành công. Kiểm tự động không thay nghiệm thu native Premiere.

Quyết định của người dùng ngày 2026-10-18: lỗi khó, hiếm gặp có thể đánh dấu
để người dùng sửa thủ công. Không đặt mục tiêu bắt buộc đúng hoàn hảo100%
trong mọi trường hợp, hoặc giữ toàn bộ nâng cấp ở nghiên cứu chỉ vì vài ca khó.

## Kết quả hữu ích và phần cần xem lại

Ưu tiên đo kết quả caption cuối trên các dự án thực tế: chữ, đủ lời, SRT đã
khớp, timing đủ dùng, thời gian chạy và số vùng người dùng phải sửa. Báo riêng
lỗi phổ biến/có hệ thống với ca khó được chọn để chẩn đoán; không suy tỷ lệ
lỗi toàn bộ từ ba clip A/C/nhé. Không hứa phát hiện được mọi lỗi chính tả.

Tên riêng hiếm, một vài từ nghe khó hoặc cạnh caption cục bộ chưa chắc có thể
giữ kết quả và đưa vào danh sách cần xem lại, có vị trí và lý do. Ưu tiên dùng
cơ chế đánh dấu/review đang có. Không tạo lại cảnh báo số đọc đã bỏ chỉ vì
SRT và voice viết cùng giá trị theo hai cách khác nhau. Một vùng cần sửa tay
không mặc nhiên làm hủy kết quả của các vùng khác.

Nếu một vùng không căn được, dùng đường lui hiện có đúng phạm vi và khai báo
ước lượng/cần xem lại; không bịa mốc cho từng từ, im lặng bỏ lời hoặc đổi model
của job đang chạy. Chỉ đánh dấu sau khi có căn cứ; số vùng có tín hiệu rủi ro
không phải số lỗi đã nghe xác nhận.

## Các lỗi vẫn phải bảo vệ

- Không làm mất hoặc đổi chữ SRT ở câu đã có đủ bằng chứng nhận diện.
- Không tự phục hồi câu đã cắt, bỏ lời thêm thật, lặp lời hoặc cắt mất tiếng.
- Không sửa sai giá trị số/ngữ nghĩa để ép khớp; ca chưa chắc chuyển review.
- Không coi timestamp ước lượng, CTC hoặc attention có chạy DTW là timing
  đã xác minh để cho Auto edit tự cắt. Caption-only và quyền cắt hình có
  điều kiện năng lực riêng.
- Giữ dữ liệu, cache/model/job/backups và các chốt toàn vẹn. Kiểm hồi quy cũ,
  package/source và native acceptance theo đúng phạm vi thực tế.

## Trình tự áp dụng

1. Chốt một ứng viên tiếng Việt qua full caption pipeline, đồng thời xác định
   rõ những vùng cần sửa tay và mức độ phát hiện được bằng tín hiệu sẵn có.
2. Chạy ca lịch sử và mẫu mới; đánh giá khối lượng sửa tay, lỗi nặng và tài
   nguyên máy. Mẫu đã dùng điều chỉnh không được gọi là holdout độc lập.
3. Tích hợp caption-only có review/fallback trước khi cân nhắc quyền cắt hình;
   không chờ mọi từ đều đạt một ngưỡng millisecond hoặc WER bằng0.
4. Đóng gói/prerelease và nghiệm thu Premiere theo quy trình; ghi rõ phần tự
   động đã kiểm, phần cần người dùng rà và lỗi còn mở. Không tự merge/stable.

Quyết định này thay tiêu chí hoàn hảo bằng tính hữu ích có kiểm soát; không
phải thay đổi ngưỡng identity/timing an toàn của engine trong lượt tài liệu.

## Chốt model sau khi chấp nhận lỗi hiếm

Giữ số đo cũ, xét lại cách chốt ứng viên: công sửa thực tế và caption cuối
có thể thay thứ tự ưu tiên so với chỉ WER. Không suy công sửa từ số marker,
hoặc loại model nhận chữ từ vài lỗi của provider timing. Bản chép sửa bởi
người nghe chưa tự động thành gold độc lập; so trên cùng audio, giữ lỗi
nặng riêng và đối chiếu lời chuẩn trước khi kết luận độ chính xác.
Protocol so sánh thực dụng (hồ sơ; từ 13/11/2026 Qwen không còn là ứng viên).

## Không bắt người dùng làm cả bài kiểm thử thủ công

Người dùng xác nhận sáu lượt nghe/sửa A/B tốn quá nhiều thời gian. Ưu tiên
chấm tự động trên audio có lời chuẩn công bố hoặc đã được xác nhận; giữ
nguyên bảo vệ SRT/lời thêm/omission và kiểm caption cuối. Lời chuẩn không
được đưa vào prompt ASR. SRT chưa xác minh khớp voice hoặc nhiều model nhận
giống nhau không tự trở thành gold. Điểm theo nhãn corpus không có nghĩa
mọi nhãn đều đúng hoặc độc lập với dữ liệu train của model.

Đo thời gian sửa tay là tùy chọn, không là điều kiện chặn việc chọn/tích hợp
ứng viên. Có thể báo số lỗi đối chiếu được theo lời chuẩn, tách thêm/thiếu/
thay từ, tên/số và mức độ ảnh hưởng; không gọi đó là số phút sửa thực tế.
Chỉ nhờ nghe vài đoạn ngắn khi bằng chứng tự động chưa đủ cho một quyết
định quan trọng. Không đòi người dùng hoàn tất sáu bản hoặc toàn bộ corpus.
