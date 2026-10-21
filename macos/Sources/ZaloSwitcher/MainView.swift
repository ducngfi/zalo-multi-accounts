import SwiftUI
import ZaloProfilesCore

/// The main window: the account in Zalo now, every saved account, and what can be done with each.
struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    banners
                    if model.statuses.isEmpty {
                        Text("Chưa có tài khoản nào. Bấm “Thêm tài khoản” để bắt đầu.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                    ForEach(model.statuses, id: \.profile.id) { status in
                        AccountRow(model: model, status: status)
                    }
                    Text("Mỗi lần chuyển tài khoản, Zalo khởi động lại trong vài giây và không cần đăng nhập lại. Khi mở song song, gọi thoại và gọi video chỉ ổn định ở một cửa sổ Zalo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .sheet(isPresented: $model.showingSettings) {
            SettingsView(model: model, settings: settings)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.headline)
                    .font(.title2.weight(.semibold))
                Text(model.subheadline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Menu {
                Button("Thêm và chuyển sang tài khoản mới…") { model.addAccount() }
                Button("Thêm ở cửa sổ Zalo thứ hai…") { model.addAccountSideBySide() }
            } label: {
                Label("Thêm tài khoản", systemImage: "plus")
            } primaryAction: {
                model.addAccount()
            }
            .fixedSize()
            .disabled(model.busy != nil)
            Button {
                model.restore()
            } label: {
                Label("Khôi phục…", systemImage: "clock.arrow.circlepath")
            }
            .disabled(model.busy != nil || model.copying != nil)
            Button {
                model.showingSettings = true
            } label: {
                Label("Cài đặt", systemImage: "gearshape")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder private var banners: some View {
        if model.isDemo {
            Banner(symbol: "theatermasks", tint: .blue,
                   text: "Bản demo với dữ liệu giả lập. Mọi thao tác chỉ diễn ra trong một thư mục tạm, không chạm tới Zalo thật trên máy này.")
        }
        if model.mainSlot == .unsaved {
            Banner(symbol: "exclamationmark.circle", tint: .orange,
                   text: "Tài khoản đang mở trong Zalo chưa được lưu. Hãy lưu trước khi chuyển, để tin nhắn và tệp của nó được giữ lại.") {
                Button("Lưu tài khoản này…") { model.saveCurrent() }
            }
        }
        if model.lowSpace, let free = model.freeSpace {
            Banner(symbol: "exclamationmark.triangle", tint: .red,
                   text: "Ổ đĩa chỉ còn trống \(Disk.format(free)). Zalo cần chỗ để lưu tin nhắn và ảnh; hãy giải phóng dung lượng trước khi thêm hoặc mở thêm tài khoản.")
        }
        if let busy = model.busy {
            Banner(symbol: nil, tint: .accentColor, text: busy)
        }
        if let copying = model.copying {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "externaldrive")
                    Text(copying).lineLimit(1)
                    Spacer()
                    Button("Hủy") { model.cancelCopy() }
                }
                ProgressBar(fraction: model.copyProgress ?? 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.10)))
        }
    }
}

/// One saved account.
struct AccountRow: View {
    @ObservedObject var model: AppModel
    let status: ProfileStatus

    var body: some View {
        HStack(spacing: 14) {
            Avatar(name: status.profile.name)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(status.profile.name).font(.headline)
                    badge
                }
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(status.place == .main ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08),
                              lineWidth: status.place == .main ? 1.5 : 1)
        )
    }

    private var badge: some View {
        let (text, color): (String, Color) = {
            switch status.place {
            case .main: return status.runningPID != nil ? ("Đang dùng", .green) : ("Zalo chính · chưa mở", .green)
            case .parked: return status.isOpenSideBySide ? ("Cửa sổ thứ hai", .blue) : ("Đã lưu", .gray)
            case .new: return ("Chưa đăng nhập", .orange)
            }
        }()
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var details: String {
        var parts: [String] = []
        if let size = model.sizes[status.profile.id] { parts.append(Disk.format(size)) }
        if let uid = status.zaloUserID { parts.append("ID Zalo …\(uid.suffix(4))") }
        if status.place == .new { parts.append("Đăng nhập một lần khi mở lần đầu") }
        if let used = status.profile.lastUsedAt, status.place == .parked, !status.isOpenSideBySide {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = AppModel.vietnamese
            parts.append("Dùng gần nhất \(formatter.localizedString(for: used, relativeTo: Date()))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            switch status.place {
            case .main:
                Button(model.mainRunning ? "Hiện Zalo" : "Mở Zalo") { model.openZalo() }
            case .parked where status.isOpenSideBySide:
                Button("Hiện") { model.openSideBySide(status) }
                Button("Đóng cửa sổ") { model.close(status) }
            case .parked, .new:
                Button("Chuyển sang") { model.switchTo(status) }
                    .buttonStyle(.borderedProminent)
                Button("Mở song song") { model.openSideBySide(status) }
            }
            Menu {
                Button("Sao lưu…") { model.backUp(status) }
                    .disabled(status.place == .new || model.copying != nil)
                Button("Đổi tên…") { model.rename(status) }
                Divider()
                Button("Chuyển vào Thùng rác…") { model.remove(status) }
                    .disabled(status.place == .main || status.isOpenSideBySide)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .disabled(model.busy != nil)
    }
}

/// A notice above the accounts.
struct Banner<Trailing: View>: View {
    let symbol: String?
    let tint: Color
    let text: String
    let trailing: Trailing

    init(symbol: String?, tint: Color, text: String, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.tint = tint
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(tint)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.10)))
    }
}

extension Banner where Trailing == EmptyView {
    init(symbol: String?, tint: Color, text: String) {
        self.init(symbol: symbol, tint: tint, text: text) { EmptyView() }
    }
}

/// A thin progress bar. Drawn by SwiftUI rather than AppKit, so it also shows in the screenshots.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.accentColor)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

/// A round badge with the account's initials, in a colour that stays the same for a name.
struct Avatar: View {
    let name: String

    private static let colors: [Color] = [.blue, .teal, .orange, .pink, .purple, .green, .indigo, .red]

    var body: some View {
        let words = name.split(separator: " ")
        let initials = [words.first, words.count > 1 ? words.last : nil]
            .compactMap { $0?.first.map { String($0).uppercased() } }
            .joined()
        let index = name.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 997 } % Self.colors.count
        return Text(initials)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(Circle().fill(Self.colors[index].gradient))
    }
}
