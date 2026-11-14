# Rà soát nguồn audio và phạm vi Chỉ tạo subtitle

Ngày: 16/10/2026. Trạng thái: đã đóng gói và cài 2.20.50; chưa nghiệm thu audio thực trong Premiere. Phần 1 ghi nhận mã trước khi triển khai; phần 9 phân biệt kiểm chứng đã có và phần còn chờ native. Chỉ áp dụng cho Chỉ tạo subtitle. Dựng theo voice có hợp đồng V1/A1/A2 riêng.

## 1. Vấn đề xác nhận trước khi triển khai

- `extension/jsx/host.jsx`, `scanCaptionRange()`: mọi clip Video/Audio được chọn đều được quy về khoảng thời gian rồi gộp. Kết quả chưa mô tả danh tính từng clip audio được chọn hay nguồn theo nhiều track.
- `extension/js/main.js`, `runCaptions()`: job chỉ mang một `voiceTrackIndex`; nguồn audio và phạm vi được quyết định độc lập nhưng giao diện chưa làm rõ sự khác biệt đó.
- `extension/jsx/host.jsx`, `beginCaptionAudioExport()`: chỉ mở tiếng một track; kiểm có clip giao với ít nhất một vùng trong toàn job, chưa phân loại riêng từng vùng rỗng.
- `renderCaptionVoiceTracks()`: bản sửa ban đầu ưu tiên track có clip nhưng chưa phân biệt gợi ý tự động với lựa chọn thủ công. Track người dùng chỉ định bị trống cũng bị thay bằng track khác.
- `_captionOnlySnapshot()` theo dõi clip, mép, speed và mute nhưng chưa ghi `disabled`. Selection được loại khỏi snapshot pause theo thiết kế hiện tại. Cơ chế mới cần giữ danh sách nguồn đã chốt, thay vì dựa vào selection đang thay đổi.
- `run-captions.ps1`: engine đã dùng danh sách WAV theo các vùng timeline có thứ tự, không chồng nhau. Nhiều track cần phối tại cùng thời gian trước khi nhận diện; không thể gửi các vùng cùng thời gian của từng track như những chapter nối tiếp.

Đây là kết luận từ mã nguồn. Chưa dùng project người dùng để kiểm chứng audio xuất thực tế.

## 2. Giao diện thống nhất

### Nguồn audio

| Lựa chọn | Ý nghĩa |
| --- | --- |
| Tất cả track đang bật | Nhận diện bản phối đang nghe được, giữ trạng thái mute và clip enable hiện tại. Không tự mở tiếng track mute. |
| Các track chỉ định | Checkbox chọn một hoặc nhiều track. Chỉ các track này được mở tiếng tạm khi xuất; các clip disabled vẫn bị loại. Giao diện phải ghi rõ có mở tiếng tạm các track đã chọn đang mute. |
| Chỉ các clip audio đang chọn | Chỉ các clip Audio được chọn, kể cả trên nhiều track. Mở tiếng tạm track chứa chúng nếu cần; giữ clip đã disabled ở trạng thái disabled. Không đưa thêm audio gốc/nhạc chỉ vì cùng thời gian. |

Không tự đổi chế độ nguồn chỉ vì selection xuất hiện hoặc biến mất. Không tự phân loại voice/nhạc dựa vào tên track hoặc số lượng clip.

### Phạm vi thời gian

Trong hai chế độ nguồn theo track, cho chọn rõ:

1. Toàn sequence: từ 0 đến mép clip cuối timeline. Selection và In/Out cũ không giới hạn chế độ này; khoảng lặng bên trong không làm dịch timestamp.
2. Theo clip đang chọn: hợp các khoảng thời gian Video/Audio đã chọn. Chỉ lấy thời gian, không lấy danh tính audio làm nguồn. Giữ các vùng rời nhau; không nhận diện khoảng trống giữa chúng.
3. Theo In/Out: chỉ dùng khi có In/Out thực, hợp lệ; sentinel/chưa đặt/đảo chiều không được coi là phạm vi hợp lệ. Không tự chuyển về toàn sequence khi lỗi.

Trong chế độ Chỉ các clip audio đang chọn, phạm vi cố định theo chính các clip Audio đó. Ô phạm vi và danh sách track bị khóa; clip Video chọn kèm không mở rộng phạm vi. Chỉ chọn video hoặc không có clip Audio hợp lệ thì báo lỗi tại nguồn.

### Gợi ý ban đầu và lựa chọn thủ công

