# 2.20.40 — SRT dài và nhận diện bổ sung

Chế độ **Chỉ tạo subtitle** dùng SRT có sẵn cho phần lời khớp và tự nhận diện phần còn lại trong toàn bộ vùng audio đang chọn, gồm mở đầu, kết thúc và lời đăng ký kênh. Kết quả ghép vào một SRT và một lượt tạo caption. File SRT đầu vào giữ nguyên.

## So khớp SRT dài

Thay giới hạn cố định 25 triệu ô bằng checkpoint hàng chi phí và tính lại traceback từng khối. Giữ recurrence, tie order và các near-best endpoints; bộ nhớ chính O(m×√n), thời gian O(n×m). Có ngân sách 128 MiB cho các mảng chính, không phải giới hạn tổng RAM của PowerShell/Whisper. Hàm căn cũ Align-PvsSubtitleReference ngoài luồng run-captions.ps1 vẫn giữ guard cũ.

## Ghép SRT và nhận diện

- Giữ chữ SRT của các cue đủ căn cứ khớp. Khi SRT nằm trong audio dài hơn, tìm trọn SRT bằng mốc từ rõ ở hai mép. Phần audio ngoài SRT được đưa sang nhận diện bổ sung.
- Các cue thiếu hoặc không khớp được gom theo khoảng audio giữa những cue đã khớp, rồi nhận diện lại chính các khoảng đó. Không dùng timestamp SRT cũ để đoán, không đưa chữ SRT vào prompt ép nhận diện. Chỗ chỉ có im lặng và không có dấu hiệu thiếu cue không gọi nhận diện thêm.
- Nếu không tìm được phạm vi SRT duy nhất/an toàn, nhận diện audio được chọn thay vì gán nhầm chữ tham chiếu. Lỗi bộ nhớ, SRT không hợp lệ và lỗi công cụ vẫn dừng.
- Nếu timestamp DTW của lượt đầu không hợp lệ, nhận diện lại nguồn đó bằng các đoạn câu trước khi so khớp/bổ sung. Các lượt bổ sung dùng đoạn câu, tránh timestamp bằng 0 của chế độ tách từng từ. Có thể cần thêm thời gian xử lý.
- Giữ offset, chapter và giới hạn từng vùng audio; báo các khoảng đã bổ sung trong log và thông báo cuối. Những vùng đã thử nhưng không tìm được lời nói được báo riêng để người dùng kiểm tra. ASR có thể nghe sai; cần nghe lại phần chữ tự nhận diện.
- Gộp một danh sách cue liên tục, giữ chỉ số cue SRT gốc làm provenance cho phần dùng chữ tham chiếu. Không sửa video/audio hoặc lưu project tự động.

Tạm dừng/tiếp tục và dừng tác vụ tiếp tục như [2.20.39](NOTIFICATIONS_2.20.39.md).

## Kiểm chứng

120 ca có seed đối chiếu từng mapping/chi phí/mép với oracle toàn ma trận. Fixture dài kiểm 36 triệu ô toàn bài, 30 triệu ô đoạn giữa, 60 triệu ô tham chiếu lặp và audio lặp; kiểm bộ nhớ trước cấp phát. Fixture ghép kiểm giữ chữ SRT, nội dung khác ở giữa, intro, CTA, offset nhiều vùng, fallback toàn ASR, kết quả rỗng và timing sai. Mock native kiểm lượt câu không có -sow/-ml/-dtw/prompt; UI kiểm báo phần bổ sung và vùng không tìm thấy lời.

File Source.srt của project Ý thức đến từ đâu đọc được 615 cue/7.591 từ. Kết quả ASR đã lưu gần nhất theo parser legacy có 7.263 từ: 55.133.433 ô. Bản sửa chọn được 603 cue tham chiếu; 12 cue cần nhận diện lại, cùng các khoảng lời nói khác và CTA cuối. Đây là kiểm so khớp/lập khoảng trên dữ liệu cache, chưa chạy nhận diện mới hoặc tạo caption trong Premiere. Lượt mới có thể dùng kết quả nhận diện câu khác sau fallback DTW. Không suy kết quả ASR hoặc nghiệm thu import/Play/Save từ fixture hay cache.
