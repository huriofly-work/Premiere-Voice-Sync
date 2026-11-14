# Premiere Voice Sync 2.20.63 — nguồn SRT và ngôn ngữ voice

## Thay đổi

Trước đây ô nối SRT độc lập với lựa chọn một SRT/tự nhận diện không SRT nên giao diện có thể hiện hai lựa chọn trái nhau. Khi bật nối, panel nay ẩn và khóa lựa chọn đơn; danh sách nối là nguồn dùng cho job. Tắt nối khôi phục lựa chọn trước đó, kể cả tự nhận diện không SRT đã chọn thủ công. Lựa chọn nối và danh sách vẫn riêng cho từng workflow.

Bật nối tự thêm toàn bộ SRT từ lần quét Project gần nhất, khử trùng đường dẫn và xếp theo tên có thứ tự số. Nếu lượt quét đầu đang chạy, danh sách được thêm khi quét xong, kể cả đã đổi tab. Cập nhật đầu vào không ghi đè danh sách đã sắp/bỏ bớt. Bấm Thêm tất cả SRT Project để thêm lại các file còn thiếu; file ngoài có thể thêm riêng. Hãy kiểm thứ tự và bỏ các bản dịch/phiên bản không cần. Quy tắc timestamp giữ nguyên như 2.20.54.

Luồng Dựng theo voice trước đây cố định Whisper ở tiếng Việt. Nay có Ngôn ngữ voice, mặc định tiếng Việt, lưu riêng với Chỉ tạo subtitle. Job chốt ngôn ngữ và truyền qua nhận diện chính, CPU fallback, cửa sổ phục hồi và DTW/caption retry. Chọn Tự nhận diện sẽ truyền auto cho Whisper; các bước đọc số riêng tiếng Việt chỉ bật khi chọn vi. SRT phải cùng ngôn ngữ với voice, tool không dịch. Bộ căn câu vẫn kiểm bằng chứng trước khi sửa timeline; việc có lựa chọn ngôn ngữ không chứng minh mọi ngôn ngữ đã được nghiệm thu với media thật.

## Kiểm chứng

Các kiểm hồi quy bao gồm: tự thêm tất cả SRT, khử trùng đường dẫn, thứ tự số, sắp/bỏ rồi cập nhật, ASR-only → nối → ASR-only, hai tab độc lập, lượt quét hoàn tất sau đổi tab, job dùng bản nối, ngôn ngữ en/auto trong job và chặn ngôn ngữ không hợp lệ. Kiểm PowerShell chạy các bộ tạo tham số nhận diện của mã thật cho vi/en/auto/zh; kiểm DTW qua các chapter với ngôn ngữ đã chọn. Đây là kiểm tự động với fixture, chưa phải playback/native Premiere.

Đã kiểm 52 nhóm hồi quy (45 nhóm trước lỗi metadata phiên bản, sau đó sửa metadata và chạy đạt nhóm UI cùng sáu nhóm còn lại); sáu nhóm Windows integration được runner bỏ qua. Kiểm browser fixture đạt ở 320/385/560 px cho cả hai workflow, gồm bật nối tự thêm hai SRT Project, thêm file ngoài, khử trùng, ẩn/khóa lựa chọn đơn, tắt nối khôi phục ASR-only, ngôn ngữ voice và không tràn ngang. Bằng chứng tại .tmp-srt-language-2.20.63 (verification.json, suite-verified.log, ui.log và thư mục ui).

Gói `dist/Premiere-Voice-Sync-2.20.63-Panel.zip` đã kiểm 70 file payload/71 mục ZIP cùng checksum và khớp nguồn runtime; 15 bộ VM chạy với mã đóng gói đạt. SHA256: `DE9B33F166AC2CB64BD0BFE2BD2B312E70CAD691C2FFF56A4D09799CE37FE8A8`. Bằng chứng `package-verified.json` và `package-tests.log` trong thư mục kiểm ở trên. Tài liệu repository được bổ sung sau build; ZIP đã kiểm được giữ nguyên.

Lần cài đầu dừng trước khi thay panel vì phát hiện Adobe Premiere Pro đang mở. Sau đó người dùng xác nhận đã lưu và đóng Premiere để cài tiếp. Bằng chứng `install.log`.
Đã cài 2.20.63 từ 2.20.62 ngày 17/10/2026 lúc 16:18 (UTC+7), sau khi người dùng xác nhận đã lưu và đóng Premiere. 62/62 file panel khớp checksum; 3.567 file dữ liệu, 22 thư mục và registry CEP giữ nguyên. Bản panel trước được sao lưu tại `dist/_installation-2.20.63-20261017T091823Z/previous-panel`; bằng chứng `verified.json` cùng thư mục và `.tmp-srt-language-2.20.63/install-resume.log`. Không điều khiển Premiere hoặc sửa project; chưa nghiệm thu native/playback.