- Trong chế độ Các track chỉ định, khi chưa có lựa chọn thủ công: gợi ý A2 nếu có clip enabled giao phạm vi; nếu không, track audio đầu tiên có clip enabled giao phạm vi. Gợi ý có thể mở tiếng tạm một track đang mute và phải thể hiện điều này trong tóm tắt.
- Ngay khi người dùng sửa checkbox, tập track là lựa chọn tường minh. Không tự thêm, bỏ hoặc thay track dù một track rỗng hay biến mất.
- Người dùng bỏ mọi checkbox: báo chưa chọn nguồn; không tự điền lại A2.
- Track bị xóa/không xác minh được sau thay đổi thứ tự: yêu cầu chọn lại. Không xem chỉ số A3 là danh tính bền vững của track cũ.
- Track rỗng trong một tập nhiều track: giữ lựa chọn và báo số track không đóng góp audio. Nếu toàn tập không đóng góp audio thì không chạy.
- Lưu cấu hình riêng trong phiên của mỗi project/sequence; không mang chỉ số track của sequence trước sang sequence khác. Nếu không thể xác minh lựa chọn cũ thì cho chọn lại.

Mặc định lần đầu đề xuất Các track chỉ định, Toàn sequence, với track được gợi ý rõ. Việc người dùng đang chọn clip trên timeline không tự thay đổi phạm vi. Khi chuyển chế độ nguồn, giữ lại cấu hình track/phạm vi để quay lại nhưng chỉ cấu hình đang có hiệu lực được gửi vào job.

## 3. Tóm tắt và thời điểm chốt đầu vào

Tóm tắt phải xuất phát từ cùng kế hoạch đã chuẩn hóa dùng để tạo job, gồm nguồn, phạm vi, số vùng, tổng thời lượng, track/clip được lấy và phần bỏ qua. Ví dụ:

- Toàn sequence · Tất cả track đang bật · A1, A2, A4.
- 2 vùng từ clip đang chọn · 34,2 giây · Nguồn A2 + A3; mở tiếng tạm A3.
- 5 clip audio đã chọn trên A2, A4 · 3 vùng · bỏ qua 1 clip disabled.

Khi bấm chạy, đọc lại sequence, selection và In/Out, rồi lập lại kế hoạch nguồn. Nếu kế hoạch khác phần người dùng đang thấy, cập nhật tóm tắt và yêu cầu bấm chạy lại bằng thông báo ngay tại đầu vào; chưa xuất audio. Không cần hộp xác nhận cho mọi lượt chạy không đổi.

Khi đã chốt job, giữ nguyên danh tính clip/track và phạm vi trong suốt lượt chạy. Đổi selection sau đó không thay nguồn của job. Thay project/sequence, clip bị di chuyển/xóa, nguồn thay đổi hoặc topology track không xác minh được thì dừng tại ranh giới an toàn. Tiếp tục sau tạm dừng kiểm chính nguồn đã chốt, không lấy selection mới để chọn lại.

## 4. Cô lập audio và phối nhiều nguồn

- Tất cả track đang bật: không thay mute/enable; xuất bản phối timeline trong các vùng đã chốt.
- Các track chỉ định: mở tiếng tập track đó, mute track còn lại; giữ enable/gain/effect của clip.
- Clip audio đang chọn: cô lập track chưa đủ. Phải loại các clip không được chọn trên những track được sử dụng, kể cả clip chồng thời gian. Không bật lại clip vốn disabled. Nhiều clip được chọn chồng nhau được phối theo timeline.
- Khi không thể đọc/ghi/xác minh trạng thái cần thiết để cô lập từng clip, báo không hỗ trợ ở phiên Premiere đó trước khi xuất. Không giảm ngầm xuống cô lập track và không xuất lẫn clip.
- Giữ xuất qua Premiere để phản ánh nested sequence, speed và hiệu ứng của nguồn đã chọn. Đọc thẳng file bằng FFmpeg không phải thay thế tương đương cho âm thanh timeline.
- Nhiều track tạo một bản phối để nhận diện chung. Chưa bao gồm diarization hoặc một Caption Track riêng cho từng nguồn; không tự xếp lời nói đồng thời thành nối tiếp.
- Track effect, bus/routing, solo, sidechain/ducking và master effect cần kiểm bằng audio thật. Không tuyên bố cô lập track đồng nghĩa cô lập mọi đường tín hiệu trong mixer khi chưa có chứng cứ.

