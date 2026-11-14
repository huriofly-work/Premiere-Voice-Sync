# Khoảng không lời mặc định 0,5 giây — 2.20.81

Theo yêu cầu, giá trị mặc định đổi từ 1 giây sang 0,5 giây ở input HTML,
thiết lập panel, planner và hàm DTW dự phòng. Lần mở mới, trường chưa lưu
và nút khôi phục mặc định đều dùng 0,5 giây. Giá trị tùy chỉnh đã lưu vẫn giữ
nguyên; không tăng schema hoặc ép ghi lại profile CEP.

Ngưỡng này xác định khoảng không lời từ SRT nguồn. Các điều kiện cắt voice
an toàn, khoảng lặng âm thanh tối thiểu, manual block, omission và phục hồi
caption của 2.20.80 vẫn được giữ. Subtitle-only không dùng ngưỡng dựng này.

Regression kiểm mặc định mới đi tới job, trường bị thiếu, giá trị đã lưu
1/2 giây, tùy chỉnh 1,5 giây, job thiếu ngưỡng và hàm DTW gọi trực tiếp.
Bộ hồi quy đầy đủ và replay ngoại tuyến phải đạt trước khi phân phối.
Replay job không ghi ngưỡng cần cho cùng kết quả với 2.20.80 đặt rõ 0,5 giây.

Nghiệm thu import/cắt/tốc độ/phát lại/timing/marker trong Premiere còn chờ.
Không tự lưu project. Phân phối prerelease theo quy trình kiểm hash, đồng bộ
nguồn/gói và CI; giữ bản cài cũ cùng dữ liệu người dùng.
