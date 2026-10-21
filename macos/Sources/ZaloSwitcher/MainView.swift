import SwiftUI
import ZaloProfilesCore

/// The main window: every saved account, which ones are open, and what can be done with each.
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
                    Text("Mỗi tài khoản chạy trong một cửa sổ Zalo riêng, cùng lúc với các tài khoản khác, và không cần đăng nhập lại. “Zalo chính” là tài khoản mở ra khi bạn bấm biểu tượng Zalo trong Dock. Gọi thoại và gọi video chỉ ổn định ở một cửa sổ Zalo tại một thời điểm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
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
            .lineLimit(1)
            Spacer(minLength: 12)
            Menu {
                Button("Thêm tài khoản mới…") { model.addAccount() }
                Button("Khôi phục từ bản sao lưu…") { model.restore() }
                    .disabled(model.copying != nil)
            } label: {
                Label("Thêm tài khoản", systemImage: "plus")
            } primaryAction: {
                model.addAccount()
            }
            .fixedSize()
            .disabled(model.busy != nil)
            Menu {
                Button("Mở mọi tài khoản đã đăng nhập") { model.openAll() }
                    .disabled(model.closedCount == 0)
                Button("Đóng mọi cửa sổ Zalo…") { model.closeAll() }
                    .disabled(model.openCount == 0)
            } label: {
                Label("Mở tất cả", systemImage: "rectangle.stack")
            } primaryAction: {
                model.openAll()
            }
            .fixedSize()
            .disabled(model.busy != nil || model.statuses.isEmpty)
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
                   text: "Zalo chính đang giữ một tài khoản chưa được lưu nên tài khoản đó chưa có trong danh sách. Hãy lưu để quản lý, sao lưu và mở nó cùng các tài khoản khác.") {
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
            Avatar(name: status.profile.name, isOpen: status.isOpen)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(status.profile.name).font(.headline)
                    stateBadge
                    if status.place == .main {
                        Badge(text: "Zalo chính", color: .blue)
                            .help("Tài khoản mở ra khi bạn bấm biểu tượng Zalo trong Dock, Launchpad, hoặc khi Zalo tự mở cùng máy Mac.")
                    }
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
                .strokeBorder(status.isOpen ? Color.green.opacity(0.6) : Color.primary.opacity(0.08),
                              lineWidth: status.isOpen ? 1.5 : 1)
        )
    }

    private var stateBadge: Badge {
        if status.isOpen { return Badge(text: "Đang mở", color: .green) }
        if status.place == .new { return Badge(text: "Chưa đăng nhập", color: .orange) }
        return Badge(text: "Đã đóng", color: .gray)
    }

    private var details: String {
        var parts: [String] = []
        if let size = model.sizes[status.profile.id] { parts.append(Disk.format(size)) }
        if let uid = status.zaloUserID { parts.append("ID Zalo …\(uid.suffix(4))") }
        if status.place == .new { parts.append("Đăng nhập một lần khi mở lần đầu") }
        if let used = status.profile.lastUsedAt, !status.isOpen, status.place != .new {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = AppModel.vietnamese
            parts.append("Mở gần nhất \(formatter.localizedString(for: used, relativeTo: Date()))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            if status.isOpen {
                Button("Hiện") { model.open(status) }
                Button("Đóng") { model.close(status) }
            } else {
                Button(status.place == .new ? "Mở để đăng nhập" : "Mở") { model.open(status) }
                    .buttonStyle(.borderedProminent)
            }
            Menu {
                Button("Sao lưu…") { model.backUp(status) }
                    .disabled(status.place == .new || model.copying != nil)
                Button("Đổi tên…") { model.rename(status) }
                Button("Đặt làm Zalo chính…") { model.makeMain(status) }
                    .disabled(status.place == .main)
                Divider()
                Button("Chuyển vào Thùng rác…") { model.remove(status) }
                    .disabled(status.place == .main || status.isOpen)
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

/// A small coloured label next to an account's name.
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
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

/// A round badge with the account's initials, in a colour that stays the same for a name, and a
/// green dot while the account is open.
struct Avatar: View {
    let name: String
    var isOpen = false

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
            .overlay(alignment: .bottomTrailing) {
                if isOpen {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
                }
            }
    }
}
