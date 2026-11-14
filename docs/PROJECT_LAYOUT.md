# Cấu trúc project

| Đường dẫn | Vai trò |
| --- | --- |
| `extension/` | Runtime được cài vào CEP. Giữ nguyên cấu trúc và cơ chế vận hành. |
| `installer/` | Đóng gói, kiểm checksum, cài/gỡ và rollback. |
| `tests/unit/`, `tests/manual/` | Hồi quy tự động và kiểm nghiệm thu có fixture/chỉ định. |
| `tools/` | Công cụ developer; xem [mục lục](../tools/README.md). |
| `docs/` | Hướng dẫn và quy tắc hiện hành; [mục lục đầy đủ](README.md). |
| `docs/releases/notes/` | Ghi chú từng phiên bản; JSON phát hành vẫn ở `docs/releases/`. |
| `docs/reviews/` | Báo cáo rà soát theo ngày. |
| `docs/history/`, `docs/acceptance/`, `docs/benchmarks/` | Receipt/inventory/nghiệm thu/số đo gốc. Không sửa receipt lịch sử để phản ánh đường dẫn mới. |
| `dist/` | Gói 2.20.88 và stable 2.20.25, kèm thư mục giải nén/checksum tương ứng. Bị loại khỏi Git. |
| `dist/archive/releases/<version>/` | Các gói cũ, sidecar và staging cùng phiên bản, giữ byte và quan hệ cùng thư mục. |
| `dist/archive/installations/` | Receipt cài đặt và bản sao panel trước đây. |
| `dist/archive/diagnostics/` | Script/log/ảnh và các fixture đóng gói cũ. |
| `_local/archive/2026-10-23/` | Các workspace/log thử nghiệm đã gom, giữ tên gốc theo từng đợt. Bị loại khỏi Git. |
| `_local/maintenance/2026-10-23/` | Snapshot Git, bản sao hai local edits, bảng di chuyển và kết quả kiểm lần dọn này. |

## Dữ liệu dev có thể xóa (từ 13/11/2026)

Trước đây `.tmp-asr-model-benchmark-20261018/`, `.tmp-cue-first-tests/` và
`_local/archive/` phải giữ vì chứa model, corpus và bằng chứng cho việc chọn
model ASR và nghiên cứu cue-first. Cả hai việc đã đóng: model là Whisper
large-v3-turbo, cue-first và Qwen đã bỏ. Từ ngày này các cây `.tmp*` và `_local/`
là dữ liệu dev có thể xóa, theo ba điều kiện: user xác nhận đúng danh sách; không
tiến trình hay phiên nào đang dùng; không đi xuyên junction/symlink khi xóa (một
số cây có link, và `Remove-Item -Recurse` của PowerShell 5.1 có thể xóa qua
junction). Runtime trong `extension/engine/runtime/`, gói trong `dist/` và dữ liệu
người dùng đã cài không thuộc nhóm này.

Workspace thử nghiệm mới nên nằm dưới `_local/`, dùng TEMP/TMP riêng trong
project khi cần.

## Tra và phục hồi

[Bảng chuyển tài liệu](maintenance/DOCUMENT_RELOCATIONS_2026-10-23.json) ánh xạ
114 đường dẫn và hash trước/sau. Link Markdown hiện hành đã đổi theo vị trí mới.
Các path/hash trong JSON lịch sử vẫn mô tả commit gốc; dùng bảng tra hoặc
`git show <commit>:<path-cu>` để đối chiếu.

Manifest `_local/maintenance/2026-10-23/local-archive-<batch>.json` ghi từng
`from`, `to`, số file/byte và toàn bộ metadata tương đối trước/sau. Đường dẫn
private trong report cũ tra qua manifest này. Muốn khôi phục một cây, bảo đảm
không có tiến trình đang dùng nó và đường dẫn cũ chưa tồn tại, rồi dùng
`Move-Item -LiteralPath <to> -Destination <from>` với đường dẫn tuyệt đối nằm
trong project. Không ghi đè cây mới hoặc chỉnh lại nội dung receipt gốc.

[Báo cáo bảo trì](maintenance/README.md) ghi tag phục hồi các nhánh Git.
Không di chuyển hay xóa release asset đã công bố, không rewrite Git history,
không merge/promote stable hoặc cài runtime trong lần sắp xếp này.
