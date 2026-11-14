# 2.20.41 — dùng chung lõi căn SRT/voice

Auto edit và Chỉ tạo subtitle dùng chung `ReferenceAlignment.ps1` để chuẩn hóa/tách từ, đọc kết quả ASR, lập danh sách từ của SRT, gán mapping thành timing cho từng cue và nhận diện lại cue bị bỏ sót. Các hàm cũ vẫn được giữ tên để luồng hiện tại gọi qua lõi chung.

## Phần kế thừa và phần riêng

- Auto edit giữ cách so khớp theo thứ tự toàn bài, công thức timing legacy, nội suy/đánh dấu và toàn bộ executor dựng hình/voice. Phép nội suy được đưa vào lõi nhưng chỉ planner Auto edit gọi; đối chiếu với bản gốc ở 30 và 29,97 fps. Không áp dụng chính sách tự thêm lời ASR vào kế hoạch dựng Auto edit.
- Chỉ tạo subtitle giữ cách tìm đoạn SRT trong vùng audio được chọn, giới hạn bộ nhớ cho SRT dài và chính sách bổ sung đã thêm ở 2.20.40. Khác biệt chọn phạm vi là có chủ đích: một luồng cần dựng theo toàn bài, một luồng có thể chỉ xử lý vài vùng audio.
- Cả hai luồng dùng cùng phép gán timestamp từ mapping: offset chapter, vị trí từ trong cue, chữ SRT, tỷ lệ từ khớp, cue không có mapping. Subtitle giữ chỉ số cue SRT gốc ngay cả khi chỉ chọn đoạn giữa.
- Trước khi bổ sung chữ mới, subtitle dùng đúng bước phục hồi từ Auto edit: nhóm thiếu hẳn tối đa 10 cue/200 từ, khoảng 0,2–30 giây, neo lân cận đạt 0,8; yêu cầu đủ timing, mỗi cue đạt 0,7 và toàn nhóm có ít nhất 0,8 từ khớp. Chỉ nhận nếu timing hợp lệ và đúng chapter. Thành công thì giữ chữ SRT; không khớp đủ thì chuyển sang ASR bổ sung như 2.20.40.
- Luồng subtitle không gọi nội suy cue SRT theo thời lượng SRT gốc. Video/audio giữ nguyên; phần thiếu/khác, mở đầu/kết thúc và lời đăng ký kênh vẫn được nhận diện bổ sung vào cùng SRT/caption kết quả. Nếu nhận diện bổ sung không có lời nói, báo vùng trống để kiểm tra, không chèn lại chữ SRT bằng thời gian ước lượng. Phân bố từ trong một đoạn câu ASR vẫn theo cách của 2.20.40, dựa trên khoảng thời gian đoạn nhận diện được.
- Các lượt phục hồi và bổ sung dùng chung hàm cắt/nhận diện cửa sổ audio của subtitle. Timing mới có nguồn gốc riêng, không ghép nhầm vào overlay DTW của lượt ASR đầu. Log ghi cue đã phục hồi; danh sách cần nghe lại dùng chỉ số SRT gốc sau khi gộp/đánh số lại.

## Kiểm chứng và giới hạn

Snapshot thuật toán Auto edit 2.20.40 nằm trong test helper độc lập với runtime, chỉ làm oracle. 100 fixture có seed đối chiếu toàn bộ cue/word timings/confidence, kể cả từ thừa/thiếu/khác và hai chapter. Kiểm parser legacy giữ nguyên cả các khoảng rất ngắn và timestamp bằng 0; subtitle tiếp tục lọc metadata/clamp theo đoạn audio. Cùng một tham chiếu đầy đủ cho kết quả gán cue tương đương ở hai luồng. Cùng một cue thiếu được phục hồi bằng cùng hàm và cùng timestamp; trường hợp nhận diện lại không khớp vẫn chờ bổ sung.

Các test SRT dài, CTA, nội dung khác ở giữa, nhiều vùng, fallback ASR và timing sai tiếp tục chạy. Gói cài yêu cầu có lõi mới trong allowlist/checksum. Đây là kiểm thử tự động, không chứng minh chất lượng ASR hoặc nghiệm thu caption/Play/Save trên Premiere thật. Xem [hành vi bổ sung 2.20.40](NOTIFICATIONS_2.20.40.md).
