# 2.20.88 — Giảm tính chữ lặp và các đợt đổi tốc độ không có việc

## Chẩn đoán từ log thực

Lượt Auto edit 2.20.87 ngày 21/10 lúc 22:37 hoàn tất trong 909.477ms:
alignment277.035ms, sentence-plan80.099ms, DTW2.699ms, speed-merge3.415ms,
timeline544.299ms. Alignment dùng248 Whisper hit/0miss,126 quiet hit/0miss;
không phải mất cache hoặc tự chuyển CPU. Timeline269 lượt, check152.569ms,
snapshot78.236ms; QE43.240ms nằm trong work, không cộng hai lần.

Hai lượt caption-only ngày22/10 lúc08:36 và09:53 hoàn tất375.493/88.057ms;
alignment357.195/86.401ms, Whisper6hit/111miss và4hit/14miss. Xuất audio
14.821/739ms, import3.223/853ms. Đây là các đầu vào khác nhau, không phải
cặp benchmark. Không lấy thời gian người dùng mở thông báo làm thời gian chạy.

## Nguyên nhân và thay đổi

Planner kiểm nhiều proof trên cùng319 câu. Instrumentation trên bản sao
Alien đếm101.095 lần chuẩn hóa chữ;152 lần whole-cue validator đã dùng
38,9s inclusive trong lượt có instrumentation. Các thời gian inclusive
chồng nhau và có overhead đo, không cộng hoặc dùng làm baseline tăng tốc.

`ReferenceAlignment.ps1` lưu kết quả chuẩn hóa **theo chuỗi đầu vào chính
xác**, Ordinal, trong process. Tối đa2.048 chuỗi, mỗi chuỗi tối đa4.096 ký tự;
quá giới hạn tính lại bình thường. Chỉ lưu mảng chuỗi bất biến và trả qua
pipeline enumeration; caller không sửa được container lưu. Không cache
cue object, uniqueness, timing, kết quả proof, cut hoặc omission. Đổi chữ
hoặc số buộc tính lại; mọi validator vẫn thực thi trên dữ liệu hiện tại.
Phần dùng chung áp dụng cho Auto edit/caption-only, retry/supplement,
legacy/DTW và planner; không thêm setting hoặc thay cache audio lưu trên đĩa.

Đổi thuật toán kiểm nhiều proof: dựng bảng số lần xuất hiện của chữ chuẩn hóa
từ reference hiện tại một lần trong mỗi lượt kiểm, rồi tra cứu cho từng proof.
Phần kiểm tính duy nhất giảm từ O(P×C) lần chuẩn hóa/quét sang O(C+P), với
P điểm cắt/C câu; các phép kiểm timing/quiet/frame vẫn chạy đầy đủ. Cả bước
chọn nhóm và hậu kiểm plan dùng đường batch; đường kiểm proof đơn lẻ vẫn
dựng index mới. Index không nằm trong JSON, không sống qua các lượt kiểm,
không lấy từ caller/plan; comparer giữ đúng `-ceq` trước đây. Không coi đây
là giảm độ phức tạp của mọi bước trong toàn bộ planner.

Generator trước đây đếm cả đoạn sai chiều speed/100%/gap vào giới hạn4
cặp, tạo nhiều đợt đọc/kiểm timeline mà không chỉnh đủ4 cặp. Tách ngân sách
quét và ngân sách native: mọi vòng vẫn có iteration/time cap, mỗi đợt tối
đa4 cặp V1–A1 thực sự chỉnh. Cặp nguyên tử, thứ tự/đối số native, snapshot
trước/sau, rebind, hậu kiểm và ranh giới hủy được giữ. No-delay vẫn20 vòng/
250ms, không artificial sleep; một native call đơn lẻ vẫn có thể vượt budget.

## Đo và hồi quy

Cặp replay planner cùng dữ liệu/cache, không instrumentation:66.591→32.938ms
(giảm50,5% ở bước này); cả hai3 quiet hit/0miss. Toàn bộ plan JSON bằng nhau
sau khi bỏ `createdAt`/đường dẫn thư mục đo; SRT giống từng byte. Cặp trước
khi đổi thuật toán index, chỉ có lexical memoization:29.473→17.840ms. Không
so chéo hai cặp hoặc với80.099ms của lượt native vì điều kiện máy khác nhau.
ASR pilot CPU có77 miss ở baseline nhưng0 miss ở candidate bị loại khỏi
kết luận tốc độ. Cặp CUDA dùng cùng backend đã xác minh và cache copy,
chặn nhận diện mới khi cache miss:227.682→121.845ms (giảm46,5%); cả hai248
Whisper hit/0miss,126 quiet hit/0miss, không cache hỏng/lỗi ghi. Cả JSON
alignment và SRT giống toàn bộ (chỉ chuẩn hóa đường dẫn thư mục đo/createdAt).
Tổng hai bước trong cặp đo294.273→154.783ms (giảm47,4%); không bao gồm
Premiere, xuất/import, backend resolver/probe hoặc model inference mới.
Đây là một cặp warm-cache, không phải trung bình nhiều lượt hay cold-cache.

Mock302 đoạn: speed152→52 lượt, tổng280→180 ở baseline/no-delay và200→100
ở fast; đây là số lời gọi mô phỏng, chưa phải thời gian tiết kiệm trong Premiere.
Regression sparse-speed thất bại trước sửa, đạt sau sửa trên cả ba profile;
kiểm tối đa4 cặp/đợt. Các fixture hiện có giữ đúng từng native call/report,
omission/cue picture/A2/frame/marker, thay đổi timeline giữa đợt và abort.
Lexical regression kiểm Unicode, số, chữ đổi, caller mutation, eviction và
chuỗi dài. Không đổi model, threshold, chất lượng chữ hoặc bằng chứng DTW.
Batch-proof regression đo số lượt chuẩn hóa tuyến tính, so từng kết quả với
đường đơn lẻ, kiểm duplicate sau lượt trước/đổi số/estimated/time/chapter/
quiet/frame và comparer Unicode; `-RequireAll` vẫn dừng với mã lỗi cũ.

## Giới hạn và nghiệm thu

Chưa kết luận giải quyết toàn bộ độ chậm. Caption có nhiều nhận diện mới
vẫn tốn thời gian nạp/chạy Whisper từng cửa sổ; worker giữ model và thay đổi
kiến trúc cần phép đo riêng. Snapshot/QE và native speed vẫn có chi phí.
Không bỏ guard, tăng batch vô hạn hoặc dùng nhiều worker sửa timeline.

Native import/playback/timing/marker và thời gian thực tế bản88 còn pending.
Không Save/Undo, không ép đóng Premiere/helpers hoặc sửa job đang chạy.
Cài đặt chỉ sau khi người dùng đóng ứng dụng thủ công; giữ dữ liệu/cache/model/
jobs/backups và phiên bản trước để quay lại. Không tự merge hoặc promote stable.
