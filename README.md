<p align="center"><img src="assets/icon/AppIcon-1024.png" width="160" alt="Biểu tượng Zalo Switcher"></p>

# Zalo Switcher

Giữ nhiều tài khoản Zalo trên một máy Mac và chuyển qua lại chỉ với một cú bấm. Bạn không phải đăng xuất, nhập lại mật khẩu hay quét lại mã QR, và không mất tin nhắn, ảnh hay tệp nào.

<p align="center"><img src="docs/screenshots/cua-so-chinh.png" width="760" alt="Cửa sổ Zalo Switcher với bốn tài khoản"></p>

**Chỉ dành cho macOS** (macOS 13 trở lên). Hiện chưa có bản Windows; dự án được sắp xếp để có thể thêm bản Windows sau này (xem [Cấu trúc dự án](#cấu-trúc-dự-án)).

Có hai cách dùng, chung một mã nguồn:

- **Zalo Switcher.app**: ứng dụng có cửa sổ, biểu tượng trong Dock và biểu tượng trên thanh menu.
- **`zalo-profiles`**: công cụ dòng lệnh trong Terminal.

> [!IMPORTANT]
> **Không liên kết với Zalo.** Zalo Switcher là dự án độc lập, không chính thức. Dự án không do Zalo hay VNG làm ra, bảo trợ hay hỗ trợ, và tác giả không có liên quan gì tới thương hiệu Zalo. “Zalo” là nhãn hiệu của chủ sở hữu, chỉ được nhắc tới ở đây để nói công cụ này dùng với ứng dụng nào. Nếu cần hỗ trợ về Zalo, hãy liên hệ Zalo, không phải dự án này.

> [!WARNING]
> **Bạn tự chịu rủi ro khi sử dụng.** Zalo Switcher di chuyển thư mục chứa toàn bộ tin nhắn, ảnh và tệp Zalo của bạn. Ứng dụng được viết cẩn thận (chỉ đổi tên thư mục, không bao giờ xóa dữ liệu Zalo, và dừng lại ngay khi có gì bất thường), nhưng không có bất kỳ bảo hành nào. **Tác giả không chịu trách nhiệm nếu bạn mất dữ liệu, mất quyền truy cập tài khoản hay gặp bất kỳ vấn đề nào khác khi sử dụng.** Hãy sao lưu dữ liệu Zalo trước khi bắt đầu, và giữ bản sao lưu của những gì bạn không thể để mất. Xem [LICENSE](LICENSE).

## Mục lục

- [Giới hạn, và vì sao có các giới hạn đó](#giới-hạn-và-vì-sao-có-các-giới-hạn-đó)
- [Cách chuyển tài khoản hoạt động](#cách-chuyển-tài-khoản-hoạt-động)
- [Cài đặt](#cài-đặt)
- [Sử dụng](#sử-dụng)
- [Bản demo](#bản-demo)
- [Dùng bằng dòng lệnh](#dùng-bằng-dòng-lệnh)
- [Dung lượng ổ đĩa](#dung-lượng-ổ-đĩa)
- [Sao lưu và khôi phục](#sao-lưu-và-khôi-phục)
- [Mở song song (thử nghiệm)](#mở-song-song-thử-nghiệm)
- [Lưu ý thêm](#lưu-ý-thêm)
- [Cấu trúc dự án](#cấu-trúc-dự-án)

## Giới hạn, và vì sao có các giới hạn đó

Có những việc công cụ này không làm được. Phần lớn là do cách Zalo hoạt động chứ không phải do ứng dụng này, và không ứng dụng nào trên máy tính của bạn thay đổi được.

**Một tài khoản không thể đăng nhập cùng lúc trên hai điện thoại, hai máy tính hay hai phiên Zalo Web.** Máy chủ của Zalo chỉ cho mỗi tài khoản một phiên của mỗi loại tại một thời điểm: một điện thoại, một ứng dụng Zalo trên máy tính và một phiên web ([chat.zalo.me](https://chat.zalo.me)). Đăng nhập trên điện thoại thứ hai sẽ đăng xuất điện thoại thứ nhất. Đăng nhập ứng dụng Zalo trên máy tính thứ hai sẽ kết thúc phiên trên máy thứ nhất, và trình duyệt thứ hai cũng vậy. Quy tắc này do máy chủ của Zalo áp dụng, nên Zalo Switcher không gỡ bỏ được, và không ứng dụng nào trên máy tính của bạn gỡ được. Zalo không công bố con số chính thức và các bài viết trên mạng nói khác nhau; điều mô tả ở đây khớp với những gì bạn thấy trên tài khoản của mình.

Cách làm được là dùng cùng lúc các loại phiên khác nhau, ví dụ:

- điện thoại của bạn,
- ứng dụng Zalo trên máy tính A,
- [chat.zalo.me](https://chat.zalo.me) trong trình duyệt trên máy tính B (đăng nhập bằng mã QR từ điện thoại).

Cả ba vẫn đăng nhập cùng lúc. Hãy thử một lần trên tài khoản của bạn: đăng nhập trình duyệt trên máy B trong khi ứng dụng trên máy A đang mở, và kiểm tra máy A vẫn còn đăng nhập.

Zalo Switcher làm một việc khác: giữ **nhiều tài khoản khác nhau** trên **một** máy Mac và cho bạn đổi tài khoản mà ứng dụng Zalo đang mở.

**Ứng dụng không sao chép phiên đăng nhập sang máy tính khác.** Sao chép thư mục dữ liệu Zalo đã đăng nhập sang máy Mac thứ hai để cả hai chạy “cùng một” phiên không vượt qua được quy tắc trên. Máy chủ Zalo sẽ thấy một phiên kết nối từ hai nơi. Nhẹ thì một bản bị đăng xuất; nặng thì tài khoản bị đánh dấu có hoạt động bất thường. Rủi ro đó không đáng với tài khoản chính của bạn, nên dự án này không làm việc đó.

**Chỉ tài khoản đang mở trong Zalo mới nhận thông báo.** Các tài khoản khác vẫn đăng nhập trên máy chủ Zalo, nhưng trên máy Mac không có gì đang nghe tin nhắn cho chúng. Tin nhắn của chúng sẽ về khi bạn chuyển lại, giống như khi máy Mac tắt trong khoảng thời gian đó.

**Chuyển tài khoản sẽ khởi động lại Zalo.** Việc này mất vài giây. Nếu Zalo không chịu thoát (đang có cuộc gọi, hoặc đang mở một hộp thoại), việc chuyển sẽ dừng lại và chưa có gì bị di chuyển.

**Mỗi tài khoản chiếm dung lượng riêng.** Mỗi tài khoản giữ trọn bộ dữ liệu Zalo của riêng nó, thường vài GB trở lên, vì Zalo lưu dữ liệu như vậy.

**Ứng dụng phụ thuộc vào nơi Zalo lưu dữ liệu.** Zalo không có cách chính thức để chạy nhiều tài khoản, nên công cụ này làm việc với thư mục mà Zalo đang dùng hiện nay. Nếu một bản cập nhật của Zalo đổi thư mục đó, công cụ sẽ không tìm thấy nó và không di chuyển gì, cho tới khi được cập nhật.

**Mở hai cửa sổ cùng lúc vẫn đang thử nghiệm.** Xem [Mở song song](#mở-song-song-thử-nghiệm): gọi thoại và gọi video chỉ ổn định ở một cửa sổ.

**Bản tải về chưa được Apple công chứng (notarize).** macOS sẽ hiện cảnh báo bảo mật ở lần mở đầu tiên. Mục [Cảnh báo bảo mật ở lần mở đầu tiên](#cảnh-báo-bảo-mật-ở-lần-mở-đầu-tiên) giải thích lý do và cách mở.

## Cách chuyển tài khoản hoạt động

<p align="center"><img src="docs/screenshots/cach-hoat-dong.png" width="760" alt="Sơ đồ: thoát Zalo, đổi chỗ thư mục, mở lại Zalo"></p>

Zalo lưu mọi thứ (phiên đăng nhập, cơ sở dữ liệu tin nhắn, ảnh, tệp, cài đặt) trong một thư mục:

```
~/Library/Application Support/ZaloData        ← thư mục ứng dụng Zalo dùng
```

Zalo bỏ qua tùy chọn `--user-data-dir` quen thuộc và luôn dùng đường dẫn đó, nên Zalo Switcher giữ cho mỗi tài khoản một bản đầy đủ của thư mục này và đưa đúng bản vào chỗ:

```
~/Library/Application Support/Zalo Profiles/
    ca-nhan/profile.json
    ca-nhan/Library/Application Support/ZaloData     ← được cất ở đây khi tài khoản khác đang mở trong Zalo
    cong-ty/profile.json
    cong-ty/Library/Application Support/ZaloData
```

Khi chuyển sang tài khoản khác, ứng dụng:

1. Yêu cầu Zalo thoát (như khi bấm ⌘Q) và đợi đến khi Zalo cùng các tiến trình phụ đã đóng hẳn. Ứng dụng không bao giờ buộc Zalo thoát. Nếu Zalo không thoát, mọi thứ dừng lại và chưa có gì bị di chuyển.
2. Đổi tên `ZaloData` thành thư mục của tài khoản hiện tại.
3. Đổi tên thư mục của tài khoản cần chuyển sang thành `ZaloData`.
4. Mở Zalo, và Zalo mở ra với tài khoản đó, đã đăng nhập sẵn.

Mỗi bước chỉ là đổi tên thư mục trên cùng một ổ đĩa: mất chưa tới một giây dù thư mục lớn bao nhiêu, không tốn thêm dung lượng, và không bao giờ sao chép hay xóa gì. Ứng dụng còn từ chối:

- chuyển khi tài khoản đang mở trong Zalo chưa được lưu, để dữ liệu của nó không bị mất;
- thay thế bất cứ thứ gì ở nơi đến (nếu bất ngờ có một thư mục chắn đường, ứng dụng dừng lại);
- di chuyển dữ liệu sang ổ đĩa khác (vì như vậy là sao chép).

Xóa một tài khoản sẽ chuyển thư mục của nó vào Thùng rác, nơi bạn vẫn lấy lại được.

Toàn bộ quy tắc, kể cả định dạng tệp, có trong [docs/how-it-works.md](docs/how-it-works.md).

## Cài đặt

Bạn cần macOS 13 trở lên và ứng dụng Zalo cho máy tính. Zalo Switcher chạy trên máy Mac dùng chip Apple và chip Intel.

1. Tải tệp **Zalo-Switcher-…-macOS.zip** từ [bản phát hành mới nhất](https://github.com/ducngfi/zalo-multi-accounts/releases/latest).
2. Mở tệp zip (Safari tự mở giúp bạn) và kéo **Zalo Switcher.app** vào thư mục **Ứng dụng** (Applications).
3. Mở Zalo Switcher. Lần đầu tiên, macOS sẽ hiện cảnh báo bảo mật: xem mục ngay dưới.
4. Cửa sổ Zalo Switcher sẽ mở ra. Hãy [lưu tài khoản đầu tiên](#sử-dụng).

### Cảnh báo bảo mật ở lần mở đầu tiên

macOS cảnh báo với mọi ứng dụng chưa được Apple kiểm tra (công chứng). Muốn công chứng cần tài khoản Apple Developer trả phí, mà dự án miễn phí này không có, nên bạn sẽ thấy cảnh báo một lần. Cảnh báo không có nghĩa là macOS tìm thấy vấn đề trong ứng dụng. Toàn bộ mã nguồn nằm trong kho này; nếu không muốn tin bản tải về, bạn có thể [tự build](#tự-build).

**macOS 15 Sequoia trở lên, kể cả macOS 26 Tahoe:**

1. Mở ứng dụng. macOS báo không thể xác minh “Zalo Switcher” không chứa phần mềm độc hại. Bấm **Xong**, đừng bấm Chuyển vào Thùng rác.
2. Mở **Cài đặt hệ thống → Quyền riêng tư & Bảo mật** và cuộn xuống phần **Bảo mật**. Bên cạnh dòng báo “Zalo Switcher” đã bị chặn, bấm **Vẫn mở**.
3. Bấm **Vẫn mở** lần nữa trong hộp thoại hiện ra, rồi xác nhận bằng mật khẩu hoặc Touch ID.

**macOS 13 Ventura và 14 Sonoma:**

1. Trong Finder, mở **Ứng dụng**, giữ phím Control và bấm (hoặc bấm chuột phải) vào **Zalo Switcher**, chọn **Mở**.
2. Bấm **Mở** trong hộp thoại hiện ra.

**Mọi phiên bản, bằng Terminal:** lệnh này gỡ dấu “tải về từ internet” khiến macOS kiểm tra ứng dụng. Sau đó mở ứng dụng như bình thường.

```bash
xattr -dr com.apple.quarantine "/Applications/Zalo Switcher.app"
```

Bạn chỉ cần làm việc này một lần. macOS có thể hỏi lại khi bạn cài phiên bản mới.

### Công cụ dòng lệnh (không bắt buộc)

Tải tệp **zalo-profiles-…-macOS.zip** từ cùng bản phát hành và mở nó, để tệp `zalo-profiles` nằm trong thư mục Tải về (Downloads). Sau đó, trong Terminal:

```bash
mkdir -p ~/.local/bin
mv ~/Downloads/zalo-profiles ~/.local/bin/
xattr -c ~/.local/bin/zalo-profiles
```

Dòng cuối gỡ dấu tải về, nếu không macOS sẽ chặn lệnh. Nếu Terminal báo `command not found: zalo-profiles`, hãy thêm thư mục đó vào đường dẫn rồi mở cửa sổ Terminal mới:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

Để kiểm tra tệp tải về, chạy `shasum -a 256 -c SHA256SUMS.txt` trong thư mục chứa các tệp zip và tệp `SHA256SUMS.txt` của bản phát hành.

### Tự build

Bạn cần bộ công cụ lập trình của Apple để có `swift`: Xcode, hoặc Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ducngfi/zalo-multi-accounts.git
```

```bash
zalo-multi-accounts/macos/scripts/install.sh
```

Lệnh này build ứng dụng và công cụ dòng lệnh, cài `~/Applications/Zalo Switcher.app` và `~/.local/bin/zalo-profiles`, rồi mở ứng dụng. Ứng dụng tự build trên máy của bạn mở được ngay, không có cảnh báo bảo mật. Muốn build mà không cài, chạy `macos/scripts/build.sh` (kết quả nằm trong `macos/build/`).

## Sử dụng

### Mở cửa sổ Zalo Switcher

Cửa sổ tự mở khi bạn mở ứng dụng. Sau đó, bạn mở lại cửa sổ bằng bất kỳ cách nào sau:

- bấm biểu tượng **Zalo Switcher trong Dock**;
- mở Zalo Switcher từ **Launchpad**, **Spotlight** (⌘ Space, gõ “Zalo Switcher”) hoặc thư mục **Ứng dụng**;
- bấm biểu tượng hai người trên **thanh menu** ở đầu màn hình, rồi chọn **Mở cửa sổ Zalo Switcher…**

Trên MacBook có tai thỏ (notch), biểu tượng trên thanh menu có thể bị che khi thanh menu có nhiều biểu tượng. Vì vậy biểu tượng trong Dock được bật sẵn, và bạn luôn mở được cửa sổ bằng Dock, Launchpad hoặc Spotlight. Đóng cửa sổ không thoát ứng dụng; muốn thoát, chọn **Zalo Switcher → Thoát Zalo Switcher** (⌘Q).

### Lưu tài khoản đầu tiên và thêm tài khoản

1. Lần đầu mở, cửa sổ báo tài khoản đang mở trong Zalo chưa được lưu. Bấm **Lưu tài khoản này…** và đặt tên, ví dụ “Cá nhân”. Zalo vẫn chạy bình thường.
2. Bấm **Thêm tài khoản** và đặt tên cho tài khoản tiếp theo, ví dụ “Cửa hàng”. Zalo khởi động lại ở màn hình đăng nhập; hãy đăng nhập tài khoản đó một lần (mã QR hoặc mật khẩu).
3. Từ đó trở đi, bấm **Chuyển sang** ở tài khoản nào thì Zalo mở tài khoản đó. Tài khoản đang mở trong Zalo có nhãn **Đang dùng**.

Mỗi tài khoản hiện dung lượng, ID Zalo (bốn số cuối) và lần dùng gần nhất. Nút **⋯** của mỗi tài khoản có **Sao lưu…**, **Đổi tên…** và **Chuyển vào Thùng rác…**

Biểu tượng trên thanh menu và menu của biểu tượng trong Dock (bấm chuột phải) cũng liệt kê các tài khoản để chuyển nhanh bằng một cú bấm.

### Cài đặt

<p align="center"><img src="docs/screenshots/cai-dat.png" width="460" alt="Cửa sổ cài đặt"></p>

Bấm **Cài đặt** trong cửa sổ (hoặc ⌘,) để:

- bật hoặc tắt biểu tượng trong Dock và biểu tượng trên thanh menu (nếu tắt cả hai, bạn vẫn mở được ứng dụng từ Launchpad, Spotlight hoặc thư mục Ứng dụng);
- cho Zalo Switcher tự mở khi đăng nhập máy Mac (khi đó ứng dụng chạy nền, không hiện cửa sổ);
- chọn mức dung lượng trống mà dưới mức đó ứng dụng sẽ cảnh báo (mặc định 5 GB);
- mở thư mục các tài khoản đã lưu hoặc thư mục dữ liệu Zalo trong Finder.

Ứng dụng có cả giao diện sáng và tối, theo cài đặt của máy Mac:

<p align="center"><img src="docs/screenshots/cua-so-chinh-toi.png" width="560" alt="Cửa sổ Zalo Switcher ở giao diện tối"></p>

## Bản demo

Muốn xem thử hoặc giới thiệu ứng dụng mà không để lộ dữ liệu của mình, hãy mở bản demo:

```bash
open -n "/Applications/Zalo Switcher.app" --args --demo
```

Bản demo dùng bốn tài khoản giả lập (“Cá nhân”, “Cửa hàng Hoa Mai”, “Công ty An Phát”, “Shop mới”) trong một thư mục tạm. Mọi nút đều hoạt động thật trên dữ liệu giả lập đó: chuyển tài khoản, mở song song, sao lưu, khôi phục, đổi tên, xóa. Bản demo không bao giờ mở Zalo thật và không chạm tới dữ liệu Zalo của bạn, và cài đặt của nó được lưu riêng. Các ảnh chụp màn hình trong README này được tạo từ bản demo (xem [Ảnh minh họa](#ảnh-minh-họa)).

## Dùng bằng dòng lệnh

```bash
zalo-profiles status                 # tài khoản đang mở trong Zalo, mọi tài khoản, dung lượng, dung lượng trống
zalo-profiles save "Cá nhân"         # lưu tài khoản đang mở trong Zalo
zalo-profiles add "Cửa hàng"         # thêm tài khoản, khởi động lại Zalo ở màn hình đăng nhập
zalo-profiles switch ca-nhan         # chuyển (theo tên hoặc mã)
zalo-profiles switch cua-hang --no-launch
zalo-profiles rename cua-hang "Shop"
zalo-profiles remove cua-hang        # chuyển vào Thùng rác
zalo-profiles open cua-hang          # mở song song (thử nghiệm)
zalo-profiles close cua-hang         # đóng cửa sổ đang mở "cua-hang"
zalo-profiles backup ca-nhan /Volumes/OCung
zalo-profiles restore "/Volumes/OCung/Zalo Backups/ca-nhan 2026-10-20 21.00" "Cá nhân (khôi phục)"
zalo-profiles paths
```

Mã của tài khoản là tên viết không dấu, ví dụ “Cá nhân” → `ca-nhan`; bạn cũng có thể gõ tên đầy đủ trong dấu ngoặc kép.

## Dung lượng ổ đĩa

Dung lượng của từng tài khoản và dung lượng trống của máy Mac hiện trong cửa sổ, trong menu và trong `zalo-profiles status`. Khi dung lượng trống dưới 5 GB (hoặc mức bạn chọn trong Cài đặt):

- cửa sổ hiện cảnh báo và biểu tượng trên thanh menu đổi thành hình tam giác cảnh báo;
- thêm tài khoản hoặc mở song song sẽ hỏi trước. Trong dòng lệnh, `add` và `open` từ chối chạy trừ khi bạn thêm `--force`.

Zalo ghi tin nhắn và ảnh ngay khi chúng đến, nên ổ đĩa đầy là nguyên nhân chính khiến dữ liệu Zalo có thể bị hỏng. Bản thân việc chuyển tài khoản không cần dung lượng trống, vì chỉ đổi tên thư mục.

## Sao lưu và khôi phục

<p align="center"><img src="docs/screenshots/sao-luu.png" width="560" alt="Đang sao lưu một tài khoản"></p>

**⋯ → Sao lưu…** ở một tài khoản (hoặc `zalo-profiles backup <tài khoản> <thư mục>`) sao chép toàn bộ dữ liệu Zalo của tài khoản đó vào thư mục bạn chọn, thường là một ổ cứng ngoài. Bản sao lưu nằm trong `Zalo Backups/<tài khoản> <ngày giờ>/` trên ổ đó:

1. Nếu Zalo đang mở tài khoản đó, cửa sổ Zalo ấy tạm đóng vài giây, để cơ sở dữ liệu được ghi trọn vẹn chứ không dở dang.
2. Ứng dụng chụp nhanh dữ liệu bằng APFS: một bản sao tức thì, dùng chung dung lượng với bản gốc nên gần như không tốn gì.
3. Zalo tự mở lại. Mọi cửa sổ Zalo khác vẫn chạy suốt quá trình.
4. Ứng dụng sao chép bản chụp sang ổ đĩa ở chế độ chạy ngầm và kiểm tra từng tệp có đúng kích thước với bản gốc. Trong lúc đó bạn vẫn dùng và chuyển tài khoản Zalo bình thường.

   Zalo lưu nhiều ảnh và video dưới hai tên dùng chung một dữ liệu (liên kết cứng), thường lên tới vài GB. Bản sao lưu chép phần dữ liệu đó một lần và tạo lại tên thứ hai dưới dạng liên kết, nên bản sao lưu có dung lượng bằng đúng bản gốc. Bản chụp APFS làm mất các liên kết này, nên ứng dụng đọc chúng từ bản gốc trong lúc Zalo vẫn đang đóng. Trên ổ đĩa không hỗ trợ liên kết cứng (exFAT, FAT), mỗi tên được chép thành một bản riêng, nên bản sao lưu sẽ lớn hơn.
5. Chỉ khi mọi tệp đều khớp, thư mục mới được đặt tên chính thức và có tệp ghi chép `backup.json`. Bản sao lưu bị lỗi hoặc bị hủy sẽ được xóa chứ không để lại dở dang, và bản chụp luôn được xóa khi xong.

Trước khi bắt đầu, ứng dụng kiểm tra ổ đĩa còn đủ chỗ. Ứng dụng từ chối các thư mục nằm trong dữ liệu của Zalo, và cảnh báo nếu thư mục nằm trên ổ đĩa của chính máy Mac, vì bản sao lưu ở đó không bảo vệ được khi ổ đĩa hỏng.

**Khôi phục…** ở đầu cửa sổ (hoặc `zalo-profiles restore <thư mục sao lưu> <tên>`) khôi phục một bản sao lưu thành một tài khoản **mới**. Không bao giờ thay thế tài khoản đang có. Bản sao được kiểm tra với `backup.json` trước khi tài khoản xuất hiện. Máy Mac cần đủ chỗ cho bản sao lưu cộng thêm 5 GB dự phòng.

Tài khoản khôi phục là cùng một tài khoản Zalo với tài khoản đã được sao lưu. Khi tài khoản gốc vẫn còn, đừng mở cả hai cùng lúc; `status` sẽ nhắc điều này. Nếu từ lúc sao lưu tài khoản đã đăng nhập ở nơi khác, Zalo có thể yêu cầu đăng nhập lại.

Đã thử ngày 20/10/2026 với một ổ cứng ngoài APFS:

| Tài khoản | Số tệp | Dữ liệu | Zalo tạm đóng | Tổng thời gian |
|---|---|---|---|---|
| Đang mở ở cửa sổ thứ hai | 508 | 455 MB | dưới 2 giây | 1,9 giây |
| Đang mở trong Zalo chính | 48.056 (13.799 tệp là liên kết cứng) | 13,75 GB | khoảng 15 giây | 75 giây |

- Cả hai lần Zalo đều tự mở lại và vẫn đăng nhập, còn cửa sổ kia không bị gián đoạn.
- Bản sao lưu nhỏ hơn được khôi phục thành một tài khoản thử, trong lúc tài khoản gốc đã đóng, và mở ra vẫn đăng nhập.

## Mở song song (thử nghiệm)

<p align="center"><img src="docs/screenshots/song-song.png" width="860" alt="Hai cửa sổ Zalo của hai tài khoản chạy cùng lúc, với cửa sổ Zalo Switcher ở giữa"></p>
<p align="center"><sub>Minh họa với dữ liệu giả lập.</sub></p>

**Mở song song** ở một tài khoản đã lưu sẽ mở thêm một cửa sổ Zalo thứ hai trong khi Zalo chính vẫn chạy, để hai tài khoản cùng trực tuyến. Zalo thứ hai được mở với `CFFIXED_USER_HOME` trỏ tới thư mục của tài khoản đó. Nhờ vậy macOS cho nó một thư mục Application Support riêng, nên nó đọc và ghi `ZaloData` của chính tài khoản đó và không bao giờ chạm tới Zalo chính. Thư mục tài khoản có các liên kết tới Keychain thật của bạn (nơi Zalo giữ khóa mã hóa), cùng Tải về, Màn hình nền, Tài liệu, Ảnh, Phim và Nhạc.

Ở tài khoản đang mở song song, **Hiện** đưa cửa sổ đó lên trước, **Đóng cửa sổ** thoát cửa sổ đó (như ⌘Q trong cửa sổ đó). Bạn cũng có thể **Thêm tài khoản → Thêm ở cửa sổ Zalo thứ hai…** để đăng nhập tài khoản mới mà không phải đóng Zalo chính.

Giới hạn đã biết:

- **Cuộc gọi.** Phần gọi điện của Zalo liên lạc với ứng dụng qua các tệp socket cố định (`/tmp/socketzalosend2021`, `/tmp/socketzalorecv2021`). Mỗi Zalo mở lên sẽ chiếm các tệp này, nên gọi thoại và gọi video chỉ ổn định ở một cửa sổ, và Zalo chính có thể cần khởi động lại thì mới gọi được. Trước một cuộc gọi quan trọng, hãy đóng các cửa sổ mở song song và khởi động lại Zalo.
- Hai cửa sổ có cùng biểu tượng Zalo trong Dock. Hãy phân biệt bằng tên tài khoản trên thanh tiêu đề (“Zalo - <tên tài khoản>”) hoặc ảnh đại diện.
- Không thể chuyển sang hay xóa một tài khoản đang mở song song cho tới khi bạn đóng cửa sổ của nó.

Đã thử ngày 20/10/2026 với Zalo 26.8.20 trên macOS 26.1, một tài khoản trong Zalo chính và một tài khoản mở song song:

- Tài khoản thứ hai mở ra đã đăng nhập sẵn.
- Mỗi Zalo chỉ có dữ liệu của tài khoản mình. Cửa sổ thứ hai mở 163 tệp, tất cả nằm trong thư mục tài khoản của nó, không tệp nào trong `ZaloData` chính.
- Zalo chính vẫn chạy, không phải khởi động lại.
- Zalo thứ hai đúng là chiếm các socket gọi điện như dự đoán. Chưa thử gọi điện.

## Lưu ý thêm

- Tệp nhận được của mọi tài khoản đều vào thư mục Tải về như bình thường.
- Nếu một bản cập nhật Zalo đổi thư mục dữ liệu, `zalo-profiles status` sẽ không tìm thấy nó nữa. Khi đó không có gì bị di chuyển.
- Muốn thôi dùng Zalo Switcher: chuyển sang tài khoản bạn muốn giữ trong Zalo, thoát Zalo Switcher và xóa ứng dụng. Zalo tiếp tục với tài khoản đó. Dữ liệu của các tài khoản khác vẫn nằm trong `~/Library/Application Support/Zalo Profiles/<mã>/Library/Application Support/ZaloData`.

### Ảnh minh họa

Mọi ảnh trong README này chỉ dùng dữ liệu giả lập. Các ảnh cửa sổ Zalo Switcher do chính ứng dụng vẽ ra từ bản demo; ảnh mở song song và sơ đồ được dựng bằng HTML trong [`docs/screenshots/src`](docs/screenshots/src). Để tạo lại tất cả:

```bash
docs/screenshots/make-screenshots.sh
```

## Cấu trúc dự án

```
macos/              ứng dụng macOS và công cụ dòng lệnh (Swift package)
windows/            dành cho ứng dụng Windows sau này (chưa bắt đầu)
docs/               cách hoạt động của tài khoản và việc chuyển đổi, giống nhau trên mọi nền tảng
docs/screenshots/   ảnh minh họa của README và cách tạo lại chúng
assets/icon/        biểu tượng ứng dụng: bản gốc SVG và các biểu tượng đã xuất cho macOS và Windows
```

Mỗi nền tảng giữ mã nguồn, script build và kiểm thử trong thư mục riêng. Phần dùng chung là cách hoạt động và định dạng tệp trong [docs/how-it-works.md](docs/how-it-works.md), cùng biểu tượng trong `assets/icon/`. Cách build và kiểm thử bản macOS có trong [macos/README.md](macos/README.md).

## Giấy phép

[MIT](LICENSE). Phần mềm được cung cấp “nguyên trạng”, không có bất kỳ bảo hành nào.
