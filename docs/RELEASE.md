# Quy trình phát hành

1. Cập nhật `VERSION`, manifest, changelog, README và mặc định version của script build ZIP.
2. Chạy `tests\Run-Tests.ps1` trên checkout sạch.
3. Nghiệm thu trong Premiere Pro 26.2.2 theo `TESTING.md`.
4. Tạo ZIP bằng `installer\build-release.ps1`.
5. Kiểm tra Setup-Panel.cmd/Remove-Panel.cmd: thiết lập mới, lặp lại, chuyển từ bản EXE cũ không mất cache, gỡ sạch và khôi phục PlayerDebugMode trên tài khoản Windows thử nghiệm.
6. Xác nhận không tạo mục Installed apps, không có EXE installer trong gói và không đóng gói dữ liệu riêng.
7. Đưa duy nhất Premiere-Voice-Sync-<version>-Panel.zip cùng SHA-256 trong ghi chú GitHub Release. Không phát hành Setup.exe.
8. Kiểm mandatory checksum/exact allowlist, file thừa, junction ở root/parent/tree và rollback cập nhật. Không dùng hash nằm trong chính gói như bằng chứng nguồn gốc.
9. Quét ZIP và thư mục giải nén bằng antivirus đang bật. Ghi công cụ, phiên bản chữ ký, kết quả và hạn chế; không gọi một lần scan là chứng nhận an toàn.
10. Nghiệm thu máy/tài khoản Windows sạch: offline CPU, GPU chưa tải (phải có consent), GPU hash sai (không thực thi), xóa cache, xuất log đã che, setup/gỡ không đụng file sentinel của chương trình khác.

Thư mục `dist` và runtime lớn không được commit. Một thay đổi trong `experiments` không được phép đi vào Release nếu chưa có quyết định nâng hợp đồng production và một vòng nghiệm thu riêng.
