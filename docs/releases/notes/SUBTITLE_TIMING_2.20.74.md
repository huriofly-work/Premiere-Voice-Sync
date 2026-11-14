# Premiere Voice Sync 2.20.74 — giữ SRT qua dạng chữ ASR và ngữ cảnh ngắn

## Thay đổi runtime

Nhánh chỉ tạo subtitle có hai sửa trong `CaptionOnly.ps1`:

1. Khi projection cũ và nhánh dấu/đơn vị bị từ chối, thử lexical view cho
   đơn vị ASR viết gộp như `km2`, `000km2`. Xét toàn bộ ngữ cảnh số/đơn vị
   từ ASR gốc, kiểm riêng chiều đơn vị để không nhầm km/km2/m2. Giữ chữ SRT;
   không chia một span thành nhiều timestamp giả. Anchor từ một token gộp
   được đánh dấu timing ước lượng và giữ nguồn timing.
2. Nếu retry câu riêng thất bại, tiếng Việt được thử một lượt với tối đa
   2,5s audio ngữ cảnh mỗi bên. Cần thấy duy nhất cả hai hàng xóm đã giữ,
   chỉ lấy phần trong khoảng gốc và xét lại bằng cùng ngưỡng nhận câu.
   Không dùng SRT làm prompt. Một connector ngắn như “Quan trọng hơn” cần
   câu liền kề tiếp theo đã xác minh mạnh để làm đủ anchor, không đứng một
   mình. Giới hạn 32 lượt/180s gồm cả retry có ngữ cảnh.

Không đổi ngưỡng nhận câu, bằng chứng bỏ/cắt hình của Auto edit, timing dùng
chung, marker đối chiếu cách đọc số đã bỏ hoặc cấu hình model đang phát hành.
Không phục hồi câu đã cắt, câu tương lai, câu lặp mơ hồ hoặc bỏ lời thêm
trước/sau câu để ép SRT khớp. Job/cache/model và project nguồn được giữ.

## Kết quả kiểm

| Audio Nam Cực dựng lại, cùng 766,5s | 2.20.73 | 2.20.74 |
|---|---|---|
| Small — model production | 253/255, thiếu 138/207 | **255/255**, 468 caption |
| Medium — đối chiếu thử, chưa phát hành | 252/255, thiếu 43/138/232 | **254/255**, còn 138, 466 caption |

Đã kiểm độc lập toàn chuỗi token SRT ở caption cuối theo thứ tự nguồn, qua
các chỗ tách câu. Không có ASR/lời lặp xen vào những câu đã giữ. Riêng cue
138 của Medium còn ASR giống baseline. Cue 43/232 giữ lại đúng số và đơn vị
SRT, lỗi lặp “chiếm” ở ranh giới đã hết. Không cue đã giữ nào bị mất.

Lời cảm ơn/hội viên ngoài SRT giống baseline của từng model; Medium vẫn có
đầu câu bị cụt như trước nên chưa đủ điều kiện thay Small. Cả hai lượt CUDA,
không fallback CPU, timing caption dương/không overlap. Small vẫn hai vùng
timing ước lượng; Medium tám (trước mười). Các số này không chứng minh ranh
giới từng từ đã chính xác khi nghe.

- Hai test mới tái hiện thất bại trước sửa, kiểm final SRT, raw ASR bất biến,
  offset/chapter, chiều đơn vị, lời thêm thật, ngữ cảnh thiếu, timing lỗi và
  không nâng timing ước lượng thành bằng chứng DTW.
- Bộ hồi quy local đạt 57 nhóm, parse 128 PowerShell scripts, loại sáu nhóm
  integration Windows bên ngoài. Test bảo mật junction cần chạy ngoài sandbox;
  lỗi quyền ở lượt thử đầu không phải lỗi thuật toán.
- Phát lại lịch sử giữ đúng 27 câu ý thức (1–9, 14–31), 199 câu của ca nhãn
  chữ cái, không phục hồi câu đã cắt/tương lai. Hash project và SRT gốc không đổi.
- [Số đo kiểm đầu ra](../../benchmarks/SRT_REGRESSION_2.20.74.json).

## Bộ nhớ của project và giới hạn

Thêm [sổ hồi quy](../../REGRESSION_MEMORY.md) và `AGENTS.md` để các lượt sửa sau đọc
được nguyên nhân, điều kiện cần giữ, test và phần còn mở từ repository.
Không phụ thuộc duy nhất vào lịch sử chat hay ghi nhớ cá nhân của trợ lý.

Audio dựng lại không gồm mix/effect native và không tái hiện đúng sáu cue
thiếu của lượt Premiere cũ. **Nghiệm thu import/nghe/timing/marker trong
Premiere vẫn chờ**, issue #14 chưa đóng. Phát hành là prerelease, giữ Small;
không tích hợp Qwen/Medium hoặc router đa ngôn ngữ trong đợt sửa này.