Tham khảo API: [mẫu PProPanel của Adobe](https://github.com/Adobe-CEP/Samples/blob/master/PProPanel/jsx/PPRO/Premiere.jsx) có ví dụ `enableAllDisabledClips` dùng thuộc tính `TrackItem.disabled` với clip video. Đây là cơ sở khảo sát cách giữ enable state, không chứng minh getter/setter hoạt động đúng cho clip Audio/nested trên máy người dùng. Phải kiểm riêng khi triển khai.

## 5. Vùng rỗng, khoảng lặng và SRT

- Kiểm giao nguồn/phạm vi cho từng vùng. Vùng chắc chắn không có clip enabled từ nguồn được chọn được bỏ qua và hiển thị lý do. Không mở rộng vùng hay thêm nguồn để lấp chỗ trống.
- Nếu không vùng nào có nguồn hợp lệ: báo lỗi đầu vào, chưa xuất WAV/ASR hoặc thêm caption.
- Có clip không đồng nghĩa có lời nói. Gain bằng 0, hiệu ứng làm im tiếng, nhạc hoặc audio không đọc được phải được phân biệt với không có clip khi có đủ chứng cứ.
- Audio xuất không có lời nói: báo không nhận diện được; không đổi nguồn tự động. Không dùng SRT để tự sinh caption trong vùng không có chứng cứ lời nói.
- Lỗi WAV, media offline, lỗi xuất hoặc lỗi đọc audio không được ghi thành khoảng lặng rồi tiếp tục như thành công.
- Các vùng rời nhau giữ tọa độ timeline; gộp khoảng trùng để tránh nhận diện/caption hai lần. Giữ kiểm frame và timestamp không chồng nhau của engine.
- SRT được căn theo audio của kế hoạch đã chốt. Đổi nguồn làm thay đổi audio tham chiếu nên không tái dùng kết quả căn từ nguồn khác chỉ vì cùng khoảng thời gian.

## 6. Hợp đồng job và khôi phục

Job mới cần mô tả tối thiểu: project/sequence identity, chế độ nguồn, chế độ phạm vi, tập track hoặc danh tính clip đã chốt, snapshot đầu vào, các vùng chuẩn hóa và đường dẫn WAV. Giữ `sources[].start/end` ở tọa độ timeline để engine và marker dùng cùng hệ quy chiếu. Phân biệt dữ liệu gợi ý tự động của UI với nguồn đã chốt của job; executor không tự chọn nguồn dự phòng.

Đọc và xác minh toàn bộ trạng thái mute/disabled cần dùng trước khi ghi bất kỳ trạng thái nào. Giữ danh tính đối tượng, giá trị gốc, trạng thái đã thay đổi và xác minh từng lần ghi. Khôi phục từng clip/track/In/Out độc lập trên đường thành công, lỗi, dừng và hủy. Một lỗi khôi phục không được ngăn các mục còn lại khôi phục; giữ nguyên lỗi xuất ban đầu và bổ sung lỗi khôi phục.

Snapshot cần bổ sung disabled/source identity phù hợp; baseline sau khôi phục phải tương đương trạng thái trước xuất. Native export vẫn theo phiên từng bước, nhường event loop, không lặp export và không giả lập timeout như đã hủy native. Trạng thái tạm cần được đối chiếu cả khi pause/resume.

Panel đóng, reload hoặc Premiere lỗi có thể làm mất phiên khôi phục trong bộ nhớ. Khi bổ sung clip-level mutation, phải thiết kế và kiểm đường khôi phục trạng thái gốc có danh tính project/sequence/clip trước khi phát hành; không tự ghi trạng thái cũ vào project khác hoặc timeline đã thay đổi. Nếu chưa xác minh được khôi phục thì giữ khóa chạy lại và báo rõ đối tượng cần kiểm. Không tự Undo, Save, đóng Premiere hoặc sửa project người dùng để thử API.

## 7. Ma trận kiểm chứng trước phát hành

Đây là ma trận yêu cầu; không được hiểu mọi ca native đều đã đạt. Kết quả thực hiện và giới hạn được ghi riêng ở phần 9.

| Nhóm | Ca cần kiểm | Điều kiện đạt |
| --- | --- | --- |
| Nguồn toàn bộ | Toàn sequence có selection và In/Out cũ; tất cả track mute; nhiều track nhạc/voice | Selection/In/Out không âm thầm giới hạn; giữ mute; không nguồn thì báo rõ |
| Gợi ý | A2 rỗng; A2 chỉ có clip ngoài vùng; A1/A2 rỗng nhưng A3 có; A2 mute | Chọn theo giao phạm vi, không chỉ clipCount; tóm tắt đúng việc mở tiếng tạm |
| Thủ công | Chọn A3; chọn A2+A3+A5; bỏ hết checkbox; một track rỗng; mọi track rỗng | Không tự đổi tập nguồn; báo phần không đóng góp/thiếu nguồn |
| Selection | Chỉ video; chỉ audio; video linked audio gốc; video+voice+nhạc; không chọn gì | Chế độ nguồn quyết định rõ audio; clip mode không suy đoán voice hoặc rơi về toàn sequence |
| Cô lập clip | Clip không chọn cùng track; clip chồng nhau; clip disabled; clip selected trên track mute | WAV không có âm của clip bị loại; giữ enable và khôi phục mute |
| Nhiều track | Clip nối tiếp và chồng nhau; một phần track hết audio giữa chừng | Phối tại đúng thời gian, không nhân đôi range/caption hoặc xếp nối tiếp sai |
| Phạm vi | Toàn sequence; vùng rời nhau; vùng trùng; In/Out hợp lệ/sentinel/đảo; vùng rỗng xen kẽ | Không mở rộng ngầm, không dịch timestamp, gộp trùng và báo vùng bỏ qua |
| Nguồn đặc biệt | Nested; speed 50/100/150%; effect/gain; routing/solo/sidechain | So WAV với nguồn timeline đã định nghĩa; ghi rõ trường hợp chưa hỗ trợ |
| Đầu vào thay đổi | Đổi selection trước chạy; sửa selection khi chạy; đổi sequence; xóa/reorder track; sửa clip | Kế hoạch đổi trước chạy được trình bày lại; job đã chốt không lấy nguồn mới |
| Lỗi API | Không đọc được mute/disabled; setter không có tác dụng; setup hỏng giữa chừng | Không nhận diện WAV lẫn nguồn; khôi phục mọi mục đã thay đổi và giữ lỗi gốc |
| Điều khiển | Pause/resume, cancel tại prepare/render/between-ranges; callback lỗi; panel reload | Không export lặp; khôi phục độc lập; không bỏ khóa khi trạng thái còn không rõ |
| Engine | Im lặng; audio hỏng/offline; WAV thiếu; SRT không khớp; source đổi nhưng cùng range | Không đổi nguồn để cứu kết quả; không dựng caption thiếu chứng cứ audio |
| Giao diện | 320/385/560 px; nhiều track/tên dài; keyboard; busy; đổi chế độ rồi quay lại | Không tràn; checkbox/ô bị khóa đúng; tóm tắt khớp job và lỗi nằm đúng trường |
| Hồi quy | Auto edit, SRT ưu tiên/thủ công, marker, DTW, export/pause/cancel cũ | Hành vi ngoài phạm vi không đổi; test liên quan và kiểm toàn bộ phù hợp đều đạt |

Mock kiểm quyết định nguồn, job, session, lỗi và khôi phục. Nghiệm thu native phải nghe/so audio xuất thật và kiểm trạng thái trước/sau cho các chế độ nguồn, nhất là clip cùng track, nested, speed/effect, mute, dừng và lỗi. Kiểm mock hoặc API mẫu không thay thế nghiệm thu đó.

## 8. Thứ tự triển khai đề xuất

1. Chuẩn hóa mô hình nguồn/phạm vi và resolver dùng chung cho tóm tắt/job; khóa lựa chọn thủ công, bổ sung ca hồi quy cho bản sửa A2 trống.
2. Bổ sung metadata quét và giao diện ba nguồn, nhiều checkbox track, phạm vi tường minh; giữ cài đặt riêng theo sequence và phát hiện kế hoạch đổi trước chạy.
3. Bổ sung toàn bộ track đang bật và nhiều track chỉ định trong staged exporter; kiểm hợp lệ từng vùng, khôi phục và pause/cancel.
4. Khảo sát/kiểm khả năng cô lập clip Audio và recovery; chỉ bật clip mode khi cơ chế đó xác minh được, không làm lựa chọn giả chỉ cô lập track.
5. Kiểm job → WAV → ASR → caption/marker, UI, kiểm hồi quy và nghiệm thu native; sau đó mới đóng gói/cài bản mới theo phạm vi người dùng yêu cầu.

Bản sửa A2 trống ban đầu đã được thay bằng cơ chế gợi ý khi chưa chọn thủ công; nguồn thủ công rỗng không còn bị đổi sang track khác.

## 9. Triển khai và bằng chứng

- Bộ kiểm cuối `Run-Tests.ps1 -NoWindowsIntegration`: **43 nhóm đạt, parse 112 script PowerShell**; sáu nhóm Windows integration bị bỏ qua. Log `.tmp-caption-input/final-suite.log`. TEMP/TMP riêng trong workspace; phép thử junction cần chạy ngoài sandbox. Syntax/ES3, UTF-8, diff whitespace và generated-source check đạt.
- `extension/js/caption-input.js`: resolver ES3 dùng chung panel/host, lưu bằng UTF-8 BOM để ExtendScript nhận đúng chuỗi tiếng Việt. Ba nguồn, ba phạm vi, gợi ý theo overlap/enabled, tập track thủ công và danh tính clip; chuẩn hóa vùng/trùng/vùng rỗng. Hợp đồng job mang kế hoạch đã chốt và key để host đối chiếu.
- UI có checkbox nhiều track, cấu hình theo project/sequence trong phiên, khóa ô không áp dụng, tóm tắt nguồn/phạm vi/unmute/vùng bỏ qua. Kế hoạch đổi trước chạy dừng tại đầu vào và cho xem tóm tắt mới; selection đổi sau khi chốt job không đổi nguồn/range.
- Host giữ staged export; mix không thay mute/enable; track mode cô lập tập track; clip mode disable clip không chọn có giao vùng trên cùng track. Getter không có hoặc setter không tác dụng thì không render/ASR.
- `job.json.audio-recovery.json` được ghi/đọc xác minh trước mutation. Hoàn tất/lỗi/hủy đều khôi phục độc lập clip/mute/In/Out và đối chiếu baseline; lỗi giữ nguyên nguyên nhân gốc cùng lỗi khôi phục. Mất phiên trong bộ nhớ có thể dùng journal qua thao tác recovery tường minh. Sai project/sequence/cấu trúc hoặc journal hỏng thì không ghi trạng thái cũ.
- Startup giữ job có journal, phát hiện journal mồ côi và khóa chạy mới; nhiều journal được xử lý lần lượt. Chỉ job đã khôi phục và bỏ journal mới đủ điều kiện dọn theo tuổi cũ.
- Các ca `caption-input.test.js`, `caption-input-host.test.js`, `caption-audio-ui.test.js`, `caption-recovery-ui.test.js` đạt. Host test dùng resolver/job/exporter thật với DOM và file fixture, xác minh tập clip có tiếng theo mute/disabled, lỗi native, setter không tác dụng, abort, mất session, journal hỏng và sai danh tính. Đây không phải phép so waveform thực.
- `tests/manual/Preview-Panel.js` đạt 320/385/560 px cho cả hai workflow, chuyển nguồn, checkbox nhiều track, giữ cấu hình khi quay lại, busy/pause/cancel và không tràn ngang. Log `.tmp-caption-input/verified-ui.log`; ảnh trong `.tmp-caption-input/ui/`. Kiểm bằng Edge headless/profile tạm, không điều khiển Premiere.
- Snapshot bổ sung disabled, track/source identity; chưa theo dõi đầy đủ mọi thay đổi tham số effect, mixer, solo hoặc routing. Chưa thử media offline/nested/speed/effect và nghe WAV xuất trên Premiere thật; chưa xác nhận getter/setter disabled của Audio trên máy người dùng. Tác vụ vẫn yêu cầu không sửa timeline/effect khi đang chạy.
- Auto edit không đổi thuật toán dựng/nhận diện; generated executor được tạo lại theo hash host mới và kiểm source. Không mở/đóng Premiere, Save, Undo hoặc dùng project người dùng trong kiểm thử.
- Theo yêu cầu cài đặt ngày 16/10/2026: bản 2.20.50 đạt lại 43 nhóm/112 script; package 69 payload, ZIP kiểm 70 entry, 61 file extension khớp nguồn đã kiểm (runtime engine.json đối chiếu cấu hình chuẩn). ZIP SHA256 `C059230612200C545866580F003FEC1444389CEACE3EC48018BB5DB9C8BAD48C`. Cài khi Premiere đóng bằng installer có rollback và `-SkipRegistry`: 61 file panel đúng checksum, 923 file dữ liệu/24 thư mục giữ nguyên, registry CEP khớp trước/sau và shortcut helper đúng identity. Bằng chứng `dist/_installation-2.20.50-20261016-165436/verified.json`. Không khởi chạy helper hoặc thao tác project; native acceptance còn chờ.
