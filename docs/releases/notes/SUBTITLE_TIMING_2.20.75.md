# 2.20.75 — adapter nhận diện và thử timing tiếng Việt

Bản này tách lời gọi Whisper khỏi lớp timing/SRT để chuẩn bị thêm một mô hình
nhận diện tiếng Việt. Model production vẫn Whisper Small; chất lượng chữ ở
voice ngoài SRT chưa thay đổi. Không cần chạy lại project chỉ để kỳ vọng bản
này sửa chính tả outro.

## Phạm vi đã làm

`RecognitionBackend.ps1` gom profile, tham số gọi, CPU fallback và kết quả
chuẩn. Kết quả chuẩn ghi rõ đơn vị giây trong cửa sổ nguồn, ngôn ngữ yêu cầu/
nhận diện, raw JSON và timing chưa xác minh. Word timing không được tự tạo.
Raw JSON tiếp tục được đưa nguyên vẹn vào lõi timing/SRT hiện hành.

Caption-only dùng wrapper adapter. Auto edit dùng chung bộ tạo tham số;
quyết định fallback, parser và bằng chứng omission/cắt hiện hành vẫn giữ
nguyên. Đây là bước đầu, chưa phải toàn bộ engine độc lập mọi backend.
Không đổi khóa runtime/model, cache key, thuật toán SRT, ngưỡng timing hoặc
ngôn ngữ. Chưa đăng ký Qwen hay router đa ngôn ngữ vào chương trình.

## Kiểm bảo toàn hành vi

- So với hàm gốc đóng băng từ 2.20.74: 11 trường hợp CPU/CUDA, cache,
  fallback, lỗi, Unicode, ngôn ngữ và DTW; argv, raw JSON và số lượt gọi khớp.
- Bản dựng lại Nam Cực với Small: caption SRT giống từng byte bản 2.20.74,
  giữ 255/255 cue nguồn và 468 caption; 113 cache Whisper hit/0 miss,
  186 quiet hit/0 miss. Đây là offline replay, không phải một lượt Premiere mới.
- Bộ hồi quy, số file gói và trạng thái cài đặt ghi trong metadata phát hành.
  Các ca SRT/số/đơn vị/lời thêm/nhãn/marker trước đây tiếp tục nằm trong suite.
- Người dùng xác nhận lượt thực tế 2.20.74 đã hết lỗi đổi chữ SRT sang ASR;
  xem [biên bản giới hạn xác nhận](../../acceptance/2.20.74_USER_RERUN_2026-10-18.md).
  Chưa coi timing, marker và mọi workflow là đã nghiệm thu.

## Thử timing riêng cho ứng viên Qwen

Qwen 1.7B là ứng viên ưu tiên về chữ trên corpus nhỏ đã đo, vẫn sai tên riêng.
Thử nghiệm mới giữ nguyên bản chép Qwen và chỉ thử căn bằng CTC tiếng Việt,
không chạy lại ASR, không dùng SRT làm prompt và không sửa chữ để ép khớp.

WhisperX hiện ánh xạ tiếng Việt tới model có giấy phép CC-BY-NC-4.0 theo
[model card](https://huggingface.co/nguyenvulebinh/wav2vec2-base-vi-vlsp2020/raw/main/README.md).
Probe riêng dùng [dragonSwing/wav2vec2-base-vietnamese](https://huggingface.co/dragonSwing/wav2vec2-base-vietnamese),
model card ghi Apache-2.0. Khóa revision và SHA-256 trong kết quả tổng hợp;
chỉ đọc safetensors/cấu hình cục bộ, không chạy mã tải từ repo model.

| Bản chép giữ nguyên | Đoạn | Kết quả probe |
|---|---|---|
| Qwen 0.6B | Outro hội viên | 75/75 từ có CTC candidate |
| Qwen 0.6B | Outro có ngữ cảnh | 87/87 từ có CTC candidate |
| Qwen 1.7B | Outro hội viên | 75/75 từ có CTC candidate |
| Qwen 1.7B | Outro có ngữ cảnh | Từ chối: ký tự `6` trong `No6` ngoài vocabulary |

Mọi candidate đều **chưa xác minh**, không được dùng để cắt hình. Coverage
không đo độ chính xác timing hoặc chứng minh bản chép đúng. Aligner có thể
căn một chữ sai vào âm thanh; chưa có gold ranh giới từ nghe đối chiếu.
Không bỏ ký tự không hỗ trợ, không wildcard hay nội suy để biến ca lỗi thành đạt.
Probe là công cụ nghiên cứu, không nằm trong bộ cài và không thay model.

## Bước kế tiếp

Tạo mẫu ranh giới từ được nghe kiểm ở outro, số, tên riêng, chuyển câu và
khoảng im lặng; đo sai số cùng tỷ lệ bị từ chối. Xử lý chữ số/tên ngoại ngữ
bằng mapping có provenance và kiểm thử, không sửa ngầm raw transcript.
Chỉ khi chữ và timing đạt mới đưa một profile Qwen vào trial có đường quay
về Small, kiểm toàn engine/các ca hồi quy rồi thử trên project dùng thử.
Chưa triển khai đồng thời 14 ngôn ngữ.
