# Premiere Voice Sync 2.20.62 — nhận ra câu thì giữ chữ SRT

Theo yêu cầu người dùng, bỏ marker “Cần đối chiếu số đọc”. Khi ngữ cảnh đã xác định được câu SRT, số ASR khác cách ghi không tạo marker hoặc cảnh báo hoàn tất riêng. Dữ liệu đối chiếu vẫn được giữ trong báo cáo và thống kê log dạng thông tin. Câu đã nhận ra, giữ chữ SRT khớp phần lớn cũng không bị báo lại là “cue SRT cần nghe lại”.

Cơ chế căn thời gian có sẵn được giữ nguyên: `Set-PvsSubtitleWordBoundaries` dùng mốc từ bên trái (`DtwBoundaryStart`), tìm đáy năng lượng gần mốc này hoặc khoảng nghỉ đo được, tránh để đỉnh attention của chữ số kéo ranh giới vào giữa cách đọc số nhiều âm tiết. Nếu không đo được ranh giới tốt hơn thì giữ bằng chứng mốc hiện có. Có kiểm hồi quy riêng cho từ đứng trước số và đáy âm thanh; điều này không phải cam kết mọi cue luôn chính xác nếu chưa nghe lại.

Không thay engine, chính sách nhận dạng câu, cơ chế bổ sung lời ngoài SRT, phục hồi câu cuối Short, timing hoặc host Premiere. Bản sửa chỉ đổi lớp thông báo/marker của panel. Marker cũ trong project được đối soát ở lần chạy workflow sau, trong phạm vi được xử lý; cài đặt không tự sửa project.

Kiểm tra đạt 5 nhóm PowerShell và 2 nhóm JavaScript, gồm marker ở cả hai workflow, cảnh báo timing độc lập, luồng tạo subtitle với khác biệt số mà không có cảnh báo hoàn tất, lưu báo cáo chẩn đoán và các kiểm căn số/ranh giới từ trước số. 46 file engine của bản phát hành và host khớp checksum với 2.20.61. Bằng chứng `.tmp-number-marker-2.20.62/checks.log`, `runtime-comparison.json`.

Gói đã kiểm đủ 70 file payload, 71 mục ZIP/checksum và khớp nguồn runtime. 12 bộ VM chạy với mã đóng gói đạt, gồm luồng hoàn tất không còn cảnh báo đối chiếu số. Bằng chứng `.tmp-number-marker-2.20.62/package-verified.json`, `package-tests.log`. ZIP SHA256: `C22D0FAF52D99C52DB45B478715652A73C8DF8D2E809438879D3E7F88AC3B51F`. Kết quả kiểm gói/cài đặt được bổ sung vào tài liệu repository sau build; ZIP đã kiểm được giữ nguyên.

Lần cài đầu dừng trước khi sửa file vì Premiere/helper đang mở. Người dùng đã xác nhận đóng cả hai và yêu cầu cài tiếp. Chưa có playback native của bản mới.

Đã cài 2.20.62 từ 2.20.61 ngày 17/10/2026 lúc 15:59 (UTC+7): 62/62 file panel đúng checksum; 3.534 file dữ liệu, 22 thư mục và registry CEP giữ nguyên. Sao lưu panel cũ tại `dist/_installation-2.20.62-20261017T085900Z/previous-panel`; bằng chứng `verified.json` cùng thư mục. Không điều khiển Premiere hoặc sửa project.
