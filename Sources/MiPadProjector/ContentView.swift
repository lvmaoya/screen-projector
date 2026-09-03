import SwiftUI
import AppKit

private enum AppSection: String, CaseIterable, Identifiable {
    case projection = "投屏"
    case wireless = "连接"
    case quality = "设置"
    case about = "关于"
    var id: Self { self }
    var icon: String {
        switch self {
        case .projection: return "rectangle.on.rectangle"
        case .wireless: return "link"
        case .quality: return "slider.horizontal.3"
        case .about: return "info"
        }
    }
    var iconColors: [Color] {
        switch self {
        case .projection: return [Color(red: 0.55, green: 0.45, blue: 1), Color(red: 0.36, green: 0.25, blue: 0.96)]
        case .wireless: return [Color(red: 0.16, green: 0.68, blue: 1), Color(red: 0.02, green: 0.46, blue: 0.91)]
        case .quality: return [Color(red: 0.32, green: 0.34, blue: 0.38), Color(red: 0.08, green: 0.09, blue: 0.11)]
        case .about: return [Color(red: 0.70, green: 0.72, blue: 0.76), Color(red: 0.47, green: 0.49, blue: 0.53)]
        }
    }
}

private struct SidebarIcon: View {
    let symbol: String
    let colors: [Color]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

struct ContentView: View {
    @StateObject private var model = ProjectorViewModel()
    @State private var section: AppSection? = .projection
    @State private var showingDeveloperGuide = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac投屏").font(.headline)
                        Text("版本 1.0.0").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

