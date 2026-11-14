# 2.20.46 — phục hồi timing tham chiếu trước khi nhận diện bổ sung

## Lỗi và nguyên nhân

Lượt Chỉ tạo subtitle 14:55:25–14:56:58 ngày 16/10/2026, bản 2.20.45, dừng ở caption-alignment. Log không có giai đoạn caption-import. Mã lỗi người dùng: `CAPTION_OVERLAP_TIMING_UNSAFE:240:9`.

Tái hiện đúng mã lỗi bằng JSON nhận diện gốc còn trong cache và audio dựng ngoại tuyến từ 30 clip A2, 877,5 giây, của project đã lưu `Virus gây hai bệnh_1.prproj`. Harness đọc backend CUDA đã cấu hình, đặt cache/file tạm trong workspace, không mở hoặc điều khiển Premiere. Audio dựng dùng vị trí/In/Out của clip, chưa áp dụng effect/routing/mix Premiere; JSON nhận diện ban đầu được phát lại từ cache, các cửa sổ còn lại chạy Whisper thật. Đây không phải nghiệm thu audio xuất trực tiếp từ Premiere.

Cue tham chiếu 114 ban đầu chỉ có timing đến từ “khí” ở 411,3175 giây, thiếu mép của “rất mạnh”. Bước bổ sung đã nhận diện lại khoảng tưởng còn thiếu và tạo chữ `ZMIGHT!` (kết quả ASR chưa xác minh). Sau đó DTW phục hồi cả câu đến 411,648687 giây, nhưng caption bổ sung vẫn tồn tại. Hai caption chồng 9 frame ở khoảng 06:51; bộ chặn đã dừng đúng. Bước hòa giải mốc câu cũ không tác động vào overlay timing theo từ mà splitter sử dụng.

## Thay đổi

- Hoàn tất retry và overlay DTW cho cue tham chiếu trước `Complete-PvsSubtitleReference`.
- Khi tìm vùng còn thiếu, dùng bản sao với mép caption đã phục hồi. Giữ đối tượng đầu vào, chữ và timecode SRT nguồn. Không nhận diện lại phần lời đã được phục hồi; phần ngoài SRT/CTA và vùng chưa khớp vẫn được bổ sung.
- Kiểm mép phục hồi hữu hạn, đúng thứ tự, nằm trong nguồn và không chồng cue kế bên. Không nới ngưỡng `Add-PvsCaptionEdgePadding` hoặc âm thầm cắt/chia đôi đoạn chồng.
- Sau khi chèn caption bổ sung và đánh số lại, ánh xạ báo cáo cue DTW sang số cuối cùng.
- Không sửa planner Auto edit, host Premiere, Save/Undo hoặc các điều khiển workflow.

## Bằng chứng

Lượt phát lại trước sửa ghi đúng `CAPTION_OVERLAP_TIMING_UNSAFE:240:9`; sau sửa cùng đầu vào ghi `CAPTIONS_READY`, xuất 507 caption. Cue tham chiếu 114 kết thúc 411,648687 giây; câu kế tiếp bắt đầu 412,876125 giây, không còn caption bổ sung trùng. Lời kêu gọi cuối video vẫn được nhận diện bổ sung.

Đầu ra ngoại tuyến còn 3 vùng timing ước lượng và 2 cue cần kiểm mép DTW; kết quả và UI tiếp tục báo các vị trí này. Không coi kiểm cấu trúc là bằng chứng đúng từng từ hoặc nhận diện chính xác toàn bài.

Ca hồi quy mới kiểm phục hồi từ cuối không kích hoạt nhận diện trùng, giữ CTA ngoài tham chiếu, bảo toàn đầu vào, giữ chỉ số tham chiếu và từ chối overlay NaN/Infinity/vượt nguồn/đảo/chồng. Bộ hồi quy gồm 42 nhóm đạt: 36 nhóm đầu của runner và 6 nhóm từ UiContract trở đi sau khi đồng bộ nhãn phiên bản log. Sáu nhóm Windows integration của `-NoWindowsIntegration` không chạy. Test bảo vệ junction cần chạy ngoài sandbox; ca thất bại do giới hạn sandbox đã chạy lại thành công. Parse lại toàn bộ script sau sửa cuối. Kiểm đầu ra độc lập: 507 cue liên tục, một dòng/cue, tối đa 42 ký tự, không chồng/đảo/vượt phạm vi; giữ câu “rất mạnh” và CTA cuối. Không nghiệm thu import/Play/Save trong Premiere.
