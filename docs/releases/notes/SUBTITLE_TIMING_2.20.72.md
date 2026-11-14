# Premiere Voice Sync 2.20.72 — xét lại câu SRT trước khi dùng ASR

## Kiểm lượt Nam Cực

Đọc project đã lưu `Thế giới dưới lớp băng Nam Cực_1.prproj` và SRT trong
`F:\Work\Kiến thức\25-11-24 Thế giới dưới lớp băng Nam Cực\Source file\Thế giới dưới lớp băng Nam Cực`.
Lượt gần nhất 09:50:50–09:55:39 ngày 18/10/2026 dùng 2.20.70, workflow Tạo
phụ đề, 468 caption. Lượt 08:21 có cùng danh sách cảnh báo. Engine/host
liên quan trong gói 2.20.70 khớp nguồn trước sửa, dù panel hiện tại là 2.20.71.

Đối chiếu toàn bộ 468 caption với 255 câu SRT, không chỉ các marker:

- 446 caption có chữ lấy từ SRT. Ghép toàn bộ chữ này theo thứ tự, chuẩn hóa
  hoa/thường/dấu câu để đối chiếu, chỉ thiếu đúng sáu cue nguồn: 97, 152, 175,
  208, 211, 241. Như vậy chữ của 249/255 câu nguồn có trong output đã lưu.
- 22 caption dùng ASR: 11 caption nội dung chính và 11 caption cảm ơn/hội
  viên ở cuối. Phần cảm ơn không có trong SRT được chọn.
- Caption 371 đã có đúng `dãy núi Gamburtsev.` từ SRT; caption 372 lại thêm
  `núi Gamberstheb.`. Đây là chèn lặp chữ đã giữ, không phải thiếu tên trong SRT.
- Ba cảnh báo timing tại khoảng 17,517–18,649; 475,233–479,233;
  599,784–600,284 giây. Một cảnh báo confidence thấp ở 682,396–685,165 giây.
  Không có caption thời lượng âm/0, chồng hoặc đảo thời gian trong dữ liệu đã lưu.

| Thời gian trên sequence | Caption cuối | Cue SRT | Kết quả đã lưu |
| --- | --- | --- | --- |
| 05:01,100–05:04,700 | 186–187 | 97 | `năm sâu... dưới lớp bằng` thay câu số đo 3 phẩy 7 đến 4 phẩy 1 |
| 07:26,000–07:27,200 | 273 | 152 | Đã nhận diện lại đúng `chịu được bức xạ mạnh` nhưng vẫn đánh dấu/dùng ASR |
| 08:15,767–08:17,800 | 306 | 175 | ASR `mực khổng lồ nam cực dài tới 10 m` thay nguyên câu SRT |
| 09:59,800–10:03,367 | 372–373 | 207, 208 | Lặp tên núi đã có ở 371, rồi dùng `Dãi núi... 1.200 km` |
| 10:08,600–10:12,667 | 376–378 | 211 | `rãi`, `trôn`, `vui`, `bang giày` và cách viết số thay chữ SRT |
| 11:45,467–11:48,200 | 431–432 | 241 | `tiếng ủ địa chấn` thay `tiếng ù địa chấn` |
| 12:29,900–12:46,400 | 458–468 | Không có | Cảm ơn/hội viên ngoài SRT; ASR còn sai `NoSick`, `chân trọng`, `hiệu ích` |

## Nguyên nhân

Core dùng chung với Dựng theo voice chỉ nhận recovery khi toàn cửa sổ gồm cả
hai hàng xóm khớp chính xác. Đây là bằng chứng bỏ/giữ hình cần giữ nghiêm.
Khi câu giữa đã được ASR nhận đúng nhưng hàng xóm vẫn sai vài chữ, core không
thay dữ liệu từ cũ. Adapter phụ đề sau đó tiếp tục chiếu trên dữ liệu cũ, không
thử lại riêng câu bị thiếu. Bước supplement ghi thẳng ASR vào khoảng trống.

Cache có riêng câu `chịu được bức xạ mạnh` và `mực khổng lồ nam cực dài tới
10 m`; kiểm predicate trên từng câu đó đạt, trong khi dữ liệu chính ban đầu
ghi `giữ được bức sạ mạnh` và `mức khổng lồ được dài tới 10 m`. Vì vậy chỉ giảm
ngưỡng chung sẽ không giải quyết đúng nguyên nhân và có thể ảnh hưởng câu đã cắt.

Helper nhận diện số trước đây chỉ chấp nhận một dải số liên tục, không hiểu
hai đầu khoảng nối bằng `đến`; đơn vị `m`/`mét` cũng chưa được coi tương đương.
Ngữ cảnh tên riêng còn có ba sai khác gần nhau (`mang/bằng`, `dãy/dãi`,
`Gamburtsev/Gamberstheb`) nên chốt chỉ cho một sai khác không nhận ra đuôi đã giữ.

## Phạm vi sửa

Chỉ thay adapter `CaptionOnly.ps1` và xử lý ngữ cảnh subtitle trong
`SubtitleTiming.ps1`. Core `ReferenceAlignment.ps1`, planner, host JSX, thao tác
timeline, marker và hệ thống thông báo giữ nguyên.

