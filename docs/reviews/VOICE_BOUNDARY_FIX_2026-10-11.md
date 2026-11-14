# Sửa lỗi điểm cắt voice 2.20.27

Trạng thái: đã kiểm thử cục bộ, chưa nghiệm thu dựng native. Người dùng đồng ý cập nhật panel thử; main/Release vẫn là 2.20.25. Bản sửa dựa trên giao diện 2.20.26.

## Nguyên nhân đã tái hiện

Ở một câu rất ngắn (cue SRT đầu vào 118), hai ranh giới liên tiếp chọn cùng điểm nghỉ tại frame 12505. Planner cũ phát sinh range 12505–12505, tự nâng mép cuối lên 12506 nhưng câu kế tiếp vẫn bắt đầu tại 12505. Một frame voice vì thế bị dùng hai lần. DTW dừng với `TRIAL_VOICE_LOST_OR_DUPLICATED` đúng với guard; không phải guard báo nhầm và không phải do giao diện 2.20.26.

Log xác nhận lỗi xảy ra tại bước `dtw-plan`, trước bước dựng timeline. Cùng vấn đề đã có trong baseline planner; đoạn ngắn cũ có speed hình 2100% vì chỉ được cấp một frame voice. Không giải quyết bằng cách nới dung sai hoặc bỏ kiểm tra.

## Bản sửa nhỏ, có giới hạn

- Trước khi chấp nhận điểm cắt silence, kiểm trên lưới frame: điểm cắt phải nằm sau đầu nhóm hiện tại và trước cuối câu kế tiếp. Không đạt thì giữ câu trong nhóm chung, đúng quy tắc chưa an toàn thì không cắt.
- Bỏ việc tự nâng range voice rỗng lên một frame. Dữ liệu không thể biểu diễn hợp lệ được báo `PLAN_VOICE_RANGE_INVALID` trước dựng.
- Thêm kiểm các nhóm voice cùng chapter nối chính xác theo frame. Khoảng trống hình không lời vẫn giữ như trước; không thêm pause mới.
- Không đổi Whisper/DTW/word mapper, căn hoặc chia caption, silence detector, ngưỡng an toàn, guard bảo toàn DTW, gộp hình hay JSX executor. Không ép voice về 100%.

## Kiểm chứng

- Tái hiện nguyên lỗi trước sửa từ project đã lưu, đọc XML nén chỉ để lấy thời gian/speed; không ghi project. Bốn chapter voice khoảng 110%, 510 cue SRT. Mốc kiểm thử là từ file đã lưu, không khẳng định trạng thái project đang mở giống hệt.
- Sau sửa: baseline, DTW và gộp hình đều hoàn tất; DTW thêm 4 điểm cắt, bảo toàn source/voice/caption và thời lượng giữa các kế hoạch. Kiểm mọi interval voice trong cả bốn chapter không rỗng, không hở/chồng. Nội dung 1126 caption giữ đầy đủ chữ SRT. Kết quả gộp hình với tham số mặc định 70–130%, gap 1/2 giây: 46 cặp; A2/caption không đổi trong bước gộp.
- Căn voice dùng lại 53 kết quả Whisper và 4 kết quả khoảng nghỉ đã có; dữ liệu chẩn đoán riêng không được đưa lên GitHub hoặc đóng gói.
- Thêm fixture hai ranh giới dùng chung điểm nghỉ ở 30 và 30000/1001 fps; điểm cắt vượt cuối câu kế tiếp; range voice rỗng không được nâng giả thành một frame. Giữ các test điểm nghỉ an toàn, căn chữ yếu, vùng không lời và DTW từ chối mất/lặp voice.
- 35 nhóm hồi quy đạt, 88 file PowerShell parse đạt; JS và fixture bố cục hai chế độ ở 320/385/560 px đạt. Không thực hiện native edit, Play/Preview hoặc Save trong các kiểm thử này.

## Nghiệm thu cần người dùng

Chạy lại từ template sạch với đầu vào/thông số thực tế. Kiểm đoạn câu ngắn vừa bị lỗi, kết quả voice/caption, Preview/Play và Save. Không merge main hoặc tạo Release chỉ từ kết quả planner/fixture.
