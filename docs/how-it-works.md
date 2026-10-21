# Zalo Switcher hoạt động như thế nào

Đây là cách hoạt động mà mọi phiên bản Zalo Switcher đều tuân theo, trên bất kỳ nền tảng nào. Bản macOS hiện thực nó trong [`macos/Sources/ZaloProfilesCore`](../macos/Sources/ZaloProfilesCore). Một bản Windows sau này nên theo cùng các quy tắc và dùng cùng định dạng tệp, để cả hai hoạt động giống nhau và dùng chung một README.

Các đường dẫn dưới đây là của macOS. Chỗ nào một nền tảng cần cách làm riêng, mục đó sẽ nói rõ.

## Ý tưởng

Ứng dụng Zalo trên máy tính giữ mọi thứ của tài khoản đang đăng nhập (phiên đăng nhập, cơ sở dữ liệu tin nhắn, ảnh, tệp, cài đặt) trong một thư mục dữ liệu. Trên macOS đó là `~/Library/Application Support/ZaloData`, và không thể bảo Zalo dùng thư mục khác: Zalo bỏ qua `--user-data-dir`.

Vì vậy Zalo Switcher giữ cho mỗi tài khoản một thư mục dữ liệu đầy đủ, gọi là **hồ sơ** (profile), và trong lúc Zalo đóng thì đổi tên đúng thư mục vào chỗ Zalo tìm. Thư mục Zalo dùng gọi là **chỗ chính**. Một hồ sơ có dữ liệu nằm trong thư mục riêng của nó gọi là **đã cất**.

## Kho hồ sơ

```
<thư mục hồ sơ>/
    state.json                      hồ sơ nào được đưa vào chỗ chính lần gần nhất
    <mã>/profile.json               tên và các mốc thời gian của hồ sơ
    <mã>/<đường dẫn dữ liệu đã cất>  dữ liệu Zalo của hồ sơ khi đã cất
```

