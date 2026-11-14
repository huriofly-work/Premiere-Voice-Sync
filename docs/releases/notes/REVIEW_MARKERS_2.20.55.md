# Premiere Voice Sync 2.20.55 — đối chiếu marker theo từng nguồn

Bản này giữ marker clip cũ trong lúc dựng. Sau khi có vị trí cuối, tool giữ marker còn đúng, cập nhật hoặc tạo phần thiếu, đọc lại kết quả rồi mới dọn phần thừa. Marker kiểm tra trên thước timeline dùng chung nguyên tắc, vẫn có hệ tọa độ và dấu sở hữu riêng.

## Hành vi

- Chạy lại cùng dữ liệu không nhân đôi marker hoặc ghi lại nội dung đã đúng. Cảnh báo giống nhau trên cùng một vùng nguồn dùng chung được gộp thành một marker clip.
- Chỉ thay marker Comment nhận diện đúng của tool trong vùng xử lý; giữ marker thủ công, marker khác loại, khác chức năng và ngoài vùng.
- Kiểm lại dữ liệu sau cập nhật và sau xóa. Nếu lỗi giữa chừng, thử phục hồi riêng dữ liệu marker của nhóm đó; thông báo nêu rõ khi chưa phục hồi đầy đủ. Không tự Undo timeline, Save hoặc chạy lại.
- Tạm dừng/hủy diễn ra ngoài bước cập nhật một nhóm nguồn, kể cả no-delay. Nhóm hoàn tất được giữ; nhóm chưa cập nhật vẫn còn marker cũ.
- Marker nguồn bị sửa sau lúc chuẩn bị được phát hiện trước khi cập nhật nhóm đó. Nếu lỗi dựng xảy ra trước bước ghi marker, marker clip cũ được giữ.
- Lỗi riêng màu vẫn được báo riêng. Khi không đọc được màu cũ, tool giữ màu của marker tái sử dụng để tránh thay đổi không thể phục hồi.

Marker clip vẫn thuộc ProjectItem nguồn: cùng media/vùng nguồn ở sequence khác có thể cùng thấy marker. Đây không phải cơ chế marker riêng theo sequence. Khôi phục marker đã xóa có thể tạo GUID mới; không bảo đảm phục hồi qua sự cố đóng Premiere hoặc mất điện.

## Kiểm chứng và phạm vi

Mã nguồn đã đạt 46 nhóm hồi quy, parse 115 script PowerShell; sáu nhóm Windows integration được runner bỏ qua. Có kiểm lỗi ghi metadata, create/delete ném lỗi sau mutation, xóa báo thành công nhưng không xóa, phục hồi không đầy đủ, marker thủ công, thời lượng marker, nguồn dùng chung, vị trí nguồn bị làm tròn, hủy giữa hai nhóm nguồn và parity direct/baseline/fast/no-delay. Chi tiết kỹ thuật ở `docs/reviews/MARKER_RECONCILIATION_2026-10-17.md` trong repository.

Chưa nghiệm thu marker hiển thị/màu, Preview/Play, Undo hoặc Save trong Premiere thật. Khi thử, dùng project thử và kiểm marker clip cùng marker trên thước timeline; kiểm cả nguồn dùng chung giữa hai sequence, chạy lại cùng dữ liệu và tạm dừng/hủy. Project không tự lưu.

## Cập nhật

Lưu công việc và đóng Premiere trước khi cài bằng `Setup-Panel.cmd`. Mở lại **Window > Extensions (Legacy) > Premiere Voice Sync**, kiểm phiên bản **2.20.55**. Cài đặt không tự sửa marker trong project đã lưu; hành vi mới áp dụng khi chạy chức năng tương ứng.

Kế thừa đầy đủ chức năng nối nhiều SRT và các bản sửa 2.20.54. Bản phát hành vẫn chờ nghiệm thu native.

## Đóng gói và cài đặt đã kiểm chứng

Ngày 17/10/2026 đã đóng gói và cài **2.20.55** từ **2.20.54**. ZIP có 70 file payload cùng SHA256SUMS.txt; toàn bộ 71 entry được đọc từ ZIP và đối chiếu hash với staging. Runtime của gói khớp mã nguồn. Chín bộ kiểm VM chạy lại bằng chính host/main/runtime trong gói đều đạt. Kiểm fixture đóng gói, cài/gỡ, rollback và registry cũng đạt; registry fixture cần chạy ngoài sandbox.

Gói: `dist/Premiere-Voice-Sync-2.20.55-Panel.zip`, **488.754.148 byte** (466,11 MiB), SHA256:

`755B4ED90A0604D87226FCEE14EB4AD6D8287D649D753F471EA43186141175E9`

So với gói 2.20.54, runtime thay ba file main/host/executor, hai file phiên bản và hai file helper/lock do compiler dựng lại helper từ mã C# không đổi. Bộ cài và thuật toán engine giữ nguyên theo hash.

Cài thật: **62/62 file panel** khớp gói; **1.568 file dữ liệu/24 thư mục** trong LocalAppData/PremiereVoiceSync giữ nguyên theo hash/cấu trúc. Registry CEP giữ nguyên, bộ cài chạy với SkipRegistry và giữ kiểm tra process. Shortcut thông báo và hash helper đã được xác minh. Premiere/helper đã đóng khi cài; không mở/đóng app hoặc thao tác project.

Bằng chứng: `dist/_installation-2.20.55-20261017T025331Z/verified.json`; panel 2.20.54 được sao lưu đầy đủ tại `previous-panel` trong cùng thư mục. Kiểm ZIP/runtime tại `.tmp-marker-reconcile/package-verified.json` và `.tmp-marker-reconcile/package-tests-2.20.55.log`. Gói ZIP giữ nguyên sau cài; phần bằng chứng cài đặt này được bổ sung vào tài liệu repository.

Các kiểm trên không xác nhận hiển thị marker, màu, playback, Undo hoặc Save trong Premiere thật; nghiệm thu native vẫn chờ người dùng.
