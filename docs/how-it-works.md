# Zalo Switcher hoạt động như thế nào

Đây là cách hoạt động mà mọi phiên bản Zalo Switcher đều tuân theo, trên bất kỳ nền tảng nào. Bản macOS hiện thực nó trong [`macos/Sources/ZaloProfilesCore`](../macos/Sources/ZaloProfilesCore). Một bản Windows sau này nên theo cùng các quy tắc và dùng cùng định dạng tệp, để cả hai hoạt động giống nhau và dùng chung một README.

Các đường dẫn dưới đây là của macOS. Chỗ nào một nền tảng cần cách làm riêng, mục đó sẽ nói rõ.

## Ý tưởng

Ứng dụng Zalo trên máy tính giữ mọi thứ của tài khoản đang đăng nhập (phiên đăng nhập, cơ sở dữ liệu tin nhắn, ảnh, tệp, cài đặt) trong một thư mục dữ liệu. Trên macOS đó là `~/Library/Application Support/ZaloData`, và không thể bảo Zalo dùng thư mục khác: Zalo bỏ qua `--user-data-dir`.

Vì vậy Zalo Switcher giữ cho mỗi tài khoản một thư mục dữ liệu đầy đủ, gọi là **hồ sơ** (profile), và mở mỗi hồ sơ trong một Zalo riêng, tất cả cùng lúc. Thư mục Zalo dùng khi được mở theo cách bình thường gọi là **chỗ chính**, và hồ sơ ở đó là **Zalo chính**. Một hồ sơ có dữ liệu nằm trong thư mục riêng của nó gọi là **đã cất**; nó được mở trong một Zalo có thư mục nhà riêng (xem [Mở nhiều hồ sơ cùng lúc](#mở-nhiều-hồ-sơ-cùng-lúc-chỉ-macos)). Chỉ khi đổi Zalo chính, các thư mục mới được đổi tên, và chỉ trong lúc Zalo của chúng đóng.

## Kho hồ sơ

```
<thư mục hồ sơ>/
    state.json                      hồ sơ nào được đưa vào chỗ chính lần gần nhất
    <mã>/profile.json               tên và các mốc thời gian của hồ sơ
    <mã>/<đường dẫn dữ liệu đã cất>  dữ liệu Zalo của hồ sơ khi đã cất
```

Trên macOS, thư mục hồ sơ là `~/Library/Application Support/Zalo Profiles`, và đường dẫn dữ liệu đã cất là `Library/Application Support/ZaloData`. Mỗi thư mục hồ sơ có dạng như một thư mục nhà (home), để có thể dùng làm thư mục nhà của một Zalo riêng (xem [Mở nhiều hồ sơ cùng lúc](#mở-nhiều-hồ-sơ-cùng-lúc-chỉ-macos)).

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
4. Nếu không nữa, chỗ chính chứa dữ liệu **chưa lưu**, không thuộc hồ sơ nào. Không được đặt hồ sơ khác làm Zalo chính cho tới khi dữ liệu này được lưu thành hồ sơ.

Mỗi hồ sơ khi đó ở **chỗ chính**, **đã cất** (có thư mục dữ liệu đã cất), hoặc **mới** (chưa từng được mở).

## Mở một hồ sơ

1. Nếu một Zalo đang mở hồ sơ đó, đưa nó lên trước. Xong.
2. Từ chối nếu một hồ sơ khác chứa cùng tài khoản Zalo (cùng ID tài khoản) đang mở, kể cả dữ liệu chưa lưu đang mở ở chỗ chính. Hai Zalo trên cùng một tài khoản sẽ dùng chung một phiên đăng nhập, và Zalo có thể kết thúc phiên đó hoặc đánh dấu tài khoản có hoạt động bất thường.
3. Hồ sơ ở chỗ chính: mở Zalo theo cách bình thường.
4. Hồ sơ mới, khi chỗ chính trống: [đặt nó làm Zalo chính](#đặt-làm-zalo-chính) rồi mở Zalo, để Zalo mở theo cách bình thường cũng có một tài khoản.
5. Mọi hồ sơ khác: mở một Zalo riêng cho thư mục hồ sơ. Hồ sơ mới mở ở màn hình đăng nhập.
6. Đặt `lastUsedAt` của hồ sơ.

**Mở tất cả** mở mọi hồ sơ đã có dữ liệu (đã từng đăng nhập) mà chưa mở, bỏ qua hồ sơ chứa cùng tài khoản Zalo với một hồ sơ đang mở, và mở Zalo chính sau cùng.

## Đóng một hồ sơ

Yêu cầu Zalo của hồ sơ đó thoát theo cách bình thường (như ⌘Q), rồi đợi tối đa 60 giây cho Zalo và các tiến trình phụ của nó đóng hẳn. Chỉ tính các tiến trình của chính Zalo đó; các Zalo khác không bị đụng tới.

Ở màn hình đăng nhập, Zalo đôi khi đóng cửa sổ và mọi tiến trình hiển thị (renderer) khi được yêu cầu thoát, rồi không bao giờ thoát hẳn. Nếu Zalo ở trạng thái đó hơn 3 giây và không có cơ sở dữ liệu tài khoản nào đang mở (`Database/_production/<ID tài khoản>/`), tức không có ai đăng nhập, thì không còn gì để lưu: gửi SIGTERM, yêu cầu thoát mà macOS cũng gửi khi tắt máy, lặp lại mỗi 5 giây cho tới khi Zalo thoát. Một Zalo còn cửa sổ, hoặc đang mở tin nhắn của một tài khoản, không bao giờ nhận SIGTERM.

## Đặt làm Zalo chính

1. Nếu hồ sơ đã ở chỗ chính: xong.
2. Từ chối nếu chỗ chính chứa dữ liệu chưa lưu.
3. Ghi nhớ Zalo chính có đang chạy không. Nếu hồ sơ cần đặt đang mở trong Zalo riêng, [đóng nó](#đóng-một-hồ-sơ).
4. Nếu Zalo đang chạy trên thư mục dữ liệu chính, yêu cầu Zalo thoát theo cách bình thường (như ⌘Q) và đợi tối đa 60 giây cho Zalo và các tiến trình phụ đóng hẳn. Không bao giờ buộc thoát. Nếu Zalo vẫn chạy, dừng lại: chưa có gì bị di chuyển.
5. Nếu có hồ sơ ở chỗ chính, đổi tên thư mục dữ liệu chính thành đường dẫn đã cất của hồ sơ đó.
6. Đổi tên thư mục đã cất của hồ sơ cần đặt thành thư mục dữ liệu chính. Nếu bước này lỗi, đổi tên thư mục của hồ sơ trước trở lại, để Zalo mở như cũ. Nếu hồ sơ cần đặt là hồ sơ mới, tạo một thư mục dữ liệu chính trống (chỉ người dùng đọc được) thay vào đó, để Zalo mở ở màn hình đăng nhập.
7. Ghi dấu nhận biết, lưu `state.json` và đặt `lastUsedAt` của hồ sơ.
8. Mở Zalo. Nếu hồ sơ Zalo chính cũ đang chạy trước đó, mở lại nó trong Zalo riêng. Nếu có lỗi, mở lại những gì đã đóng, ở nơi dữ liệu của chúng đang nằm.

## Quy tắc an toàn

Đây là những gì giữ dữ liệu của các tài khoản an toàn. Mọi phiên bản đều phải giữ chúng.

- **Chỉ đổi tên.** Mọi lần di chuyển đều là đổi tên trên cùng một ổ đĩa. Việc này tức thì, không cần dung lượng trống và không thể bị bỏ dở. Một lần đổi tên mà sẽ thay thế thứ gì đó ở nơi đến, hoặc sẽ phải sao chép vì nơi đến ở ổ đĩa khác, phải thất bại thay vì làm. (macOS: `renamex_np` với `RENAME_EXCL`.)
- **Không bao giờ xóa dữ liệu Zalo.** Xóa một hồ sơ sẽ chuyển cả thư mục của nó vào Thùng rác, nơi có thể lấy lại. Không thể xóa hồ sơ đang ở chỗ chính, hay hồ sơ đang mở.
- **Không bao giờ buộc Zalo thoát.** Buộc thoát có thể khiến cơ sở dữ liệu của Zalo bị ghi dở. Ngoại lệ duy nhất là một Zalo không có ai đăng nhập, bị kẹt sau khi đã đóng cửa sổ (xem [Đóng một hồ sơ](#đóng-một-hồ-sơ)), và khi đó chỉ gửi SIGTERM, không bao giờ SIGKILL.
- **Một tài khoản Zalo, một cửa sổ.** Không mở hai hồ sơ chứa cùng một tài khoản Zalo cùng lúc.
- **Dừng lại khi không chắc.** Bất cứ điều gì bất thường (một thư mục chắn đường, Zalo vẫn chạy, thiếu hồ sơ) đều dừng thao tác trước khi có gì bị di chuyển, kèm thông báo nói rõ lý do.
- **Để ý dung lượng trống.** Khi ổ đĩa chứa dữ liệu Zalo còn trống dưới 5 GB (hoặc mức người dùng chọn), cảnh báo, và hỏi trước khi thêm tài khoản hay mở thêm một tài khoản (`--force` trong dòng lệnh). Zalo ghi tin nhắn ngay khi chúng đến, và ổ đĩa đầy là nguyên nhân chính khiến dữ liệu của nó bị hỏng.

## Biết Zalo có đang mở một thư mục hay không

Ứng dụng Zalo trên máy tính được xây dựng trên Electron (Chromium). Trên macOS, khi một thư mục dữ liệu đang mở, Chromium giữ trong đó một liên kết tượng trưng `SingletonLock` trỏ tới `<máy>-<pid>`. Zalo Switcher đọc pid và kiểm tra tiến trình còn chạy và đúng là Zalo (bundle id `com.vng.zalo`). Đó cũng là cách biết hồ sơ nào đang mở. Mỗi nền tảng cần cách riêng để biết điều này.

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

## Mở nhiều hồ sơ cùng lúc (chỉ macOS)

Hồ sơ ở chỗ chính mở trong Zalo bình thường. Mỗi hồ sơ đã cất mở trong một Zalo riêng, được mở bằng `open -n` với `CFFIXED_USER_HOME` trỏ tới thư mục hồ sơ, nên thư mục Application Support của nó, và theo đó thư mục dữ liệu của nó, là của riêng hồ sơ. Các Zalo này chạy cùng lúc và không đụng tới dữ liệu của nhau. Thư mục hồ sơ có các liên kết tượng trưng tới Keychain thật, Tải về, Màn hình nền, Tài liệu, Ảnh, Phim và Nhạc. Gọi điện chỉ ổn định ở một cửa sổ, vì phần gọi điện của Zalo dùng đường dẫn socket cố định.

Các nền tảng khác sẽ cần cách khác để cho mỗi Zalo một thư mục dữ liệu riêng. Nếu một nền tảng không làm được, nó vẫn có thể chỉ hỗ trợ [đặt làm Zalo chính](#đặt-làm-zalo-chính), tức là đổi qua lại từng tài khoản.

## Bản demo

`Zalo Switcher --demo` (và `--render-screenshots <thư mục>`, dùng để tạo ảnh cho README) chạy toàn bộ logic thật trên bốn hồ sơ giả lập trong một thư mục tạm, với một “Zalo giả” không mở ứng dụng nào. Bản demo không bao giờ đọc hay ghi dữ liệu Zalo thật, và xóa hồ sơ trong bản demo chỉ chuyển nó vào thư mục tạm đó.
