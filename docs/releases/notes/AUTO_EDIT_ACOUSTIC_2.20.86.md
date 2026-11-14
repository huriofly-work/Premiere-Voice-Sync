# 2.20.86 — Dựng hình theo cue SRT

Người dùng chạy native 2.20.85 vẫn nhận 158 đoạn voice, 695 caption và
74 marker review, báo hình lệch voice và thiếu điểm cắt. Log xác nhận bản85
đã thực sự được chạy, không phải đang dùng nhầm bản cài.

## Kiểm tra lịch sử và nguyên nhân

`v2.19.1:extension/engine/lib/TimelinePlan.ps1` có `New-RetimePlan` lặp theo
từng cue: nguồn chỉ chạm nhau được giữ thành hai đoạn, chỉ nguồn thực sự
chồng lấn mới gộp. Bản lưu hiện nằm trong
legacy-speed-clamp.
Nhánh này còn có speed clamp đã loại bỏ; không khôi phục clamp vì nó có thể
làm mất đồng bộ. `build-sentence-plan.ps1` ở v2.19.1 cũng có nhóm theo dấu
câu và được main.js gọi. Vì vậy không coi sự tồn tại của helper per-cue là
bằng chứng tất cả phiên native cũ đều đã chạy đúng helper đó.

Các bản79–83 dùng proxy để giữ vùng recognition khó. Hình và voice dùng chung
nhóm; proxy dài chặn các điểm cắt nội bộ. Bản85 thêm ngữ cảnh tám từ DTW và
silence để mở điểm cắt, nhưng vẫn buộc cắt hình phải có điểm cắt voice. Sai
một từ trong ngữ cảnh, hoặc voice đọc liền, làm bỏ qua cả mép hình có thể
căn được. Speed merge còn có thể giảm số đoạn hình. Đây là lỗi phân chia
đơn vị dựng, không thể sửa chỉ bằng giảm marker.

## Thay đổi

- Có kế hoạch hình riêng `srt-cue-picture-v1`. Ranh giới nguồn lấy từ hai cue
  SRT kề nhau; ranh giới đích lấy từ mép từ DTW đã qua guard nguyên cue và
  ánh xạ A2 thật. Một cue có đủ bằng chứng vẫn có thể cung cấp mép bên cạnh
  cue chưa xác minh. Không nội suy word timing để cấp quyền cắt.
- Hình/A1 chia thêm bên trong nhóm đã có; A2/caption map/gap/đuôi giữ nguyên.
  Frame nguồn và output phải phủ đúng parent, anchor phải khớp voice map.
  Nếu mép từ trùng đuôi clip/chapter và không còn frame voice phía sau,
  giữ nhóm đã có và tiếp tục; không báo lỗi mapping chỉ vì không thể chia thêm.
  Khoảng không lời nguồn từ ngưỡng đã lưu tiếp tục theo cơ chế gap riêng.
- Quyền cắt voice nhận thêm DTW nguyên cue: đủ timing, tỷ lệ exact ít nhất
  85%, từ đầu/cuối exact, cùng chapter, nguồn duy nhất, không trim inPoint.
  Vẫn cần silence đo được >=0,12 giây và biên bảo vệ0,04; không cắt qua lời
  thêm. Ngữ cảnh tám từ cũ giữ nguyên và ưu tiên khi đã hợp lệ.
- Speed merge giữ mọi cue picture; additive DTW bảo vệ metadata. Executor
  direct/staged dùng cùng kế hoạch hình, giữ kế hoạch A2 riêng.
- Chỉ phục hồi chữ SRT raw-cell khi toàn bộ từ nguồn xuất hiện liên tiếp,
  exact100% trong DTW độc lập, cùng vùng/chapter, primary xác định cùng câu,
  không số mâu thuẫn/lời dư/nguồn trùng/lấn cell kế bên. Lưu chữ primary gốc.
  Caption-only không được thêm quyền cut/omission từ việc giữ chữ.
- Tốc độ retime hình đúng kế hoạch chỉ là chẩn đoán; không tạo marker dư chỉ
  vì vượt khoảng cảnh báo. Native speed không đọc được/sai kế hoạch vẫn có
  marker, kể cả khi nằm trong khoảng. Chính sách legacy giữ nguyên.

## Kết quả ngoại tuyến

Alien chạy đủ bốn stage shipping trên SRT/ba MP3 thật với geometry lịch sử:

| Đo | 2.20.85 | 2.20.86 |
|---|---:|---:|
| Đoạn hình | 158 | 302 |
| Đoạn voice | 158 | 234 |
| Mép voice có proof | 155 | 231 |
| Điểm cắt chỉ hình thêm | 0 | 68 |
| Cue SRT giữ đầy đủ | 280/319 | 286/319 |
| Caption cuối | 695 | 695 |
| Vị trí review dự kiến | 74 | 62 |

Sáu cue phục hồi là2,175,240,281,282,289; mọi chữ cell khác giữ nguyên.
Không bỏ hình nguồn/voice frame hoặc thêm omission; bảy SRT/MP3 giữ hash.
232/269 cell manual có timing DTW, còn37 cell ước lượng trong17 khối;
25 vùng timing,31 vùng chữ,4 DTW ngoài proxy và7 gap tạo67 issue/62 vị trí.
Đây là vùng cần xem lại, không phải số lỗi đã nghe xác nhận. Marker tốc độ
native chưa biết trước; planned retime đúng không tự tạo thêm speed marker.

Fit84 cue exact nguyên câu trên cùng DTW dùng dựng mốc: sai lệch tâm cue
median0,085→0,062s; p950,671→0,163s; max1,156→0,236s. Đây là fit diagnostic,
không phải bộ gold độc lập hay bằng chứng nghe/playback. Không diễn giải
thành độ chính xác recognition hoặc native đã đạt.

Island chuẩn giữ30/30 cue/66 caption,27 gap,125 frame tại gap đã báo;
fixture SRT cố ý103 giữ lời thật102/65 caption. Ca27/199 giữ identity cũ.

## Hồi quy và đường đã rà

[Cue picture](../../../tests/unit/Test-CuePicturePlan.ps1) tái hiện cue chạm nhau,
không dấu kết câu, voice liền; guard nguyên cue/silence/chapter/trim/duplicate,
phục hồi chữ thật và từ chối estimated/thiếu từ/lời dư/số mâu thuẫn/overlap.
[Shipping planner](../../../tests/unit/Test-AutoEditAcousticPartitions.ps1) tái hiện
manual không có silence: A2 một nhóm, hình ba nhóm, gap nguồn không bị nuốt;
speed merge giữ mốc. [Native mock](../../../tests/unit/diagnostic-executor.test.js)
kiểm direct/baseline/fast/no-delay giống từng call/report, V1/A1 chia gấp đôi
trong khi A2 giữ nguyên, lỗi plan bị chặn trước mutation và speed lỗi vẫn báo.
Full suite:71 nhóm/149 PS, `-NoWindowsIntegration`; package/source parity và
20 Node suite trên payload là kiểm tự động, không phải nghiệm thu native.

Rà legacy/per-cue helper, manual/raw-DTW/nguyên-cue, normal có timing thật,
additive DTW, speed merge, direct/diagnostic, review/ownership/reconciliation,
caption-only, strict omission và trimmed fallback. Strict omission hiện giữ
kế hoạch riêng, không bật picture refinement; caption-only không đổi quyền.
Không đổi model ASR, threshold hoặc saved settings, không thao tác project.

Native import/razor/retime, playback, độ khớp hình/voice/caption và marker còn
**pending người dùng chạy thử**. Không Save/Undo hoặc đóng ép Premiere/helper.
