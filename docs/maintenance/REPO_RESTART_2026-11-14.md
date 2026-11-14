# Khởi tạo lại repository ngày 14/11/2026

Repo `huriofly-work/Premiere-Voice-Sync` được tạo mới, bắt đầu bằng một commit
snapshot của mã nguồn tại thời điểm chuyển. Repo cũ cùng tên đã bị xoá.

## Lý do

Repo cũ chuyển sang public ngày 13/11/2026. Lịch sử Git của nó có thông tin cá
nhân của người duy trì trong metadata commit và trong nội dung file cũ. Viết lại
lịch sử ngay trong repo đó là không đủ, vì GitHub vẫn giữ commit cũ qua các ref
của pull request. Repo mới chỉ chứa nội dung hiện hành đã được rà soát.

## Những gì thay đổi

- Lịch sử commit, issue, pull request và 24 release cũ không còn trên GitHub.
  Bản sao lưu đầy đủ (Git mirror, metadata issue/PR/release và file release đã
  kiểm SHA-256) do người duy trì giữ ngoài GitHub.
- Tài liệu vẫn nhắc số issue/PR và SHA commit cũ dưới dạng chữ, đánh dấu
  "repo cũ"; các số đó không trỏ tới issue/PR của repo mới.
- `docs/releases/*.json` và các receipt lịch sử giữ nguyên byte theo
  [quy định bằng chứng](../history/README.md).
- Chưa có release trên repo mới. Bản đầu tiên sẽ phát hành theo
  [quy trình phân phối](../GITHUB_DISTRIBUTION.md).

## Không thay đổi

Mã nguồn, runtime lock, bộ cài và trạng thái nghiệm thu: 2.20.25 là bản đã
nghiệm thu; 2.20.90 còn chờ nghiệm thu Premiere. Việc chuyển repo không phải
nghiệm thu native.
