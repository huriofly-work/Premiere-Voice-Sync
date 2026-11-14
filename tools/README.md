# Công cụ developer

Chạy từ thư mục gốc project. Các công cụ này không nằm trong gói runtime;
đọc [quy tắc khả thi](../docs/DEVELOPMENT_FEASIBILITY_POLICY.md) trước khi gọi
lệnh có tác động lên host.

| Công cụ | Dùng để |
| --- | --- |
| `setup-engine.ps1` | Nhập runtime đã duyệt (bin + model) vào `extension/engine/runtime`. |
| `Verify-GitHubDistribution.ps1` | Kiểm metadata phát hành, và gói ZIP khi truyền `-PackagePath`. |
| `Build-DiagnosticExecutor.js` | Sinh lại `extension/jsx/diagnostic-executor.jsx`; `--check` kiểm parity. |
| `diagnostic-fast-support.jsx` | Nguồn hỗ trợ cho executor sinh ra ở trên. |
| `Generate-CaptionLexicon.ps1` | Sinh lại danh sách cụm từ caption tiếng Việt. |
| `Inspect-WhisperJson.ps1` | Xem nhanh JSON đầu ra của whisper.cpp. |

Các tool chọn model ASR, benchmark và cue-first đã gỡ ngày 13/11/2026 sau khi
chốt Whisper large-v3-turbo. Ghi output riêng dưới `_local/`; giữ audio,
reference, jobs, models và cache ngoài Git. Không gọi diagnostic native chỉ để
dọn project. Xem thêm [kiểm thử](../docs/TESTING.md).