Trên macOS, thư mục hồ sơ là `~/Library/Application Support/Zalo Profiles`, và đường dẫn dữ liệu đã cất là `Library/Application Support/ZaloData`. Mỗi thư mục hồ sơ có dạng như một thư mục nhà (home), để có thể dùng làm thư mục nhà của một Zalo thứ hai (xem [Mở song song](#mở-song-song-chỉ-macos)).

`profile.json`:

```json
{
  "createdAt" : "2026-10-20T13:00:00Z",
  "id" : "cua-hang",
  "lastUsedAt" : "2026-10-20T14:30:00Z",
  "name" : "Cửa hàng"
}
```

`lastUsedAt` không có cho tới khi hồ sơ được mở lần đầu. `state.json` là `{ "main" : "<mã>" }`. Ngày giờ theo chuẩn ISO 8601.

- **mã** (id): tên thư mục, tạo từ tên: bỏ dấu và “đ” thành “d”, giữ chữ cái ASCII viết thường và chữ số, mọi ký tự khác thành một dấu gạch ngang. Nếu mã đã có, thêm `-2`, `-3`, v.v. Nếu kết quả rỗng thì dùng `profile`. Ví dụ: “Đức – Công việc” → `duc-cong-viec`.
- **tên** (name): văn bản tự do, không trùng nhau khi bỏ qua chữ hoa và dấu. Có thể tìm hồ sơ theo mã hoặc theo tên.
- **dấu nhận biết** (marker): tệp `.zalo-profile-id` trong một thư mục dữ liệu, chứa mã của hồ sơ sở hữu thư mục đó, trên một dòng.

## Hồ sơ nào đang ở chỗ chính

1. Không có thư mục dữ liệu chính: chỗ chính **trống**, và Zalo sẽ mở ở màn hình đăng nhập.
2. Dấu nhận biết trong thư mục dữ liệu chính ghi mã của một hồ sơ có thật: hồ sơ đó đang ở chỗ chính.
3. Nếu không, nếu `state.json` ghi một hồ sơ có thật và hồ sơ đó không có thư mục đã cất: hồ sơ đó đang ở chỗ chính. (Zalo có thể xóa dấu nhận biết, ví dụ sau khi đăng xuất.)
4. Nếu không nữa, chỗ chính chứa dữ liệu **chưa lưu**, không thuộc hồ sơ nào. Không được chuyển gì cho tới khi dữ liệu này được lưu thành hồ sơ.

Mỗi hồ sơ khi đó ở **chỗ chính**, **đã cất** (có thư mục dữ liệu đã cất), hoặc **mới** (chưa từng được mở).

## Chuyển sang một hồ sơ

1. Nếu hồ sơ cần chuyển đã ở chỗ chính, mở Zalo hoặc đưa Zalo lên trước. Xong.
2. Từ chối nếu chỗ chính chứa dữ liệu chưa lưu, hoặc hồ sơ cần chuyển đang mở ở cửa sổ thứ hai.
3. Nếu Zalo đang chạy trên thư mục dữ liệu chính, yêu cầu Zalo thoát theo cách bình thường (như ⌘Q) và đợi tối đa 60 giây cho Zalo và các tiến trình phụ đóng hẳn. Không bao giờ buộc thoát. Nếu Zalo vẫn chạy, dừng lại: chưa có gì bị di chuyển.
4. Nếu có hồ sơ ở chỗ chính, đổi tên thư mục dữ liệu chính thành đường dẫn đã cất của hồ sơ đó.
5. Đổi tên thư mục đã cất của hồ sơ cần chuyển thành thư mục dữ liệu chính. Nếu bước này lỗi, đổi tên thư mục của hồ sơ trước trở lại, để Zalo mở như cũ. Nếu hồ sơ cần chuyển là hồ sơ mới, tạo một thư mục dữ liệu chính trống (chỉ người dùng đọc được) thay vào đó, để Zalo mở ở màn hình đăng nhập.
6. Ghi dấu nhận biết, lưu `state.json` và đặt `lastUsedAt` của hồ sơ.
7. Mở Zalo.

## Quy tắc an toàn

Đây là những gì làm cho việc chuyển an toàn. Mọi phiên bản đều phải giữ chúng.

- **Chỉ đổi tên.** Mọi lần di chuyển đều là đổi tên trên cùng một ổ đĩa. Việc này tức thì, không cần dung lượng trống và không thể bị bỏ dở. Một lần đổi tên mà sẽ thay thế thứ gì đó ở nơi đến, hoặc sẽ phải sao chép vì nơi đến ở ổ đĩa khác, phải thất bại thay vì làm. (macOS: `renamex_np` với `RENAME_EXCL`.)
- **Không bao giờ xóa dữ liệu Zalo.** Xóa một hồ sơ sẽ chuyển cả thư mục của nó vào Thùng rác, nơi có thể lấy lại. Không thể xóa hồ sơ đang ở chỗ chính, hay hồ sơ đang mở ở cửa sổ thứ hai.
- **Không bao giờ buộc Zalo thoát.** Buộc thoát có thể khiến cơ sở dữ liệu của Zalo bị ghi dở.
- **Dừng lại khi không chắc.** Bất cứ điều gì bất thường (một thư mục chắn đường, Zalo vẫn chạy, thiếu hồ sơ) đều dừng thao tác trước khi có gì bị di chuyển, kèm thông báo nói rõ lý do.
- **Để ý dung lượng trống.** Khi ổ đĩa chứa dữ liệu Zalo còn trống dưới 5 GB (hoặc mức người dùng chọn), cảnh báo, và hỏi trước khi thêm tài khoản hay mở một tài khoản ở cửa sổ thứ hai (`--force` trong dòng lệnh). Zalo ghi tin nhắn ngay khi chúng đến, và ổ đĩa đầy là nguyên nhân chính khiến dữ liệu của nó bị hỏng.

## Biết Zalo có đang mở một thư mục hay không

Ứng dụng Zalo trên máy tính được xây dựng trên Electron (Chromium). Trên macOS, khi một thư mục dữ liệu đang mở, Chromium giữ trong đó một liên kết tượng trưng `SingletonLock` trỏ tới `<máy>-<pid>`. Zalo Switcher đọc pid và kiểm tra tiến trình còn chạy và đúng là Zalo (bundle id `com.vng.zalo`). Mỗi nền tảng cần cách riêng để biết điều này.

## Tài khoản Zalo trong một thư mục dữ liệu

ID tài khoản Zalo là tên của thư mục chỉ gồm chữ số (ít nhất sáu chữ số) được sửa gần nhất trong `<thư mục dữ liệu>/Database/_production/`. ID này được dùng để chỉ ra hai hồ sơ cùng chứa một tài khoản, ví dụ sau khi khôi phục một bản sao lưu.

## Sao lưu

Một bản sao lưu là thư mục `<nơi lưu>/Zalo Backups/<mã> <yyyy-MM-dd HH.mm>/` chứa `ZaloData/` và `backup.json`:

```json
{
  "bytes" : 455000000,
  "createdAt" : "2026-10-20T14:00:00Z",
  "files" : 508,
  "format" : 1,
  "links" : 0,
  "profileID" : "cua-hang",
  "profileName" : "Cửa hàng",
  "zaloUserID" : "123456789"
}
```

- `files` đếm mọi tên tệp, kể cả các tên phụ của tệp liên kết cứng. `bytes` đếm dữ liệu liên kết cứng một lần. `links` là số tên được tạo lại dưới dạng liên kết cứng.
- Tạo bản sao lưu: chỉ đóng Zalo của hồ sơ đó trong lúc lấy một bản sao nhất quán (macOS: một bản chụp APFS, vài giây), mở lại Zalo, rồi sao chép sang nơi lưu ở chế độ chạy ngầm, kiểm tra kích thước từng tệp. Bản sao được ghi dưới tên `<tên>.partial` và chỉ được đặt tên chính thức cùng `backup.json` khi mọi thứ đều khớp. Bản sao bị lỗi hoặc bị hủy sẽ bị xóa.
- Khôi phục: sao chép `ZaloData/` vào một thư mục tạm trong thư mục hồ sơ, kiểm tra với `backup.json`, rồi mới biến nó thành một hồ sơ **mới**. Khôi phục không bao giờ thay thế hồ sơ đang có.

## Mở song song (chỉ macOS)

Thử nghiệm. Một hồ sơ đã cất có thể được mở trong một Zalo thứ hai trong khi Zalo chính vẫn chạy: Zalo được mở với `CFFIXED_USER_HOME` trỏ tới thư mục hồ sơ, nên thư mục Application Support của nó, và theo đó thư mục dữ liệu của nó, là của riêng hồ sơ. Thư mục hồ sơ có các liên kết tượng trưng tới Keychain thật, Tải về, Màn hình nền, Tài liệu, Ảnh, Phim và Nhạc. Gọi điện chỉ ổn định ở một cửa sổ, vì phần gọi điện của Zalo dùng đường dẫn socket cố định.

Các nền tảng khác sẽ cần cách khác để cho Zalo thứ hai một thư mục dữ liệu riêng, hoặc có thể không hỗ trợ việc này.

## Bản demo

`Zalo Switcher --demo` (và `--render-screenshots <thư mục>`, dùng để tạo ảnh cho README) chạy toàn bộ logic thật trên bốn hồ sơ giả lập trong một thư mục tạm, với một “Zalo giả” không mở ứng dụng nào. Bản demo không bao giờ đọc hay ghi dữ liệu Zalo thật, và xóa hồ sơ trong bản demo chỉ chuyển nó vào thư mục tạm đó.
