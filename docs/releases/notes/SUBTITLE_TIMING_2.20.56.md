# Premiere Voice Sync 2.20.56 — ưu tiên giữ chữ SRT khi nhận diện gần khớp

Chỉ tạo subtitle trước đây có thể thay cả câu SRT bằng chữ tự nhận diện dù máy
chỉ bỏ sót một từ. Bản này giữ chữ SRT khi ít nhất 80% từ khớp chính xác, chỉ
thiếu/khác tối đa hai từ, có mốc đầu/cuối khớp và timestamp hợp lệ.

Nếu thiếu timing một vài từ ở giữa, phải còn khoảng giữa các từ đã nhận diện;
không tạo timestamp giả cho từ thiếu. Cue được giữ có marker yêu cầu nghe lại
chữ/timing, chưa được coi là DTW đã xác minh. Câu lặp mơ hồ, mất đầu/đuôi,
khác nhiều chữ, có lời nói thêm hoặc chỗ nối sát sau cắt vẫn xử lý thận trọng.
Điều kiện Auto edit xóa hình và bộ chứng minh voice đã bỏ nội dung giữ nguyên.

Không thể phân biệt chắc chắn mọi lỗi ASR với voice thực sự thay/cắt một hoặc
hai từ giữa câu nhưng vẫn để khoảng timing phù hợp. Cần nghe lại marker này.
Marker bổ sung nay phân biệt cue SRT chưa xác minh với lời nói tại vùng chưa
được SRT khớp bao phủ. Cài đặt không tự sửa caption/marker đã có trong project.

Mã nguồn đã đạt 47 nhóm hồi quy, parse 116 script PowerShell; sáu nhóm tích hợp
Windows được runner bỏ qua. Có ca thiếu một/hai từ, thay từ, giữ chữ qua bước
tạo caption, cắt thật, câu lặp, lời nói thêm, nhiều nguồn và timing hỏng. Đây
là kiểm fixture/VM, chưa nghiệm thu nhận diện hoặc dựng subtitle trong Premiere.

Kế thừa nối nhiều SRT và cơ chế đối chiếu marker của 2.20.55. Khi thử, dùng
sequence thử, kiểm panel hiện 2.20.56, chọn đúng SRT/audio rồi nghe lại các cue
được giữ và marker. Không tự điều khiển Premiere, Undo hoặc Save project.

Cài bằng Setup-Panel.cmd khi Premiere đã đóng. Dữ liệu/cache/model/jobs/backups
được giữ nguyên khi cập nhật.

## Đóng gói và cài đặt đã kiểm chứng — 17/10/2026

Đã tạo `dist/Premiere-Voice-Sync-2.20.56-Panel.zip`, **488.755.183 byte**
(466,11 MiB), SHA256:

`2B7ADE447FDB7C212A52C340F6AD8E97D7E24AC7D01C3596889BDDD140E10BAE`

Đọc và đối chiếu đủ 71 entry ZIP (70 payload và manifest checksum); runtime
khớp mã nguồn. Chín bộ kiểm VM bằng runtime trong gói và bốn bộ kiểm engine
bằng thư viện sao chép nguyên byte từ gói đều đạt. Kiểm fixture đóng gói,
cài/gỡ, rollback và registry đạt. Sau khi đổi số phiên bản, kiểm repository/UI/
workflow metrics đạt; 47 nhóm hồi quy/116 script đã đạt trước bước đổi số phiên bản.

So với gói 2.20.55, engine subtitle thay `CaptionOnly.ps1`, `SubtitleTiming.ps1`
và `run-captions.ps1`; panel thay main/manifest/index, tài liệu và helper/lock
do compiler dựng lại từ mã C# không đổi. `ReferenceAlignment.ps1`,
`run-alignment.ps1`, host và executor giữ nguyên hash; điều kiện xóa hình không đổi.

Cài thật từ 2.20.55 khi Premiere/helper đã đóng: **62/62 file panel** khớp gói,
**1.568 file dữ liệu/24 thư mục** trong LocalAppData/PremiereVoiceSync giữ nguyên
hash/cấu trúc. Registry CEP không đổi; bộ cài dùng SkipRegistry và giữ kiểm tra
process. Shortcut thông báo và helper-lock được xác minh; không chạy helper.

Bằng chứng cài đặt:
`dist/_installation-2.20.56-20261017T031253Z/verified.json`. Panel cũ được sao
lưu và kiểm hash đầy đủ tại `previous-panel` cùng thư mục trước khi cập nhật.
Kiểm gói tại `.tmp-subtitle-release/package-verified.json`,
`package-tests.log`, `package-engine-tests.log`, `installer-tests.log` và
`changed-package-files.json` trong cùng thư mục.

ZIP giữ nguyên sau cài; phần bằng chứng này được bổ sung vào tài liệu repository.
Không mở/đóng Premiere hoặc thao tác timeline, Play, Undo, Save, caption/marker
trong project. Nghiệm thu bằng audio thật và trong Premiere vẫn chờ người dùng.
