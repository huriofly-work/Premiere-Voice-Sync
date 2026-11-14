# Premiere Voice Sync

Panel CEP cho Adobe Premiere Pro 26 trên Windows, gồm **Dựng theo voice** và **Chỉ tạo subtitle**.

| Luồng | Trạng thái và tài liệu |
| --- | --- |
| Bản phát hành | Repository được khởi tạo lại ngày 14/11/2026 nên chưa có bản tải trên trang [Releases](https://github.com/huriofly-work/Premiere-Voice-Sync/releases); bản đầu tiên sẽ phát hành sau. [Lý do khởi tạo lại](docs/maintenance/REPO_RESTART_2026-11-14.md). |
| Bản đã kiểm trước đây | 2.20.25 đã nghiệm thu trên máy người dùng; 2.20.90 (Whisper large-v3-turbo thay Small, ZIP khoảng 1,6 GB, CPU chậm hơn khoảng 2 lần) còn chờ nghiệm thu Premiere, xem [phạm vi và giới hạn](docs/releases/notes/ASR_TURBO_2.20.90.md). |
| Hướng phát triển | Big update làm từng bước trên engine và panel 2.20.x, ra từng bản nhỏ. Nghiên cứu cue-first, chọn model ASR và Qwen đã đóng ngày 13/11/2026; [lý do và phần đã gỡ](docs/REGRESSION_MEMORY.md). |

[Hướng dẫn sử dụng](docs/USER_GUIDE.md) · [Mục lục tài liệu](docs/README.md) · [Cấu trúc project](docs/PROJECT_LAYOUT.md) · [Lịch sử thay đổi](CHANGELOG.md)

Ghi chú từng phiên bản và bằng chứng trước đây được giữ trong [tổng quan đến 2.20.88](docs/releases/OVERVIEW_THROUGH_2.20.88.md) và [mục lục phát hành](docs/releases/README.md).

Panel CEP cho Adobe Premiere Pro 26 trên Windows. Có hai chức năng: **Dựng theo voice** và **Chỉ tạo subtitle**.

[Hướng dẫn sử dụng đầy đủ](docs/USER_GUIDE.md) gồm cài đặt, hai chức năng, CPU/GPU, dữ liệu và lưu ý khi chia sẻ bộ cài. Hướng dẫn subtitle cũng có ngay trong panel.

## Tạo subtitle độc lập

1. Mở sequence bất kỳ, chọn **Chỉ tạo subtitle** và nguồn audio: tất cả track đang bật, các track chỉ định hoặc đúng các clip audio đang chọn.
2. Chọn phạm vi **Toàn sequence**, **Theo khoảng thời gian của clip đang chọn** hoặc **Theo In/Out**; nguồn clip audio dùng chính phạm vi của chúng. Chọn ngôn ngữ lời nói và giới hạn ký tự.
3. Để SRT trống để tự nhận diện nội dung, hoặc chọn SRT đúng lời nói (có thể là SRT toàn video). Tool tự tìm phần SRT khớp audio được chọn, giữ chữ và căn lại timestamp.
4. Bấm **Tạo subtitle**. Tool thêm Caption Track mới đúng vị trí và giữ nguyên video/audio. Nghe lại rồi tự lưu project.

Audio xuất qua Premiere theo nguồn/phạm vi đã chốt. Trong chế độ track chỉ định, gợi ý A2 có clip enabled giao phạm vi, hoặc track đầu tiên phù hợp; lựa chọn thủ công được giữ khi nguồn trống và lỗi được báo rõ. Nhiều nguồn được phối theo timeline; clip mode loại clip không chọn trên cùng track. Vùng rời nhau giữ đúng vị trí. Chế độ này không cần V1/A1 linked, SRT tiếng Việt hoặc template sạch. Subtitle giữ nguyên ngôn ngữ lời nói; không dịch. File tạm được dọn sau tác vụ, trừ job còn nhật ký cần khôi phục.

## Đầu vào

- Sequence template sạch đang mở.
- V1: một nested video chính; A1: audio gốc đã linked với V1.
- A2: các chapter voice tiếng Việt đặt liên tiếp theo thứ tự. CTA cách nhóm voice chính trên 2 giây được giữ nguyên.
- Một file SRT cùng ngôn ngữ đã dùng để tạo voice (hoặc danh sách SRT nối).

Không cần SRT ngôn ngữ gốc, không cần chọn thư mục làm việc và không cần xuất XML.

## Cách dùng

1. Mở sequence template sạch.
2. Chọn SRT trong selectbox được tự động lấy từ Project, hoặc bấm **Chọn ngoài** để thêm một file từ ổ đĩa vào chính selectbox đó.
3. Mở **Tùy chỉnh theo video** nếu cần; giữ mặc định nếu chưa chắc.
4. Bấm **Phân tích và dựng tự động** rồi xác nhận. Đầu vào được kiểm lại khi chạy, không cần đọc/chẩn đoán trước.

**Cập nhật đầu vào** dùng sau khi đổi sequence/chọn clip/import SRT; nó cập nhật danh sách SRT và thông tin timeline cho chế độ đang mở. **Chẩn đoán đầu vào** nằm trong **Hỗ trợ và nhật ký**, chỉ dành cho việc tìm nguyên nhân không chạy được, không sửa timeline. Lý do dùng CPU vẫn hiện ngay ngoài mục thiết lập GPU.

Panel tự nhận diện voice, lập kế hoạch câu với điểm cắt DTW an toàn, gộp hình một lần nếu vượt ngưỡng tốc độ, dựng trực tiếp theo đợt nhanh, tạo caption và hậu kiểm. Các cơ chế này là mặc định, không cần bật ô thử nghiệm. Project không tự lưu.

Panel là nơi xem kết quả và phê duyệt. Toast Windows nhắc khi tác vụ chạy nền hoàn tất hoặc cần xử lý; bấm để quay lại panel. Âm thanh có tùy chọn lưu trong Thiết lập. Xem [phạm vi và nghiệm thu 2.20.71](docs/releases/notes/NOTIFICATIONS_2.20.71.md); nghiệm thu workflow trong Premiere vẫn được ghi riêng.

Marker: đỏ = quá nhanh; cam = quá chậm; vàng = căn voice cần nghe lại; xanh dương = hình đã gộp, speed trong ngưỡng. Nhóm gộp còn vượt dùng đỏ/cam và ghi rõ trong ghi chú. Chỉ dọn marker cũ nhận diện được của tool, không dựa màu để xóa.

## Logic dựng

- Timestamp gốc của SRT tham chiếu xác định vùng hình nguồn.
- Whisper căn lời Việt với voice để tạo timestamp mới và caption.
- Caption dài được tách thành các đoạn một dòng, mặc định tối đa 42 ký tự. Thứ tự chọn điểm chia là dấu câu, khoảng nghỉ hơi có xác nhận trên voice, rồi mới đến khoảng trắng. Nếu đoạn cuối chỉ còn vài từ, hai caption cuối được cân lại để tránh một từ đứng riêng. Điểm chuyển được lượng tử hóa theo frame.
- Nếu Whisper bỏ sót một block cue ngắn, engine nhận diện lại riêng vùng đó giữa các mốc neo tin cậy cùng chapter. Chỉ dùng kết quả có đủ timestamp từng từ và độ khớp cao; không remap các cue đã khớp. Planner có thể nội suy mép cue trong khoảng hợp lệ để dựng, nhưng không dùng nội suy để chia caption thiếu word timestamp; cue nội suy có marker trên A2, và tác vụ dừng trước khi đổi timeline nếu không đủ dữ liệu an toàn.
- Voice chỉ bị cắt tại silence an toàn giữa các câu hoàn chỉnh.
- Dấu chấm phẩy `;` được xem là dấu kết câu cùng với `.`, `?` và `!`.
- Khoảng subtitle dưới 1 giây được hấp thụ vào câu liền kề; từ 1 giây trở lên được giữ nguyên như đoạn không lời.
- Hình nguồn được dùng đầy đủ, trừ vùng SRT đã xác minh không còn trong voice; phần hình giữ lại được retime theo voice. Khoảng 70–130% mặc định dùng để chọn một cặp hình liền kề giúp giảm lệch tốc độ, không giới hạn speed. Mỗi đoạn chỉ gộp một lần, không gộp tiếp. A2/caption không gộp theo hình. Mọi đoạn hình đã gộp có marker; nếu vẫn ngoài ngưỡng thì ghi thêm cảnh báo.
- Executor cắt V1+A1 linked, kiểm tra khe hở hình theo frame và bảo toàn các element ngoài phạm vi.

Kết quả Whisper được cache theo file voice, kích thước, thời điểm sửa và model. Chạy lại cùng voice bỏ qua lượt nhận diện toàn file; nếu cache có vùng bị bỏ sót, engine vẫn nhận diện lại riêng vùng ngắn đó.

Mục **Tùy chỉnh theo video** chỉ hiển thị năm lựa chọn có ý nghĩa biên tập và có thể thay đổi theo từng video: ngưỡng cảnh báo chậm, ngưỡng cảnh báo nhanh, gap không lời tối thiểu, gap tách nhóm voice/CTA và số ký tự tối đa của mỗi caption.

Các ngưỡng silence, thời lượng silence an toàn, cửa sổ tìm ranh giới, confidence marker, dấu kết thúc câu, dung sai map voice, dung sai timeline, khe hở hình và cache Whisper được cố định trong thuật toán. Chúng không còn xuất hiện trên giao diện để tránh một thay đổi kỹ thuật làm hỏng timeline.

Executor không ghi `end/outPoint` trước hoặc sau `setSpeed`, nhờ đó clip giữ metadata nhất quán và có thể tiếp tục chỉnh bằng Rate Stretch Tool. Sau khi dựng, panel xóa master In/Out của nested ProjectItem để khi kéo nest sang sequence khác Premiere dùng toàn bộ video.

Planner quy đổi toàn bộ ranh giới nguồn, voice và timeline sang frame trước khi tính tốc độ. Executor 2.18 chỉ gọi `setSpeed` một lần cho mỗi TrackItem, với tỉ lệ chính xác lấy từ toàn bộ khoảng source chia cho duration đích. Premiere 26.2.2 có trường hợp riêng: slow-motion chạm đúng đuôi nested source đổi speed nhưng giữ duration cũ. Nếu và chỉ nếu cặp V1–A1 cuối gặp lỗi này, executor dùng `TrackItem.end` để đặt mép timeline theo frame đích. Fallback không ghi `outPoint`, không áp dụng cho các đoạn giữa và hậu kiểm bắt buộc cả V1 lẫn A1 phải hội tụ.

Engine tự phát hiện NVIDIA bằng `nvidia-smi` tại đường dẫn hệ thống đã biết. Backend CUDA có sẵn được kiểm hash và thử nhận diện trước khi sử dụng. Tải backend CUDA 12.4 từ whisper.cpp chỉ diễn ra khi người dùng bật **Cho phép tải backend GPU từ GitHub**; mặc định tắt trên máy mới. Backend CPU luôn được giữ lại; nếu không có NVIDIA, driver không tương thích, không có mạng, file GPU không hợp lệ hoặc GPU lỗi giữa tác vụ, chương trình dùng CPU và ghi lý do. Nút **Kiểm tra lại GPU** bỏ trạng thái probe cũ và thử lại.

Gói CUDA tải ở lần sử dụng đầu trên mỗi máy có dung lượng khoảng 678 MB và không nằm trong file ZIP của extension. Kết quả probe được cache theo GPU, driver, binary và model; những lần mở panel sau không phải nạp lại model để kiểm tra. Khi GPU lỗi giữa tác vụ, CUDA được tạm ngừng 24 giờ để tránh lặp lỗi và có thể được xác minh lại bằng `resolve-backend.ps1 -ForceProbe`.

Hậu kiểm đo khe hở giữa các clip, điểm kết thúc thực tế của V1/A1, duration và liên kết V1–A1 theo frame. Không so sánh `outPoint` trước–sau retime, vì Premiere biểu diễn lại thuộc tính này theo speed và chênh lệch đó không phải bằng chứng xén nguồn.

Marker tốc độ dùng metadata thực tế sau retime, gắn trên nguồn clip V1; marker căn voice gắn trên A2. Vị trí marker được kiểm theo khoảng source của đúng đoạn, không đặt trên toàn timeline. Trước dựng, tool dọn marker của nó trong vùng nguồn xử lý: tên có tiền tố `VOICE SYNC -` và tag `[PremiereVoiceSync:owned-marker:v1]`, hoặc đúng cả tên/mẫu ghi chú của bản cũ. Chỉ tiền tố tên chưa đủ để xóa. Marker thủ công, không chắc nguồn gốc hoặc ngoài vùng được giữ. Tag không phải chữ ký bảo mật; sao chép nguyên ghi chú/tên có thể bị nhận là marker tool. Marker thuộc ProjectItem nên các clip/sequence dùng chung nguồn có thể thấy cùng thay đổi. Bật **Timeline Settings > Show Clip Markers** nếu chưa thấy.

Phiên bản 2.19.1 ưu tiên đường dẫn voice Unicode đang tồn tại và chỉ sửa mojibake khi đường dẫn sau sửa thực sự tồn tại. Nếu không mở được voice để dò khoảng lặng, chương trình dừng với lỗi rõ ràng thay vì âm thầm gộp toàn bộ video thành một đoạn. Điểm cắt A2 chỉ được tạo khi vùng im kéo dài ít nhất 120 ms, nằm sát ranh giới nhận diện, còn biên an toàn 40 ms ở cả hai phía và chứa một frame Premiere hợp lệ. Ranh giới có độ tin cậy thấp hoặc không đạt đủ điều kiện sẽ được gộp để bảo toàn trọn câu. Nhật ký và hộp hoàn tất hiển thị riêng số câu theo dấu câu và số đoạn voice có điểm cắt an toàn.

Hậu kiểm va chạm V1 dùng ranh giới frame tuyệt đối. Một clip giữ nguyên bắt đầu đúng tại frame kết thúc mới của video được xem là tiếp giáp hợp lệ; chỉ khi nó bắt đầu sớm hơn ít nhất một frame chương trình mới báo overlap. Lỗi preflight xảy ra trước thao tác dựng không còn yêu cầu Undo.

Nếu video mới dài tới vị trí của một clip V1 nằm sau video chính, phiên bản 2.15 xem clip V1 sớm nhất đó là mốc bắt đầu của cụm outro. Toàn bộ clip video/audio bắt đầu từ mốc này trở đi được dời cùng một số frame để outro tiếp giáp với đuôi video mới. Nội dung, duration, speed và khoảng cách tương đối trong cụm outro không đổi; các clip bắt đầu trước mốc outro không bị dời. Mỗi TrackItem được đọc lại theo frame sau khi move và tác vụ dừng nếu Premiere không đặt nó đúng vị trí.

Voice mapping so sánh độc lập mép đầu và mép cuối của từng đoạn A2 với giới hạn cố định 2 frame cho mỗi mép. Không cộng hai sai số thành một giá trị chung; vì vậy trường hợp hai mép đều hợp lệ không còn bị báo lỗi giả. Nếu một mép thực sự vượt giới hạn, nhật ký ghi cue, sai số từng mép và clip gần nhất để chẩn đoán.

Planner 2.16 không còn coi `Chapter = -1` của cue thiếu timestamp là ranh giới chapter. Mọi mép caption sau căn chỉnh cũng được lượng tử hóa theo frame, tránh chồng lấn dưới một frame do làm tròn giây.

Caption Track vẫn được tạo từ SRT đã căn. SRT chỉ được import vào một bin tạm; sau khi `createCaptionTrack` thành công, bin tạm và ProjectItem SRT bị xóa. Phiên bản 2.18.1 không dựa vào giá trị trả về không ổn định của `deleteBin()`: chương trình kiểm tra `nodeId` của bin trong cây Project và số ProjectItem thực tế qua nhiều lần đọc DOM.

Caption dùng word timestamp thực tế. Dấu kết thúc câu là ranh giới tự nhiên; dấu phẩy/chấm phẩy/hai chấm được ưu tiên nhưng không bắt buộc tách thành mảnh 1–2 từ. Dấu hai chấm trong tên Latin như “Alien: Covenant” không tách tên phim. Sau đó ưu tiên nghỉ hơi thật và cuối cùng ranh giới từ; từ vựng offline giúp giữ cụm như “phá tung”, “cấm kỵ”, “tổng khối lượng”. Caption vẫn tối đa 42 ký tự mặc định và giữ đúng mốc đã căn, không nới thêm frame ở mép (từ 2.20.89), không chồng caption kề bên.

Với tiếng Việt, mọi cue có chữ số được kiểm tra bằng một lần nhận diện cửa sổ ngắn quanh cue, dùng gợi ý cách đọc số nhưng giữ nguyên số hiển thị. Timestamp mới chỉ được nhận khi chữ số khớp, đủ từ, thứ tự thời gian hợp lệ và có mốc lexical hai mép. Mốc riêng cho caption không đổi các điểm cắt, nhóm câu hay tốc độ video/voice. Không xác minh được thì giữ mốc cũ và báo cue cần nghe lại; không đoán timestamp từ độ dài chữ. Cách viết số có dấu phân cách dễ hiểu nhầm như “1.000” không tự đổi cách đọc trong gợi ý.

Cơ chế pause, trim và mượn/copy hình đã được loại bỏ. Workflow schema 8 không cho phép tạo visual fill, tránh hiện tượng TrackItem V1 không ổn định hoặc mất đoạn trên giao diện timeline.

Các giá trị nhập đều được kiểm tra kiểu số và miền hợp lệ trước khi phân tích. Tham số hậu kiểm chỉ quyết định đạt/không đạt, không thay đổi cách dồn clip trên timeline.

## Cài đặt

### Gói ZIP: Thiết lập panel / Gỡ panel

1. Đóng Adobe Premiere Pro.
2. Giải nén đầy đủ `Premiere-Voice-Sync-<phiên bản>-Panel.zip` tải từ trang Releases, sau khi đối chiếu SHA-256 với ghi chú Release.
3. Mở thư mục vừa giải nén, nhấp đúp **Setup-Panel.cmd** và chờ thông báo hoàn tất.
4. Mở Premiere Pro, sau đó vào `Window > Extensions (Legacy) > Premiere Voice Sync`.

Gói ZIP offline chứa sẵn Whisper CPU, FFmpeg, model và từ vựng caption. Script kiểm hash nội bộ rồi chép panel vào `%APPDATA%\Adobe\CEP\extensions\com.premierevoicesync.local`, bật `PlayerDebugMode` cho CSXS 12. Không cần quyền Administrator, Python hoặc module ngoài; không đăng ký Windows Installed apps và không tạo bộ cài EXE.

Nếu máy đang dùng bản EXE cũ của tool, thiết lập mới kiểm tra đúng tên/đường dẫn trước khi gỡ mục Installed apps và file uninstaller cũ, giữ cache/model/backend. Các file không thuộc tool được giữ nguyên. Đây là gói không đăng ký ứng dụng, không phải portable hoàn toàn: panel và dữ liệu vẫn nằm trong AppData. Giữ thư mục giải nén hoặc ZIP để dùng Remove-Panel.cmd; xóa gói ZIP không tự gỡ panel.

### Mã nguồn trong bản phân phối

ZIP giữ nguyên JavaScript giao diện, ExtendScript điều khiển Premiere, PowerShell engine và các thư viện script ở dạng đọc được. Quy trình build không mã hóa, làm rối, đóng gói thành `.pvsbin` hay tạo loader giải mã. Người dùng có thể kiểm tra trực tiếp mã đang được cài trong thư mục extension.

Gói phát hành vẫn không chứa lịch sử Git, file test và công cụ build vì các thành phần đó không cần thiết để extension hoạt động. Gói có kèm `THIRD_PARTY_NOTICES.md` liệt kê nguồn và giấy phép của FFmpeg, whisper.cpp, SDL2, model Whisper và danh sách cụm từ tiếng Việt, cùng toàn văn giấy phép GPL v3 của FFmpeg trong `licenses/GPL-3.0.txt`.

### Bản quyền

Repository được công khai để xem và kiểm tra mã nguồn. Mã của Premiere Voice Sync không kèm giấy phép mã nguồn mở: © huriofly-work, bảo lưu mọi quyền. Bạn được xem mã trên GitHub và dùng gói phát hành chính thức; muốn sao chép, sửa đổi hoặc phân phối lại mã thì cần xin phép trước. Các thành phần bên thứ ba trong gói giữ giấy phép riêng, xem [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Báo lỗ hổng bảo mật theo [hướng dẫn này](https://github.com/huriofly-work/Premiere-Voice-Sync/security/policy).

## Gỡ cài đặt sạch

1. Đóng Adobe Premiere Pro.
2. Mở thư mục gói ZIP đã giải nén.
3. Chạy **Remove-Panel.cmd**, đọc xác nhận rồi chọn **Y** để gỡ sạch.

Bộ gỡ chỉ xóa đúng extension ID `com.premierevoicesync.local` và vùng `%LOCALAPPDATA%\PremiereVoiceSync` sau khi kiểm tra danh tính/đường dẫn. Không dò xóa ID khác theo tên hiển thị và không xóa thư mục TEMP theo tiền tố. `PlayerDebugMode` được trả về trạng thái trước lần thiết lập đầu tiên nếu chưa bị người dùng/ứng dụng khác đổi. Whisper/FFmpeg của chương trình khác và thư mục ZIP giải nén được giữ nguyên. Bản EXE cũ cần chạy Setup-Panel.cmd để chuyển trước khi dùng script gỡ mới.

Model nhận diện là Whisper large-v3-turbo (khoảng 1,6 GB, nằm trong ZIP) từ 2.20.90; chạy CPU chậm hơn Small khoảng 2 lần nên máy NVIDIA nên dùng CUDA. Máy NVIDIA có thể cho phép tải thêm backend CUDA khoảng 678 MB. Chưa cho phép tải, không có NVIDIA hoặc CUDA không vượt qua kiểm tra thì dùng CPU và hiển thị lý do. Chưa có backend GPU đóng gói cho AMD/Intel.

Yêu cầu máy mới: Windows 10/11 x64 và Adobe Premiere Pro 26.x. Internet không cần thiết cho chế độ CPU hoặc quá trình cài offline; chỉ cần khi tự tải CUDA cho NVIDIA. Nếu mạng bị ngắt hoặc CUDA không tương thích, chương trình vẫn dùng CPU đã đóng gói sẵn.

## Thư mục dữ liệu và dọn file

Mã nguồn và gói cài đặt nằm hoàn toàn trong thư mục `Premiere Voice Sync`. Khi chạy, chương trình không tạo output hay cache cạnh SRT hoặc trong thư mục project video.

Dữ liệu lâu dài được gom vào `%LOCALAPPDATA%\PremiereVoiceSync`:

- `Backends`: backend CUDA đã cài tự động.
- `Models`: bản model có đường dẫn ASCII để công cụ native đọc ổn định.
- `Cache\Whisper`: kết quả nhận diện dùng lại để tăng tốc lần sau.
- `backend-state.json`: trạng thái CPU/GPU và lý do fallback gần nhất.

**Xóa cache nhận diện** trong Nhật ký kỹ thuật chỉ xóa `Cache\Whisper`, không xóa model/backend. **Xuất log đã che thông tin** lưu log panel tại thư mục người dùng chọn, che đường dẫn, tên sequence/media được biết, email và mẫu token GitHub; vẫn phải đọc lại trước khi chia sẻ. Không tự upload log.

Các thư mục job, WAV chuyển đổi, JSON alignment, edit plan và report trung gian chỉ tồn tại trong lúc chạy. Chúng được xóa bằng khối dọn dẹp bắt buộc khi tác vụ thành công hoặc phát sinh lỗi; các thư mục tạm sót do Premiere/Windows bị tắt đột ngột cũng được dọn tự động ở lần chạy sau.

Khởi động lại Premiere Pro và mở `Window > Extensions (Legacy) > Premiere Voice Sync`.

## Cấu trúc mã nguồn

- `extension`: duy nhất mã được cài vào Adobe CEP; cấu trúc thư mục này không đổi so với 2.19.1.
- `installer`: tạo ZIP và quản lý thiết lập/gỡ panel, chuyển từ bản EXE cũ.
- `tests/unit`: kiểm tra tự động, độc lập với project Premiere của người dùng.
- `tests/manual`: kiểm tra cần fixture media được chỉ định rõ ràng.
- `tools`: công cụ dành cho phát triển, không được đóng gói cho người dùng.
- `experiments`: thuật toán thử nghiệm, không được production import hoặc đóng gói.
- `docs`: kiến trúc, kiểm thử, phát hành và báo cáo rà soát.

## Kiểm thử

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Khi chỉ kiểm tra mã và dữ liệu, không gọi helper/registry/shortcut Windows, dùng `-NoWindowsIntegration`. Chế độ này vẫn chạy mock thông báo, kiểm schema C# thuần và kiểm planner/engine. Các nhóm tích hợp bị bỏ qua được in rõ, không được tính là đã đạt.

Bộ test trên kiểm tra mã nguồn, planner, giao diện và vòng đời bộ cài. Việc dựng thật trong Premiere vẫn phải nghiệm thu riêng theo `docs/TESTING.md`.

## Đóng gói

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\installer\build-release.ps1
```

Gói `Premiere-Voice-Sync-<VERSION>-Panel.zip` (theo file `VERSION`) được tạo trong `dist`, chứa một thư mục phiên bản duy nhất, Setup-Panel.cmd, Remove-Panel.cmd và HUONG_DAN_SU_DUNG.md. Có helper EXE nhỏ chỉ cho thông báo Windows và mở panel khi người dùng bấm; mã C# đi kèm. Không chứa EXE installer, test, downloads, VAD, ffprobe, pipeline XML hay code rehearsal cũ. Cache audio và log tự lưu được giữ nguyên. Auto edit mặc định không delay như baseline đã nghiệm thu. Xem [hướng dẫn sử dụng](docs/USER_GUIDE.md) và [đánh giá tăng tốc](docs/PERFORMANCE_REVIEW.md).

`build-release.ps1` sao chép nguyên mã nguồn vận hành vào vùng staging, kiểm tra không còn payload `.pvsbin`, rồi tính checksum và nén ZIP. Công cụ IExpress/Setup.exe đã được loại bỏ. Phát hành một ZIP và công bố SHA-256 trong ghi chú Release; người dùng không cần mang theo file checksum riêng.

Runtime cho developer phải được nhập từ bộ artifact đã duyệt đúng `runtime-lock.json`, không tự tải bản latest:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\setup-engine.ps1 -ArtifactsRoot <folder-containing-bin-and-models>
```

Setup chỉ dùng gói đã build đủ `SHA256SUMS.txt`; chạy Setup ngay từ checkout chưa build sẽ bị từ chối. Gói thiếu checksum, file thừa, hash sai hoặc đường dẫn liên kết bị từ chối trước khi thay panel. Cập nhật có rollback bản cũ nếu bước thay panel lỗi. Kiểm checksum nội bộ không chứng minh nguồn gốc nếu toàn gói bị thay thế: đối chiếu SHA-256 của ZIP với ghi chú Release đáng tin cậy trước khi chạy script. CEP production vẫn chưa ký, vẫn cần PlayerDebugMode. Xem [giới hạn và kế hoạch bảo mật](docs/SECURITY.md).
