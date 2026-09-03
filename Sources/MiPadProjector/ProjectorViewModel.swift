import Foundation

struct AndroidDevice: Identifiable, Hashable {
    let id: String
    let state: String
    let model: String

    var displayName: String { model.isEmpty ? id : model.replacingOccurrences(of: "_", with: " ") }
    var isReady: Bool { state == "device" }
}

@MainActor
final class ProjectorViewModel: ObservableObject {
    @Published var devices: [AndroidDevice] = []
    @Published var selectedID: String?
    @Published var address = ""
    @Published var pairingAddress = ""
    @Published var pairingCode = ""
    @Published var status = "正在检查环境…"
    @Published var isBusy = false
    @Published var maxSize = "1920"
    @Published var bitrate = "12M"
    @Published var turnScreenOff = false

    private(set) var adbPath: String?
    private(set) var scrcpyPath: String?

    var dependenciesReady: Bool { adbPath != nil && scrcpyPath != nil }

    init() {
        Task { await inspectEnvironment() }
    }

    func inspectEnvironment() async {
        adbPath = Self.findExecutable("adb")
        scrcpyPath = Self.findExecutable("scrcpy")
        guard dependenciesReady else {
            status = "缺少投屏组件，请先安装 Android Platform Tools 和 scrcpy。"
            return
        }
        status = "投屏组件已就绪，正在查找设备…"
        await refreshDevices()
    }

    func refreshDevices() async {
        guard let adbPath else { await inspectEnvironment(); return }
        isBusy = true
        defer { isBusy = false }
        let result = await Self.run(adbPath, ["devices", "-l"])
        guard result.code == 0 else {
            status = "ADB 启动失败：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
            return
        }
        devices = result.output
            .split(separator: "\n")
            .dropFirst()
            .compactMap(Self.parseDevice)
        if selectedID == nil || !devices.contains(where: { $0.id == selectedID }) {
            selectedID = devices.first(where: \.isReady)?.id
        }
        if devices.isEmpty {
            status = "未发现设备。请用 USB 连接，或输入无线调试地址。"
        } else if devices.contains(where: { $0.state == "unauthorized" }) {
            status = "请在设备上允许这台 Mac 进行 USB 调试。"
        } else {
            status = ""
        }
    }

    func enableWireless() async {
        guard let adbPath, let selectedID else { status = "请先通过 USB 连接并选择设备。"; return }
        await perform("正在开启无线调试…") {
            let result = await Self.run(adbPath, ["-s", selectedID, "tcpip", "5555"])
            self.status = result.code == 0 ? "无线调试已开启。请输入设备的局域网 IP，例如 192.168.1.20:5555。" : result.output
        }
    }

    func connectWireless() async {
        guard let adbPath else { status = "未找到 adb。"; return }
        let target = normalizedAddress(defaultPort: "5555")
        guard !target.isEmpty else { status = "请输入 IP 地址和端口。"; return }
        await perform("正在连接 \(target)…") {
            let result = await Self.run(adbPath, ["connect", target])
            self.status = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            await self.refreshDevices()
        }
    }

    func pairWireless() async {
        guard let adbPath else { status = "未找到 adb。"; return }
        let target = pairingAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !pairingCode.isEmpty else { status = "请输入配对地址、端口和配对码。"; return }
        await perform("正在与设备配对…") {
            let result = await Self.run(adbPath, ["pair", target, self.pairingCode])
            if result.code == 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let services = await Self.run(adbPath, ["mdns", "services"])
                if let endpoint = Self.connectEndpoint(from: services.output, matching: target) {
                    _ = await Self.run(adbPath, ["connect", endpoint])
                }
                await self.refreshDevices()
            } else {
                self.status = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    func startProjection() async {
        guard let scrcpyPath, let selectedID else { status = "请选择一台已连接的设备。"; return }
        guard devices.first(where: { $0.id == selectedID })?.isReady == true else { status = "设备尚未授权或离线。"; return }
        var arguments = ["--serial", selectedID, "--window-title", "Mac投屏", "--max-size", maxSize, "--video-bit-rate", bitrate, "--stay-awake"]
        if turnScreenOff { arguments.append("--turn-screen-off") }
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: scrcpyPath)
            process.arguments = arguments
            if let tools = Bundle.main.resourceURL?.appendingPathComponent("Tools", isDirectory: true) {
                process.currentDirectoryURL = tools
                var environment = ProcessInfo.processInfo.environment
                environment["ADB"] = adbPath ?? tools.appendingPathComponent("adb").path
                environment["SCRCPY_SERVER_PATH"] = tools.appendingPathComponent("scrcpy-server").path
                process.environment = environment
            }
            try process.run()
            status = "投屏窗口已启动。关闭投屏窗口即可断开。"
        } catch {
            status = "无法启动投屏：\(error.localizedDescription)"
        }
    }

    private func normalizedAddress(defaultPort: String) -> String {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains(":") || defaultPort.isEmpty { return value }
        return value.isEmpty ? "" : "\(value):\(defaultPort)"
    }

    private func perform(_ message: String, operation: @escaping () async -> Void) async {
        isBusy = true
        status = message
        await operation()
        isBusy = false
    }

    nonisolated private static func parseDevice(_ line: Substring) -> AndroidDevice? {
        let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 2 else { return nil }
        let model = fields.first(where: { $0.hasPrefix("model:") })?.dropFirst(6).description ?? ""
        return AndroidDevice(id: fields[0], state: fields[1], model: model)
    }

    nonisolated private static func connectEndpoint(from output: String, matching pairingTarget: String) -> String? {
        let host = pairingTarget.split(separator: ":").first.map(String.init) ?? ""
        return output.split(separator: "\n")
            .map(String.init)
            .first(where: { $0.contains("_adb-tls-connect._tcp") && (host.isEmpty || $0.contains(host)) })?
            .split(whereSeparator: \.isWhitespace)
            .last
            .map(String.init)
    }

    nonisolated private static func findExecutable(_ name: String) -> String? {
        let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent(name).path
        let candidates = [bundled].compactMap { $0 }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) async -> (code: Int32, output: String) {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let tools = Bundle.main.resourceURL?.appendingPathComponent("Tools", isDirectory: true) {
                process.currentDirectoryURL = tools
                var environment = ProcessInfo.processInfo.environment
                environment["ADB"] = tools.appendingPathComponent("adb").path
                environment["SCRCPY_SERVER_PATH"] = tools.appendingPathComponent("scrcpy-server").path
                process.environment = environment
            }
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return (process.terminationStatus, String(decoding: data, as: UTF8.self))
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
    }
}
