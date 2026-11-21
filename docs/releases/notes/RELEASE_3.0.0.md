# 3.0.0: marker gọn trong ba loại, gắn một lần sau hậu kiểm

Bản ứng viên, chưa công bố. 2.20.98 vẫn là stable/Latest. Bản đầu ngày 20/11/2026 đã chạy danh sách nghiệm thu trên Premiere; các lỗi tìm thấy đã sửa (mục "Sửa sau lượt nghiệm thu" bên dưới) và gói được build lại ngày 21/11/2026.

## Trước khi dùng: không tương thích với bản cũ

3.0.0 không đọc dữ liệu hay bản cài của các bản trước (quyết định ngày 19/11/2026):
- **Marker 2.20.x không được nhận ra.** Trước lần chạy đầu bằng 3.0.0, xóa tay mọi marker có tên bắt đầu bằng `VOICE SYNC - ` trên file voice, nest V1 và thước timeline, hoặc dùng bản sao template sạch. Nếu không xóa, marker cũ vẫn nằm đó, và marker mới phải tránh chỗ marker cũ nên có thể lệch sang frame bên cạnh hoặc không gắn được.
- **Không chuyển đổi bản cài từ bộ cài EXE cũ.** Ai còn bản EXE cũ thì gỡ bản đó trước.
- **Thiết lập tốc độ đã lưu được giữ nguyên.** Giá trị 110 không còn tự đổi thành 130.

## Thay đổi

### Ba loại marker

| Tên trong Premiere | Gắn ở | Dùng cho |
|---|---|---|
| `VOICE SYNC - Video` | nest V1 (hiện trên clip hình) | tốc độ ngoài ngưỡng, gộp hình, V1/A1 lệch vị trí hoặc lệch mép, chưa xác minh liên kết, không đọc được tốc độ, hở hình, độ dài sau đổi tốc độ chưa khớp, đuôi hình/tiếng lệch |
| `VOICE SYNC - Voice` | file voice (hiện trên clip A2) | voice căn chưa chắc, voice lệch vị trí kế hoạch |
| `VOICE SYNC - Caption` | file voice | chữ khác SRT, timing ước lượng, cần nghe lại; Dựng theo voice và Tạo phụ đề mỗi chức năng có bộ riêng |

Marker vẫn là một điểm ở giữa đoạn cảnh báo. Các cảnh báo cùng loại trên một đoạn được gộp thành một marker, còn marker khác loại đặt sát bên nhau. Ghi chú vẫn ngắn, dạng "Cue N: …".

### Gắn marker một lần, sau hậu kiểm

Thứ tự trong Dựng theo voice:
1. dựng V1–A1;
2. dựng voice A2;
3. **Tạo caption**;
4. **Hậu kiểm** một lần: kiểm timeline, caption, file tạm, phần ngoài phạm vi, và gom mọi cảnh báo;
5. **Gắn marker** một lần cho mỗi nguồn, nest V1 trước rồi đến file voice;
6. **Báo cáo**.

- Bỏ việc ghi marker trước khi cắt, cùng toàn bộ phần dời lại và khôi phục đi kèm. Lỗi của 2.20.94 và 2.20.97 nằm ở chính phần này.
- Bước Gắn marker luôn dọn toàn bộ marker cũ của tool trên nguồn đó. Marker đã đúng chỗ thì giữ nguyên, nên chạy lại không phải ghi gì.
- Cảnh báo không gắn được được liệt kê trong mục chưa gắn của panel.
- Không tạo được caption thì vẫn gắn marker Video và Voice, chỉ bỏ marker Caption, và panel nêu lý do.
- Không còn marker nào trên thước timeline.

### Dừng và lỗi

- Khi Dừng hoặc gặp lỗi, timeline được giữ đến bước đã làm.
- Marker chỉ gắn ở bước cuối. Dừng trước bước Gắn marker thì marker trên file voice và nest vẫn là của lần chạy trước, và thông báo nói rõ điều này.
- Yêu cầu Dừng đến khi bước cuối đã dựng xong thì panel báo hoàn tất và giữ kết quả.
- Câu lỗi luôn bắt đầu bằng lỗi gốc.
- Sau khi Dừng hoặc lỗi, panel không chặn lượt chạy sau, trên mọi sequence. Tạo phụ đề tự khôi phục mute, enable và In/Out; nếu không khôi phục được thì chỉ cảnh báo.