- Với cue chưa giải quyết, thử lại riêng khoảng giữa hai cue SRT liền kề đã
  giữ, cùng source, timestamp hợp lệ, mỗi neo ít nhất bốn từ. Không thử cue
  đã được chứng minh bỏ, câu tương lai thiếu neo, cue lặp mơ hồ, nhãn dưới ba từ,
  khoảng hơn 30 giây. Giới hạn 32 lần/180 giây audio cho nhánh này.
- Giữ nguyên predicate nhận diện câu, bảo toàn toàn bộ chữ SRT. Không nuốt lời
  thêm ở mép cửa sổ; không tạo timestamp cho từ thiếu. Phục hồi là partial
  subtitle, không được nâng thành DTW hoàn chỉnh hay bằng chứng cắt hình.
- Nối hai đầu khoảng số chỉ khi `đến` nằm giữa các token số; giữ chữ đơn vị SRT.
  Bất đồng hoặc mơ hồ về giá trị vẫn được lưu trong dữ liệu review, không thay
  chữ/số nguồn bằng ASR, không bật lại marker đối chiếu số đã bỏ trước đây.
- Ngữ cảnh tám từ đã thuộc câu SRT giữ được phép có tối đa ba sai khác gần,
  còn ít nhất năm từ trùng. Mỗi sai khác phải qua cùng phép kiểm chính tả;
  vẫn cần duy nhất một vị trí và nằm gần mép. Neo ngắn giữ giới hạn một sai
  khác. Từ không liên quan, số thay đổi và ngữ cảnh lặp không được cắt bỏ.

## Hồi quy bắt buộc

`Test-SubtitleRetryReference.ps1` chứa sáu ca câu Nam Cực, số dạng khoảng/đơn
vị, đuôi tên riêng lặp, giữ chữ tới caption cuối, offset, timing quality/origin,
nhận diện trống/khác, lời thêm, timestamp sai và bằng chứng Auto edit không đổi.

Mỗi lần sửa luồng này phải chạy cùng các bộ cũ, không xóa ca khó để cho suite
đạt: Short/SRT dài và cue tương lai trùng; số đọc/La Mã; nhãn A./C.; SRT join
và voice language; partial sentence/identity; supplement thật/CTA; đuôi
`tận/tật`, `giải/dài`; ngữ cảnh lặp/sai khác/lời thêm; DTW retry cục bộ,
overlap và voice conservation; marker ownership/reconciliation; pause/cancel,
notification và package lifecycle. `tests/Run-Tests.ps1` tự phát hiện các bộ này.

## Bằng chứng và giới hạn

Bằng chứng đọc project/cache tại `.tmp-antarctica-audit-20261018/` gồm hash
nguồn, tracks, markers, cache-index, comparison, whole-output-diff và các
diagnostic/predicate từ cache. Replay selection trên segment timestamp chỉ giữ
247 cue, không thay cho số 249 cue của output native đã lưu. Đây là hai loại
bằng chứng khác nhau.

Kiểm toàn engine trên audio A2 dựng lại từ InPoint/speed của 74 clip và nested
Hội viên dùng vùng job/cache/temp riêng trong workspace. Audio này không có
mix/effect native của Premiere. Cùng WAV/GPU/backend small: baseline 2.20.71
giữ 249/255 cue, adapter mới giữ 250/255. Còn chưa nhận diện được cue 138,
167, 207, 209, 210, có cảnh báo ASR; không tuyên bố đã phục hồi đủ 255 câu.
Sáu cue thiếu của lượt native ban đầu lại đều được baseline giữ trên WAV dựng
lại; vì vậy số liệu WAV này không phải bằng chứng nghiệm thu sáu lỗi native.
Sáu ca đó có cache diagnostic và regression fixture riêng. Output engine mới
có 468 caption và vẫn ba vùng timing ước lượng cần kiểm tra.

Sau khi chốt phạm vi, toàn suite đạt 54 nhóm, parse 124 script, bỏ qua sáu
nhóm integration Windows có tác động bên ngoài (`-NoWindowsIntegration`).
Replay cache lịch sử consciousness giữ đúng 27 cue, letters giữ đúng 199 cue,
gồm A./C.; không phục hồi câu tương lai đã cắt. Test mới được chứng minh thất
bại trên hai lib trước sửa. Các kết quả tự động không phải bảo đảm tuyệt đối
mọi đầu vào; các ca lịch sử phải tiếp tục có mặt trong suite lần sửa sau.

Không điều khiển Premiere, import, Play, Save hoặc Undo project;
hash project/SRT nguồn phải giữ nguyên. Chạy lại/import/nghe/marker native là
nghiệm thu riêng, không được suy từ suite hoặc checksum gói.

Gói cuối: `dist/Premiere-Voice-Sync-2.20.72-Panel.zip`, 488.774.235 byte,
SHA256 `93B12DCE172B50E5FFCFC5A3399EC8DCA4A451CB65B3A56EF96DB279EAF414C8`.
Kiểm 71 payload/72 ZIP entry khớp hash, nguồn/runtime khớp, 20 bộ VM chạy trên
mã trong gói đạt; 46 file engine/host ngoài hai lib sửa khớp 2.20.71.
Cài từ 2.20.71 khi Premiere/helper đóng; xác minh 63 file panel đã cài và giữ
nguyên hash của 4.522 file/22 thư mục dữ liệu, registry CEP không đổi. Bằng
chứng: `dist/_installation-2.20.72-20261018T035426Z/verified.json`. Native
acceptance vẫn chờ chạy lại/import/nghe trên Premiere.
