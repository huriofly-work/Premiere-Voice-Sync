# Voice đã lược bỏ nội dung — 2.20.51

## Hành vi

SRT gốc có A → B → C → D → E, voice còn A → C → E:

- **Chỉ tạo subtitle:** giữ chữ A, C, E từ SRT, căn theo voice hiện tại; không thêm B, D và không chèn khoảng trống thay chúng. Không sửa hình/audio.
- **Auto edit:** dùng timestamp gốc của B, D để bỏ đúng vùng V1/A1 linked tương ứng; giữ hình còn lại, căn thời lượng theo voice và tạo caption A, C, E. Không thêm điểm cắt voice chỉ vì hình có đoạn bị bỏ.

Đối chiếu dựa trên nội dung và thứ tự, không dùng timestamp SRT gốc để đoán vị trí voice đã cắt. Các khoảng không lời ngoài vùng subtitle bị bỏ vẫn theo quy tắc dựng hiện có.

## Bằng chứng trước khi bỏ hình

`Resolve-PvsEditedReference` dùng chung cho hai luồng trong `ReferenceAlignment.ps1`:

1. Tìm các cue còn khớp trọn chữ, có timestamp hợp lệ, không chồng/lặp hoặc đảo thứ tự. Tối thiểu tám từ thuộc các mốc neo có ít nhất bốn từ.
2. Gom cue chưa tìm thấy thành từng cụm. Nhận diện lại vùng nối có câu trước/sau (hoặc mép audio), tối đa 30 giây; không đưa chữ SRT vào prompt của lượt kiểm tra này.
3. Nếu nhận diện lại thấy trọn các câu bị bỏ sót ban đầu, phục hồi chúng. Nếu chỉ thấy đúng các câu neo còn lại, ghi vùng nghi đã lược bỏ cùng bằng chứng. Câu lặp hoặc nhận diện khác nội dung vẫn là chưa xác minh.
4. Auto edit chỉ nhận kết quả có toàn bộ lời nhận diện được giải thích bởi cue giữ lại, toàn bộ cue được phân loại, thứ tự và timing hợp lệ. Kết quả còn mơ hồ dừng trước khi đổi timeline.

Đây là bằng chứng từ hai lượt nhận diện, không phải thông tin lịch sử edit hay chứng minh tuyệt đối. Chưa có nghiệm thu trên cặp voice đã cắt/SRT thật của người dùng.

## Cắt giữa cue, câu lặp và ASR sai

- Subtitle giữ các cue khớp trọn chữ; vùng chưa khớp dùng nhận diện thực tế và có nhật ký/cảnh báo. Không đưa nguyên câu SRT lên chỉ vì còn khớp một phần số từ.
- Auto edit chưa tự suy ra timestamp hình cho phần bị cắt ngay trong một cue: SRT chỉ có mốc đầu/cuối cue, không cung cấp mốc hình cho từng từ. Khi phát hiện nhưng chưa phân loại được vùng này, tác vụ dừng để kiểm tra hoặc chỉnh SRT.
- Câu lặp có nhiều vị trí phù hợp, đoạn neo quá ngắn, cửa sổ kiểm tra quá dài hoặc các mốc neo thuộc hai chapter khác nhau không tự cấp quyền bỏ hình.
- Số viết khác cách đọc, biến thể chính tả và lỗi ASR có thể khiến đường xử lý voice đã cắt dừng thận trọng. Không nới điều kiện xóa để tăng tỷ lệ chạy qua.
- Ràng buộc Auto edit hiện có về template, nhóm voice, tốc độ và media In vẫn được áp dụng. Không bổ sung hỗ trợ timeline clip có media In khác 0 ở thay đổi này.

## Kế hoạch và thực thi

`New-PvsEditedSourceMap` lưu rõ các khoảng hình giữ/bỏ trên lưới frame. Planner, DTW và cân bằng speed lập kế hoạch trên hệ tọa độ liên tục của hình còn lại. `editedSourceMap` giữ ánh xạ ngược về hình nguồn; alignment vẫn lưu timestamp SRT gốc. Chỉ bản sao cue dùng trong planner được chuyển tọa độ.

