# 2.20.42 — tối ưu căn SRT/voice theo từng nguồn

Chỉ tạo subtitle giữ SRT đã căn tốt khi một nguồn khác không khớp, lặp, đảo thứ tự hoặc chưa nhận diện được lời. Nguồn không an toàn được thử nhận diện riêng, ghi lý do trong `referenceFallbackRanges`; lỗi bộ nhớ/compiler/native vẫn dừng. Khi có SRT và lượt nhận diện ban đầu hoàn toàn rỗng, vẫn cho phép thử lại bằng nhận diện đoạn câu.

Lõi dùng chung bổ sung kiểm timestamp cho bước phục hồi; subtitle cũng dùng kiểm tra này trước khi chấp nhận cue tham chiếu. Chữ khớp nhiều nhưng timestamp NaN/Infinity, bằng 0, từ chồng/đảo hoặc vượt nguồn không được xem là căn tốt. Kết quả Auto edit hợp lệ tiếp tục được đối chiếu với baseline; không đổi mapper chính, planner, nội suy, điểm cắt hoặc executor.

Giữ nội suy cue làm phương án cuối của Auto edit. Subtitle phục hồi theo ASR trước, rồi nhận diện bổ sung phần thiếu/khác và intro/outro/CTA; vùng nhận diện vẫn rỗng được báo để kiểm tra. Không chèn lại chữ SRT chưa xác nhận bằng thời gian nội suy. Chia thời gian từ trong đoạn câu ASR là bước riêng, không phải nội suy cue thiếu từ timestamp SRT gốc.

Thêm kiểm nhiều nguồn, fallback cục bộ, ASR rỗng, lặp/đảo thứ tự và timestamp sai. Kiểm hồi quy gồm 100 ca đối chiếu cue/từ Auto edit, oracle scope dài, nội suy hai frame rate và 10 plan/SRT A/B. Xem [báo cáo rà soát](../../reviews/ALIGNMENT_REVIEW_2026-10-15.md). Chưa nghiệm thu ASR/caption/import/Play/Save trên project thật.