### Sửa sau lượt nghiệm thu ngày 20/11/2026

- **Đoạn hình giảm tốc bị hụt** (mục 5, voice 90%): Premiere giới hạn đoạn nest chạy chậm ở "cuối nest − điểm vào nguồn" và cắt luôn Out, nên một đoạn giữa thiếu 56 frame. Tool giờ khôi phục Out rồi mới đặt điểm cuối, cho mọi đoạn. Cách sửa đã được thử trực tiếp trên Premiere 26.2.2 (#102).
- **Marker ở chỗ hai đoạn giao bằng nhau** (mục 7, 25 fps): chọn đoạn chứa điểm giữa cảnh báo, không có thì đoạn trước (#103).
- **Câu báo khi lời nhận diện không khớp SRT** (mục 4): câu tiếng Việt dễ hiểu thay cho lỗi kỹ thuật (#105).
- **Kiểm đầu vào một lần** (mục 6): Dựng theo voice từ chối voice chạy ngược, Time Remapping, voice hoặc V1 bị cắt phần đầu, đổi tốc độ V1, voice chồng nhau, file mất…, và báo đủ từng lý do kèm cách sửa. Hỗ trợ đầu vào đã chỉnh để dành cho bản sau. Caption Track có sẵn không còn bị chặn (#109).
- **Tạo phụ đề** bỏ các lượt đọc đầu vào trùng lặp và đường xử lý cũ (#111).

## Đã kiểm

- **Marker cuối so với bản cũ.** Thử mô phỏng 42 fixture × 4 kiểu chạy: trước khi đổi tên và loại marker, bộ marker cuối khớp bản cũ (bỏ qua GUID). Lệnh dựng timeline không đổi.
- **Chạy lại.** Mọi fixture chạy lại đều ghi 0 marker.
- **Frame rate và tốc độ voice.** Mô phỏng ở 23,976, 24, 25, 29,97 và 60 fps, với voice 90%, 100% và 150%: marker nằm đúng giữa đoạn.
- **Clip chạy ngược, Time Remapping.** Dựng theo voice từ chối ở bước kiểm đầu vào, trước khi sửa timeline, và nêu đúng lý do.
- **Lượt nghiệm thu trên Premiere ngày 20/11/2026** (bản đầu): mục 1–4 đạt; mục 5, 6, 7 tìm ra các lỗi đã sửa ở trên.
- **Dừng hoặc lỗi giữa chừng.** Ma trận ngắt ở từng bước có 0 ca tệ hơn trước. Khi ghi lỗi giữa chừng, tool bù lại được cả 172/172 lần lỗi tiêm vào, không còn marker ghi dở.
- **Bộ kiểm thử đầy đủ.** Gồm cả sáu nhóm tích hợp Windows: cài, gỡ, rollback, registry, shortcut, thông báo.

## Còn chờ

- **Kiểm lại trên Premiere:** các mục bị ảnh hưởng theo [danh sách nghiệm thu 3.0.0](../../TESTING.md#kiểm-lại-sau-các-bản-sửa-ngày-20112026). Đã có sẵn hai xác nhận của user ngày 19/11: marker trên nest đi theo clip, và mép caption được nới đúng.
- **Thời gian dựng:** lượt 20/11 trên Sông Congo mất 53,1 s cho các bước timeline (2.20.98: 62,1 s); gắn 19 marker lên nest mất 18,3 s, sẽ xem xét tăng tốc ở bản sau.
- **Không làm trong bản này:**
  - Setup/Remove trên tài khoản Windows sạch, quét antivirus;
  - ký số panel;
  - giới hạn của Whisper Turbo.
- **Cài đặt:** đóng Premiere và helper thông báo bằng tay trước khi cài.
