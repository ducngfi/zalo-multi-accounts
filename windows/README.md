# Zalo Switcher cho Windows

Chưa bắt đầu. Hiện Zalo Switcher chỉ chạy trên macOS; thư mục này là nơi dành cho một ứng dụng Windows sau này.

Một bản Windows nên:

- nằm trọn trong thư mục này, với mã nguồn, script build và kiểm thử riêng (ví dụ một solution .NET);
- tuân theo cách hoạt động, quy tắc an toàn và định dạng tệp trong [docs/how-it-works.md](../docs/how-it-works.md), để hồ sơ và bản sao lưu hoạt động giống như trên máy Mac;
- có giao diện tiếng Việt, như bản macOS;
- dùng biểu tượng trong [assets/icon](../assets/icon): `AppIcon.ico` dùng được ngay, và `make-icons.sh` xuất lại nó từ `AppIcon.svg`.

## Cần tìm hiểu trước

Chưa có điều nào dưới đây được kiểm tra trên Windows.

- Zalo cho Windows lưu dữ liệu ở đâu, và mọi thứ (phiên đăng nhập, tin nhắn, ảnh, tệp) có nằm trong một thư mục như trên máy Mac không.
- Có thể mở Zalo với một thư mục dữ liệu khác không; nếu được, việc chuyển hay mở cửa sổ thứ hai sẽ đơn giản hơn.
- Làm sao biết Zalo có đang mở một thư mục dữ liệu, và làm sao cho Zalo thoát sạch sẽ. Đóng cửa sổ có thể chỉ ẩn Zalo xuống khay hệ thống, và Windows không cho đổi tên một thư mục khi có tệp bên trong đang mở.
- Đổi tên: `MoveFileEx` không có `MOVEFILE_REPLACE_EXISTING` và không có `MOVEFILE_COPY_ALLOWED` sẽ thất bại thay vì thay thế hay sao chép sang ổ đĩa khác, đúng với quy tắc “chỉ đổi tên”.
- Nên để hồ sơ ở đâu (ví dụ `%LOCALAPPDATA%\Zalo Profiles`), trên cùng ổ đĩa với dữ liệu Zalo.