Host xác minh tổng các vùng giữ và bỏ phủ đúng một lần toàn bộ hình nguồn, rồi mở rộng kế hoạch về các lát nguồn thật. Nếu một đoạn voice không có điểm cắt an toàn, hình có thể có nhiều lát nhưng A2 vẫn là một đoạn. Thời lượng từng lát hình được phân bổ theo phép retime của nhóm, giống chính sách dựng theo nhóm hiện có; không khẳng định mỗi mép hình là mốc từng từ đã đo âm học.

V1/A1 được razor tại các biên cần thiết. Sau khi đọc lại và kiểm tra toàn bộ các cặp lát hình/audio, host bỏ đúng các cặp thuộc vùng đã ghi bằng chứng, dùng `remove(false, false)` và kiểm tra chúng thực sự đã biến mất. Sau đó mới retime/di chuyển hình và xử lý voice. Bộ thực thi theo đợt có ranh giới dừng riêng trước/giữa các lần bỏ cặp. Cancel giữ kết quả đang có để kiểm tra; không Save/Undo tự động.

Các bất biến vẫn được kiểm tra: toàn bộ hình giữ lại xuất hiện đúng một lần; không mất/trùng frame voice; V1/A1 linked khớp nhau; output không có khe hở; caption không chứa câu đã bỏ; các element ngoài phạm vi được bảo toàn. Kế hoạch cũ không có `editedSourceMap` đi qua đường cũ.

## Kiểm chứng

- `Test-EditedReference.ps1`: nhiều cụm bị bỏ, giữ chữ/offset, phục hồi ASR sót, retry trống/sai/lỗi, subtitle không có câu thừa và phần câu dùng ASR.
- `Test-EditedPlanner.ps1` và `Check-EditedSourcePlan.js`: planner thật, caption đầu ra, không chèn pause cho cue đã bỏ, bảo toàn kế hoạch DTW, cân bằng speed và mở rộng bản đồ nguồn tại 30/29.97 fps. FFmpeg được thay bằng fixture không có silence.
- `diagnostic-executor.test.js`: bỏ nhiều vùng/đầu/cuối V1/A1, giữ voice liền khi cần, ba chế độ lịch chạy, từ chối map hỏng trước mutation, Cancel trước xóa. Các lời gọi native và báo cáo của hai bộ thực thi phải giống nhau.

Bộ hồi quy `Run-Tests.ps1 -NoWindowsIntegration` đạt 45 nhóm và parse 114 script; sáu nhóm Windows integration được bỏ qua theo runner. TEMP/TMP/LOCALAPPDATA riêng, log `.tmp-edited-suite/final-suite.log`. Bản mới bổ sung marker tại vùng nối cần nghe lại, được ánh xạ theo timeline đầu ra của từng luồng.

Những kiểm tra trên là unit/fixture/VM; không xác nhận hành vi `remove`, razor, retime, caption import, Play hay Save trong Premiere thật.

## Cài đặt ngày 16/10/2026

Đã nâng panel từ 2.20.50 lên 2.20.51 khi Premiere và helper thông báo đã đóng. Kiểm tra đủ 61 file cài đặt đúng checksum; 923 file dữ liệu/24 thư mục giữ nguyên từng hash và cấu trúc. Registry CEP không đổi; shortcut thông báo đúng identity. Có bản sao panel cũ trong `dist/_installation-2.20.51-20261016-174846/previous-panel` và bằng chứng `verified.json` cùng thư mục. Không mở/đóng Premiere, chạy helper hoặc thao tác project. Nghiệm thu native còn chờ người dùng.

Gói đã cài có SHA256 `1674AD52753A916464CF0ABD602C716860F67F2C7A1190785047F55A4505EEFD`; gói ZIP là bản cố định trước cài đặt, tài liệu trạng thái cài trong workspace được cập nhật sau.

Khi kiểm trong Premiere: xác nhận panel hiện 2.20.51, thử Chỉ tạo subtitle với voice đã bỏ nhiều câu và SRT gốc, nghe lại các marker nối; sau đó thử Auto edit trên sequence thử có hình khớp timestamp SRT. Xác minh phần bị bỏ trên V1/A1, phần voice còn lại, caption, Play và Save. Không coi cài thành công là nghiệm thu các bước này.
