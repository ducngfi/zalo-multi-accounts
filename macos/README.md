# Zalo Switcher cho macOS

Ứng dụng macOS và công cụ dòng lệnh, trong cùng một Swift package. Cách cài và dùng có trong [README chính](../README.md); các quy tắc mà chúng tuân theo có trong [docs/how-it-works.md](../docs/how-it-works.md).

## Build và kiểm thử

Bạn cần macOS 13 trở lên và Xcode hoặc Command Line Tools. Chạy các lệnh sau trong thư mục này:

```bash
swift build
swift test            # chạy logic hồ sơ với một Zalo giả trong thư mục tạm
scripts/build.sh      # build "Zalo Switcher.app" và zalo-profiles vào build/
scripts/install.sh    # build, cài vào ~/Applications và ~/.local/bin, rồi mở ứng dụng
scripts/release.sh    # build và đóng gói các tệp zip cùng mã kiểm tra cho một bản phát hành GitHub vào build/release/
```

Tệp chạy là bản universal (chip Apple và Intel). Ứng dụng có chữ ký ad-hoc nên chạy được trên máy Mac đã build nó. Ứng dụng không được ký bằng Developer ID hay công chứng, nên bản tải về sẽ hiện cảnh báo bảo mật ở lần mở đầu tiên ([README chính](../README.md#cảnh-báo-bảo-mật-ở-lần-mở-đầu-tiên) có giải thích).

Giao diện chỉ có tiếng Việt. `scripts/build.sh` khai báo ứng dụng là tiếng Việt (`CFBundleDevelopmentRegion` và `vi.lproj`), nên các hộp thoại của hệ thống như hộp chọn thư mục cũng hiện bằng tiếng Việt.

## Bản demo và ảnh chụp màn hình

```bash
open -n "build/Zalo Switcher.app" --args --demo    # chạy thử với bốn tài khoản giả lập
../docs/screenshots/make-screenshots.sh           # tạo lại mọi ảnh của README từ dữ liệu giả lập
```

## Phát hành

1. Tăng `VERSION` và `BUILD` ở đầu `scripts/build.sh`, và `Version` trong [`windows/Directory.Build.props`](../windows/Directory.Build.props) lên cùng số đó.
2. Chạy `scripts/release.sh`.
3. Commit, push, và đăng các tệp: `gh release create v<phiên bản> build/release/* --title "Zalo Switcher <phiên bản>" --notes-file <ghi chú>`, với ghi chú theo [mẫu bên dưới](#ghi-chú-phát-hành); vài phút sau, GitHub Actions tự thêm các tệp Windows vào bản phát hành này (xem [windows/README.md](../windows/README.md#phát-hành)).
4. Sửa ghi chú của bản trước còn vài dòng: “Bản cũ. Hãy dùng [bản mới nhất](https://github.com/ducngfi/zalo-multi-accounts/releases/latest).”, một câu nói bản đó có gì, và tên tệp cần tải.

### Ghi chú phát hành

Giữ ghi chú ngắn, để người dùng thấy ngay mục **Assets** ngay bên dưới. Hướng dẫn cài, cách vượt cảnh báo bảo mật, ảnh minh họa và giới hạn đã có trong [README chính](../README.md), nên chỉ dẫn liên kết tới đó, không chép lại. Mẫu (thay `X.Y.Z`):

```markdown
<Một câu: ứng dụng làm gì.> Có cho Mac và Windows.

| Máy của bạn | Tải tệp này trong **Assets** ngay bên dưới |
|---|---|
| **Mac** (macOS 13 trở lên) | **Zalo-Switcher-X.Y.Z-macOS.zip** |
| **Windows** (Windows 10 trở lên) | **ZaloSwitcher-Setup-X.Y.Z.exe** |

Cách cài và cách mở lần đầu: [Mac](https://github.com/ducngfi/zalo-multi-accounts#cài-đặt) · [Windows](https://github.com/ducngfi/zalo-multi-accounts#windows). Các tệp còn lại không bắt buộc: công cụ dòng lệnh, bản Windows chạy không cần cài, và mã kiểm tra.

**Có gì mới**

- <Tối đa ba hoặc bốn dòng, mỗi dòng một thay đổi người dùng thấy được.>
- Nâng cấp từ bản cũ: các tài khoản đã lưu vẫn giữ nguyên.

<sub>Dự án độc lập, không liên kết với Zalo hay VNG. Bạn tự chịu rủi ro khi sử dụng. Xem [giới hạn](https://github.com/ducngfi/zalo-multi-accounts#giới-hạn-và-vì-sao-có-các-giới-hạn-đó) trước khi dùng.</sub>
```

## Mã nguồn

- `Sources/ZaloProfilesCore`: lưu trữ hồ sơ, mở và đóng từng tài khoản trong Zalo riêng, đặt Zalo chính, sao lưu, điều khiển tiến trình Zalo, và dữ liệu giả lập cho bản demo.
- `Sources/zalo-profiles`: công cụ dòng lệnh.
- `Sources/ZaloSwitcher`: ứng dụng AppKit với giao diện SwiftUI: cửa sổ chính (`MainView`), cài đặt (`SettingsView`), biểu tượng thanh menu và menu Dock (`Menus.swift`), và phần vẽ ảnh chụp màn hình (`Screenshots.swift`).
- `Tests/ZaloProfilesCoreTests`: kiểm thử cho phần lõi.
- `Resources/AppIcon.icns`: biểu tượng ứng dụng, xuất từ [`assets/icon/AppIcon.svg`](../assets/icon/AppIcon.svg) bằng `assets/icon/make-icons.sh`. Hãy sửa tệp SVG, không sửa tệp này.
