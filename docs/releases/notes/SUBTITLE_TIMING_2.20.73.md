# Premiere Voice Sync 2.20.73 — căn từ theo chính sách giữ SRT

## Lỗi và cách sửa

Bản dựng ngoại tuyến Nam Cực ở 2.20.72 giữ 250/255 câu SRT. Một số câu
bị loại dù đã đủ chữ để nhận ra câu: bộ căn vị trí chỉ so chữ chính xác,
trong khi bộ xét nhận câu chấp nhận biến thể dấu và đơn vị tiếng Việt.
Ví dụ `thụ/thu` bị căn lệch sang `ô`, còn `mét` bị căn vào `000` thay vì `m`.

Nếu phép căn cũ không qua bước xét nhận câu, nhánh chỉ tạo subtitle thử
lại phép căn với biến thể dấu/đơn vị đã được chấp nhận. Việc xét sau đó
vẫn dùng chữ ASR, timestamp, chất lượng và nguồn timing gốc. Giữ phép căn
cũ khi nó đã đạt. Không thay chữ SRT, ngưỡng nhận câu, ngưỡng bằng chứng
Auto edit, timing chung hoặc đường căn của ngôn ngữ khác.

Số dạng `1 phần 3` được coi là một trường số khi nhận dạng ngữ cảnh câu.
Chữ nối phải nằm ngay giữa hai token số; `3 phần việc 4` và `3 ngày 4`
không trở thành một trường số. SRT vẫn quyết định giá trị được hiển thị.

## Kiểm chứng và giới hạn

- Kiểm thử mới tái hiện lỗi với “Chúng hấp thụ ô xy trực tiếp qua da để
  tồn tại” và hai câu liền nhau “đỉnh cao nhất gần 3000 mét”, “xấp xỉ
  1 phần 3 chiều cao của Everest”. Cùng test thất bại trên gói 2.20.72.
- Phát lại bước chọn SRT với audio Nam Cực giữ **253/255**, tăng ba câu
  167, 209, 210; hai câu chưa giải quyết là 138 “nước hồ giàu sắt” và
  207 chứa tên “Gamburtsev”. Không ép ghép tên riêng hoặc hạ ngưỡng câu ngắn.
- Phát lại cache ca ý thức giữ đúng 27 câu (1–9, 14–31); ca chữ cái giữ
  đúng 199 câu như baseline, gồm các câu A/C. Không phục hồi câu đã cắt.
- Bộ hồi quy gồm kiểm giữ chữ qua caption cuối, ASR gốc không bị sửa,
  căn ngôn ngữ khác không đổi, số/ngữ cảnh thường, lời thêm thật,
  vùng mơ hồ, timing, marker, pause/cancel và thông báo Windows.

Audio Nam Cực được dựng từ các clip voice trong project đã lưu; không
phải bản mix/effect do Premiere xuất. Dữ liệu thử nằm trong thư mục tạm,
không đưa audio, project, cache hoặc weights vào GitHub.

**Nghiệm thu native còn chờ:** chạy lại “Chỉ tạo subtitle”, nghe kiểm
chữ/timing/marker trong Premiere bằng project thử. Kiểm thử tự động,
đóng gói và cài đặt không thay thế bước này. Bản phân phối là prerelease;
Whisper small vẫn là mô hình hiện hành. Hai câu còn mở tiếp tục được theo
dõi trong GitHub issue #14; nghiên cứu mô hình ưu tiên tiếng Việt trước.
