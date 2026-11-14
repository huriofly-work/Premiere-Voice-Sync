# Giữ chữ SRT khi nhận diện thiếu vài từ — 17/10/2026

Chính sách dưới đây là lịch sử 2.20.56. Đã được bổ sung tiêu chí nhận ra cả câu
trong [2.20.59](../releases/notes/SUBTITLE_TIMING_2.20.59.md), theo yêu cầu ưu tiên giữ chữ SRT.

Đã đóng gói/cài đặt 2.20.56 ngày 17/10/2026; xem
[bằng chứng phát hành](../releases/notes/SUBTITLE_TIMING_2.20.56.md). Không thao tác project Premiere;
nghiệm thu nhận diện/caption trong Premiere vẫn chờ người dùng.

## Vấn đề

Chỉ tạo subtitle bật `AllowEditedReference`. Bộ tìm câu cho voice đã cắt yêu cầu
khớp nguyên câu; retry không có prompt SRT cũng yêu cầu khớp nguyên văn. Chỉ một
từ ASR bỏ sót có thể làm cả câu bị chuyển sang chữ tự nhận diện và marker bổ sung.
Đường chọn SRT dự phòng còn yêu cầu đủ timestamp của mọi từ.

## Chính sách mới cho subtitle

- Giữ nguyên chữ SRT khi ít nhất 80% từ khớp chính xác và chỉ thiếu/khác tối đa
  hai từ. Câu phải có 5–200 từ, mốc đầu/cuối được nhận diện khớp chính xác và
  timestamp hợp lệ, đúng nguồn, đúng thứ tự, không chồng.
- Với từ không có timestamp, phải có khoảng giữa hai từ đã đo ít nhất 60 ms
  cho mỗi từ thiếu. Khoảng này chỉ là điều kiện chặn chỗ nối sát sau cắt, không
  chứng minh từ đó đã được đọc và không được ghi thành timestamp của từ thiếu.
- Mọi từ ASR trong khoảng câu phải được ánh xạ; không nuốt lời nói thêm. Câu SRT
  lặp, mất đầu/đuôi, khác nhiều chữ hoặc không có khoảng timing đủ vẫn chưa xác minh.
- Chỉ thử phục hồi từ các cụm chưa xác minh, tối đa 10 cue/200 từ/30 giây. Cue
  được bộ đối chiếu phân loại là đã bỏ không được phục hồi theo chính sách này.
- Giữ nguyên timing quan sát được, không tạo timing cho từ thiếu. Gắn
  `SubtitleReferencePartialMatch` và yêu cầu nghe lại chữ/timing. Không coi cue này
  là DTW đã xác minh; caption dùng bộ tách hiện có với cảnh báo rõ.
- Áp dụng cả nhánh voice đã cắt và nhánh đối chiếu dự phòng của subtitle.
  `ReferenceAlignment.ps1` và điều kiện cho phép Auto edit bỏ hình giữ nguyên.

Đây là chính sách ưu tiên bản chữ SRT có sẵn khi nhận diện gần khớp. Nếu voice
thực sự thay/cắt một hoặc hai từ giữa câu nhưng vẫn để khoảng timing phù hợp,
không thể phân biệt chắc chắn chỉ bằng các kết quả ASR này; marker yêu cầu nghe lại
vẫn được giữ. Không tuyên bố chữ hoặc mốc từng từ đã được xác minh hoàn toàn.

Marker bổ sung phân biệt cue SRT chưa xác minh với lời nhận diện ở vùng chưa có
SRT khớp bao phủ. Câu giữ chữ SRT nhận marker riêng nêu rõ cần kiểm tra chữ/timing.

## Kiểm chứng

`Test-SubtitlePartialReference.ps1` kiểm một/hai từ thiếu, thay một từ, giữ nguyên
chữ qua bước tạo và tách caption, cờ review, không bịa timing, cue khớp đủ, chỗ nối
đã nén, thiếu đầu/đuôi, khác nhiều từ, bỏ cả câu, lời nói thêm, đường đối chiếu dự
phòng, câu lặp, offset nguồn và timestamp hỏng. Kiểm cả việc kết quả/bằng chứng
dùng cho Auto edit vẫn không cho phép bỏ hình từ các cue chỉ khớp một phần.

`review-markers.test.js` kiểm nhãn giữ chữ SRT và hai loại nhận diện bổ sung.
Các ca này là fixture/VM, không phải nhận diện hoặc nghiệm thu Premiere thật.

Ngày 17/10/2026: `Run-Tests.ps1 -NoWindowsIntegration` đạt **47 nhóm**, parse
**116 script PowerShell**; sáu nhóm Windows integration được runner bỏ qua.
TEMP/TMP/LOCALAPPDATA riêng trong `.tmp-subtitle-partial/`. Lượt sandbox đầu bị
chặn tạo junction trong test bảo mật; lượt cuối ngoài sandbox đạt cả nhóm này.
Log cuối: `.tmp-subtitle-partial/suite-final.log`. Đồng bộ số phiên bản ghi trong
workflow log từ giá trị cũ 2.20.54 về VERSION hiện tại 2.20.55 để kiểm metrics đạt.
JS syntax và diff whitespace đạt. Không chạy ASR mới trên audio thật hoặc mở,
đóng, Play, Undo, Save, nhập caption hay cài đặt panel Premiere.
