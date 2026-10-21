import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    /// Drawn on its own for the screenshots, without the Done button's sheet.
    var showsDoneButton = true

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Cách mở Zalo Switcher") {
                    Toggle("Hiện biểu tượng trong Dock", isOn: $settings.showDockIcon)
                    Toggle("Hiện biểu tượng trên thanh menu", isOn: $settings.showMenuBarIcon)
                    Text("Trên MacBook có tai thỏ (notch), biểu tượng trên thanh menu có thể bị che khi thanh menu có nhiều biểu tượng. Khi đó hãy mở cửa sổ này bằng biểu tượng trong Dock, hoặc mở Zalo Switcher từ Launchpad hay Spotlight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !settings.showDockIcon && !settings.showMenuBarIcon {
                        Label("Cả hai biểu tượng đều đang tắt. Bạn vẫn mở được cửa sổ này bằng cách mở Zalo Switcher từ Launchpad, Spotlight hoặc thư mục Ứng dụng.",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Khởi động") {
                    Toggle("Mở Zalo Switcher khi đăng nhập máy Mac", isOn: Binding(
                        get: { settings.openAtLogin },
                        set: { on in
                            do { try settings.setOpenAtLogin(on) } catch { Prompt.error(error) }
                        }))
                    Text("Khi tự mở cùng máy Mac, ứng dụng chạy nền và không hiện cửa sổ.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Dung lượng") {
                    Stepper(value: $settings.lowSpaceGB, in: 1...100) {
                        Text("Cảnh báo khi ổ đĩa còn trống dưới \(settings.lowSpaceGB) GB")
                    }
                    Text("Khi ổ đĩa gần đầy, Zalo có thể không lưu được tin nhắn. Dưới mức này, ứng dụng sẽ hỏi trước khi thêm hoặc mở thêm tài khoản.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Dữ liệu") {
                    LabeledContent("Các tài khoản đã lưu") {
                        Button("Mở trong Finder") { model.showProfilesFolder() }
                    }
                    LabeledContent("Dữ liệu Zalo đang dùng") {
                        Button("Mở trong Finder") { model.showZaloDataFolder() }
                    }
                }
                Section {
                    LabeledContent("Phiên bản", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    Text("Zalo Switcher là dự án độc lập, không liên kết với Zalo hay VNG.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if showsDoneButton {
                Divider()
                HStack {
                    Spacer()
                    Button("Xong") { model.showingSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(14)
            }
        }
        .frame(width: 560, height: showsDoneButton ? 640 : 720)
    }
}