                List(AppSection.allCases, selection: $section) { item in
                    HStack(spacing: 7) {
                        SidebarIcon(symbol: item.icon, colors: item.iconColors)
                        Text(item.rawValue)
                    }
                    .tag(Optional(item))
                }
            }
            .navigationTitle("Mac投屏")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Group {
                switch section ?? .projection {
                case .projection: projectionView
                case .wireless: wirelessView
                case .quality: qualityView
                case .about: aboutView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle((section ?? .projection).rawValue)
            .toolbar { toolbarContent }
        }
        .frame(minWidth: 760, minHeight: 540)
        .sheet(isPresented: $showingDeveloperGuide) { developerGuide }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if section == .projection || section == .wireless {
                Button { Task { await model.refreshDevices() } } label: {
                    Label("刷新设备", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
            }
            if section == .projection {
                Button { Task { await model.startProjection() } } label: {
                    Label("开始投屏", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!selectedDeviceIsReady || model.isBusy || !model.dependenciesReady)
            }
        }
    }

    private var projectionView: some View {
        Group {
            if !model.dependenciesReady {
                messageView(icon: "exclamationmark.triangle", title: "应用包不完整", detail: "缺少内置投屏组件，请重新获取完整的应用。", color: .orange)
            } else {
                Form {
                    Section("已连接设备") {
                        if model.devices.isEmpty {
                            Text("未发现设备").foregroundStyle(.secondary)
                        }
                        ForEach(model.devices) { device in
                            Button {
                                model.selectedID = device.id
                            } label: {
                                deviceRow(device)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private var wirelessView: some View {
        Form {
            Section {
                Text("无线连接要求设备已开启“开发者选项 → 无线调试”，并与 Mac 处于同一个局域网。访客网络、公共 Wi-Fi 或开启设备隔离的路由器可能导致无法连接。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("通过 USB 建立连接") {
                Text("USB 设备授权后会直接出现在“投屏”页面，也可以继续开启无线连接。").foregroundStyle(.secondary)
                Picker("USB 设备", selection: $model.selectedID) {
                    Text("选择设备").tag(String?.none)
                    ForEach(model.devices) { Text($0.displayName).tag(Optional($0.id)) }
                }
                HStack {
                    Spacer()
                    Button("开启无线调试") { Task { await model.enableWireless() } }
                        .disabled(model.selectedID == nil || model.isBusy)
                }
            }
            Section("通过配对码建立连接") {
                Text("用于首次建立信任。请在设备的“无线调试 → 使用配对码配对设备”中查看配对地址和配对码；配对完成后仍需通过下方地址建立连接。")
                    .foregroundStyle(.secondary)
                TextField("配对地址，例如 192.168.1.20:37123", text: $model.pairingAddress)
                    .textFieldStyle(.roundedBorder)
                SecureField("六位配对码", text: $model.pairingCode).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("配对并连接") { Task { await model.pairWireless() } }
                        .disabled(model.pairingAddress.trimmingCharacters(in: .whitespaces).isEmpty || model.pairingCode.isEmpty || model.isBusy)
                }
            }
            Section("通过地址建立连接") {
                Text("用于连接已经配对，或已通过 USB 开启无线调试的设备。请填写无线调试主页面显示的 IP 地址和端口。")
                    .foregroundStyle(.secondary)
                TextField("设备 IP 或 IP:端口", text: $model.address).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("连接") { Task { await model.connectWireless() } }.buttonStyle(.borderedProminent)
                        .disabled(model.address.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
                }
            }
            if shouldShowStatus {
                Section {
                    HStack(spacing: 8) {
                        if model.isBusy { ProgressView().controlSize(.small) }
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var qualityView: some View {
        Form {
            Section("画面") {
                Picker("分辨率", selection: $model.maxSize) {
                    Text("流畅（1280p）").tag("1280")
                    Text("均衡（1920p）").tag("1920")
                    Text("设备原始分辨率").tag("0")
                }
                Picker("视频码率", selection: $model.bitrate) {
                    Text("8 Mbps").tag("8M"); Text("12 Mbps").tag("12M"); Text("20 Mbps").tag("20M")
                }
            }
            Section("设备控制") {
                Toggle("投屏时关闭设备屏幕", isOn: $model.turnScreenOff)
                LabeledContent("键盘与鼠标") { Text("投屏窗口内可直接控制").foregroundStyle(.secondary) }
            }
            Section {
                Text("更高分辨率和码率会增加局域网带宽与设备功耗。推荐使用 1920p 和 12 Mbps。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var aboutView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                Text("Mac投屏").font(.title2.bold())
                Text("版本 1.0.0").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 36)

            Form {
                Section("功能") {
                    Text("通过 USB 或局域网将设备低延迟投屏到 Mac，并支持键盘与鼠标控制。")
                }
                Section("使用说明") {
                    HStack(alignment: .center, spacing: 12) {
                        instructionNumber(1)
                        Text("在设备的开发者选项中开启 USB 调试；使用无线连接时还需开启无线调试。")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button("如何打开开发者模式") { showingDeveloperGuide = true }
                            .buttonStyle(.link)
                    }
                    .padding(.vertical, 2)
                    instructionRow(2, "打开“连接”页面，通过 USB、配对码或设备地址建立连接。")
                    instructionRow(3, "进入“投屏”页面，从已连接设备中选择需要投屏的设备。")
                }
                Section {
                    Label("使用完成后，建议关闭设备的 USB 调试和无线调试。", systemImage: "lock.shield")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("隐私") {
                    Text("所有连接和屏幕数据仅在设备与这台 Mac 之间传输，不会上传到云端。")
                        .foregroundStyle(.secondary)
                }
                Section("内置开源组件") {
                    Link(destination: URL(string: "https://github.com/Genymobile/scrcpy")!) {
                        componentRow("scrcpy", version: "4.1")
                    }
                    .buttonStyle(.plain)
                    Link(destination: URL(string: "https://developer.android.com/tools/releases/platform-tools")!) {
                        componentRow("Android Debug Bridge", version: "37.0.1")
                    }
                    .buttonStyle(.plain)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            instructionNumber(number)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func instructionNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Color.accentColor, in: Circle())
    }

    private func componentRow(_ name: String, version: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.primary)
            Spacer()
            Text(version).foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var developerGuide: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("如何打开开发者模式").font(.title2.bold())
                Spacer()
                Button("完成") { showingDeveloperGuide = false }
                    .keyboardShortcut(.defaultAction)
            }
            Divider()
            instructionRow(1, "打开设备的“设置”，进入“关于手机”或“关于设备”。")
            instructionRow(2, "连续点击“版本号”或“系统版本”约 7 次，直到出现开发者模式已开启的提示。")
            instructionRow(3, "返回设置，进入“系统与更新”“更多设置”或“开发者选项”。")
            instructionRow(4, "开启 USB 调试；需要无线连接时，再开启无线调试。")
            Text("不同品牌和系统版本的菜单名称可能略有不同，可在设置中搜索“开发者选项”。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 560)
    }

    private func messageView(icon: String, title: String, detail: String, color: Color) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon).font(.system(size: 46, weight: .light)).foregroundStyle(color)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("重新查找") { Task { await model.inspectEnvironment() } }.buttonStyle(.borderedProminent)
            Spacer()
        }.padding(36)
    }

    private func deviceRow(_ device: AndroidDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone")
                .font(.title2).frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName).font(.body.weight(.medium))
                Text(device.id).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(device.isReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(stateText(device.state))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(model.selectedID == device.id ? 1 : 0)
                .accessibilityLabel(model.selectedID == device.id ? "已选择" : "未选择")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var shouldShowStatus: Bool {
        model.isBusy || (!model.status.isEmpty && !model.status.contains("已就绪") && !model.status.hasPrefix("未发现设备"))
    }

    private var selectedDeviceIsReady: Bool {
        model.devices.first(where: { $0.id == model.selectedID })?.isReady == true
    }

    private func stateText(_ state: String) -> String {
        switch state {
        case "device": return "已连接"
        case "unauthorized": return "等待授权"
        case "offline": return "离线"
        default: return state
        }
    }

}
