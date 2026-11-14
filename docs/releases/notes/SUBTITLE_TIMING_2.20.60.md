# Premiere Voice Sync 2.20.60 — bỏ marker số và chặn chữ thừa ở biên SRT

## Lỗi đã xác nhận trên project được lưu

Lượt chạy 2.20.59 ngày 17/10/2026, 14:47–14:52 tạo 675 caption và 11 marker. Đọc bản project Final được lưu lúc 14:57:46 xác nhận 9 marker timing số và 2 marker nhận diện bổ sung. Chỉ đọc file, không điều khiển Premiere hay sửa project.

- Caption 661, 1111,500–1113,467 giây: “– một giấc mộng dài giữa vũ trụ vô tận.”, thuộc SRT 287.
- Caption 662, 1113,467–1113,800 giây: “tật.”. Đây là đuôi cùng câu được ASR ngữ cảnh đọc thành “vô tật.”. Bộ loại ngữ cảnh yêu cầu khớp nguyên văn 4–8 từ, nên không nhận ra đuôi câu SRT có một từ nghe sai. Từ này lọt vào vùng nhận diện bổ sung và được thêm lần nữa.
- Marker 1113,467 giây và 1116,600 giây đều ghi các cue SRT 288, 289, 290, 292–296. Đây là danh sách ứng viên chưa xác minh của một vùng rộng; không chứng minh toàn bộ các cue đó bị thiếu tại cả hai marker. Marker sau nằm ở lời cảm ơn/hội viên/Super Thanks, khác nội dung SRT nguồn.

## Thay đổi

Không tạo marker “Chưa xác minh timing của số” trong cả hai chế độ; vẫn giữ kết quả tinh chỉnh số trong báo cáo/log dạng thông tin, không dùng riêng kết quả này để báo hoàn tất cần kiểm tra.

Bộ loại ngữ cảnh nhận ra tối đa một từ gần chính tả/dấu trong một neo 4–8 từ của câu SRT liền kề đã được chọn; những từ còn lại phải khớp, neo phải duy nhất và gần biên. Câu lặp mơ hồ hoặc từ không liên quan không được cắt bỏ. Nếu có một từ thật sự thêm sau câu đã đủ, từ đó vẫn được giữ. Dùng biên caption đã phục hồi và đúng nguồn audio để tìm hàng xóm, tránh dùng nhầm biên cũ trước DTW.

Khi toàn bộ cửa sổ bổ sung chỉ chứa ngữ cảnh của hai câu SRT đã có, ghi nhận vùng đã được ngữ cảnh bao phủ; không thêm chữ hoặc tạo marker báo thiếu lời. Không thay chữ SRT và không sửa điều kiện Auto edit cho phép bỏ hình.

Marker bổ sung ghi số caption cuối, trích nội dung tự nhận diện và đặt tại phạm vi caption thực có chữ; không liệt kê danh sách cue SRT ứng viên như một lỗi nội dung đã xác nhận. Khoảng trống trước/sau phần cảm ơn không bị gộp vào vùng marker có chữ.

## Kiểm chứng

Phát lại cùng cache nhận diện thực của lượt native: mã cũ giữ khoảng 2,500–3,08775 giây trong cửa sổ ngữ cảnh và sinh “tật.”; mã mới nhận ra hai câu liền kề, giới hạn cả hai biên tại 3,010 giây, không còn chữ bổ sung. Cache phần cảm ơn vẫn giữ 75 từ, gồm Super Thanks/Stickers/Chat. Đây là phát lại cache/timestamp cấp segment, không phải nhận diện DTW mới hoặc playback trong Premiere.

Bằng chứng đọc project/cache: `.tmp-supplement-tail-2.20.60/summary.json`, `tail-replay.json`, `captions.json`, `markers.json`. Kiểm hồi quy mới gồm biến thể đuôi câu, lời thêm thật, từ khác nghĩa, câu lặp, biên overlay, vùng chỉ chứa ngữ cảnh, giữ outro và marker trích caption.

Bộ hồi quy đạt 50 nhóm, parse 120 script PowerShell; sáu nhóm Windows integration được runner bỏ qua. Sau thay đổi cuối về khoảng trống giữa hai neo, hai nhóm context boundary/recognition safety và phát lại cache đều đạt. Log `.tmp-supplement-tail-2.20.60/suite-final.log`. Gói khớp nguồn, kiểm đủ ZIP/allowlist/checksum, 12 bộ VM chạy với mã của gói đạt; bằng chứng `package-verified.json`, `package-tests.log` cùng thư mục. So 2.20.59 chỉ đổi engine subtitle và marker/log; host/engine Auto edit không đổi.

ZIP SHA256: `CD3998D8DB7BE4CA0177C7B37CAB04376F486BAB8157067EDB6ED719104F9275`. Mục kết quả này được bổ sung vào tài liệu repository sau đóng gói; không sửa ZIP đã kiểm.

Project hiện có giữ nguyên; cài đặt không tự sửa caption/marker đã tạo. Cần chạy lại tạo subtitle để áp dụng quy tắc mới rồi nghe lại điểm nối và outro trước khi lưu.

Đã cài 2.20.60 từ 2.20.59 lúc 15:09 ngày 17/10/2026 (UTC+7): 62/62 file panel đúng checksum, giữ nguyên 3.157 file dữ liệu/22 thư mục và registry CEP. Sao lưu panel cũ; bằng chứng `dist/_installation-2.20.60-20261017T080904Z/verified.json`. Không mở/đóng Premiere/helper hoặc sửa project. Chưa có lượt chạy native 2.20.60.
