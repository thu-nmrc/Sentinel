import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var permissionManager: PermissionManager

    @AppStorage(SentinelConstants.UserDefaultsKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(SentinelConstants.UserDefaultsKeys.screenshotInterval) private var screenshotInterval = SentinelConstants.defaultScreenshotInterval
    @AppStorage(SentinelConstants.UserDefaultsKeys.screenshotQuality) private var screenshotQuality = 0.75
    @AppStorage(SentinelConstants.UserDefaultsKeys.screenshotRetentionDays) private var screenshotRetentionDays = 14
    @AppStorage(SentinelConstants.UserDefaultsKeys.databaseRetentionDays) private var databaseRetentionDays = 90
    @AppStorage(SentinelConstants.UserDefaultsKeys.llmEnabled) private var llmEnabled = false
    @AppStorage(SentinelConstants.UserDefaultsKeys.llmModel) private var llmModel = SentinelConstants.LLMDefaults.defaultModel

    @State private var storageBytes: Int64 = 0
    @State private var showCleanConfirm = false
    @State private var cleanMessage: String?
    @State private var apiKeyDraft: String = ""
    @State private var apiKeySaved: Bool = false
    @State private var apiKeyTestState: APIKeyTestState = .idle
    @State private var apiKeyTestMessage: String = ""

    enum APIKeyTestState { case idle, testing, success, failure }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape.fill") }

            storageTab
                .tabItem { Label("Storage", systemImage: "internaldrive.fill") }

            aiTab
                .tabItem { Label("AI", systemImage: "sparkles") }

            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield.fill") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle.fill") }
        }
        .frame(width: 620, height: 520)
        .padding(8)
        .onAppear {
            syncLaunchAtLoginState()
            refreshStorageUsage()
            loadAPIKeyDraft()
        }
        .alert("Clean Old Data", isPresented: $showCleanConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clean", role: .destructive) {
                performCleanOldData()
            }
        } message: {
            Text("Remove screenshots older than \(screenshotRetentionDays) days. Database cleanup will be available in a future update.")
        }
        .alert("Done", isPresented: Binding(
            get: { cleanMessage != nil },
            set: { if !$0 { cleanMessage = nil } }
        )) {
            Button("OK", role: .cancel) { cleanMessage = nil }
        } message: {
            Text(cleanMessage ?? "")
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch Sentinel at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            } header: {
                Text("Startup")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Screenshot interval")
                        Spacer()
                        Text("\(Int(screenshotIntervalClamped)) s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $screenshotInterval,
                        in: 1...30,
                        step: 1
                    ) {
                        Text("Interval")
                    } minimumValueLabel: {
                        Text("1s")
                            .font(.caption2)
                    } maximumValueLabel: {
                        Text("30s")
                            .font(.caption2)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Screenshot quality")
                        Spacer()
                        Text(qualityLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $screenshotQuality, in: 0.3...1, step: 0.05)
                }
            } header: {
                Text("Capture")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var screenshotIntervalClamped: Double {
        min(30, max(1, screenshotInterval))
    }

    private var qualityLabel: String {
        String(format: "%.0f%%", screenshotQuality * 100)
    }

    private var storageTab: some View {
        Form {
            Section {
                LabeledContent("Data location") {
                    Text(SentinelConstants.StoragePaths.appSupportDirectory.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                Stepper("Screenshot retention: \(screenshotRetentionDays) days", value: $screenshotRetentionDays, in: 1...SentinelConstants.maxScreenshotRetentionDays)
                Stepper("Database retention: \(databaseRetentionDays) days", value: $databaseRetentionDays, in: 7...SentinelConstants.maxDatabaseRetentionDays)
            } header: {
                Text("Locations & retention")
            }

            Section {
                LabeledContent("Estimated usage") {
                    Text(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                        .monospacedDigit()
                }
                Button {
                    refreshStorageUsage()
                } label: {
                    Label("Refresh usage", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    showCleanConfirm = true
                } label: {
                    Label("Clean Old Data", systemImage: "trash")
                }
            } header: {
                Text("Maintenance")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var aiTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("使用 LLM 个性化生成 Skills", isOn: $llmEnabled)
                    Text(llmEnabled
                         ? "Skill 推荐由 OpenAI 模型基于你的真实使用画像动态生成。"
                         : "目前使用本地规则推荐。打开开关后改用 LLM 生成更贴合你工作流的 Skills。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("生成模式")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("OpenAI API Key")
                        Spacer()
                        if apiKeySaved {
                            Label("已保存到 Keychain", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    SecureField("sk-...", text: $apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    HStack(spacing: 8) {
                        Button("保存") { saveAPIKey() }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKeyDraft.isEmpty)
                        Button("测试连接") { testAPIKey() }
                            .disabled(apiKeyDraft.isEmpty || apiKeyTestState == .testing)
                        if apiKeySaved {
                            Button(role: .destructive) { clearAPIKey() } label: {
                                Text("移除")
                            }
                        }
                        Spacer()
                        if apiKeyTestState == .testing {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if !apiKeyTestMessage.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: apiKeyTestState == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(apiKeyTestState == .success ? .green : .orange)
                            Text(apiKeyTestMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Key 仅保存在本机 Keychain。Sentinel 仅在你点击「分析」时把使用画像发送给 OpenAI 用于生成 Skills。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("OpenAI 凭据")
            }

            Section {
                Picker("模型", selection: $llmModel) {
                    ForEach(SentinelConstants.LLMDefaults.availableModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                Text("成本与质量参考：gpt-4o-mini 最便宜，gpt-4.1 / gpt-4o 更细致，o4-mini / o3-mini 推理更强。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("模型选择")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func loadAPIKeyDraft() {
        if let stored = KeychainHelper.get(account: KeychainAccount.openAIAPIKey), !stored.isEmpty {
            apiKeyDraft = stored
            apiKeySaved = true
        } else {
            apiKeySaved = false
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainHelper.set(trimmed, account: KeychainAccount.openAIAPIKey)
            apiKeyDraft = trimmed
            apiKeySaved = true
            apiKeyTestState = .idle
            apiKeyTestMessage = "已保存。"
        } catch {
            apiKeyTestState = .failure
            apiKeyTestMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func clearAPIKey() {
        KeychainHelper.delete(account: KeychainAccount.openAIAPIKey)
        apiKeyDraft = ""
        apiKeySaved = false
        apiKeyTestState = .idle
        apiKeyTestMessage = "已移除。"
    }

    private func testAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apiKeyTestState = .testing
        apiKeyTestMessage = "正在请求 /v1/models …"
        let client = OpenAIClient(apiKey: trimmed, model: llmModel)
        Task {
            do {
                let models = try await client.listModels()
                await MainActor.run {
                    apiKeyTestState = .success
                    let preview = models.prefix(6).joined(separator: ", ")
                    apiKeyTestMessage = "连接成功，可见 \(models.count) 个模型，例如：\(preview)"
                }
            } catch {
                await MainActor.run {
                    apiKeyTestState = .failure
                    apiKeyTestMessage = error.localizedDescription
                }
            }
        }
    }

    private var permissionsTab: some View {
        Form {
            permissionSection(
                title: "Screen Recording",
                granted: permissionManager.hasScreenRecording,
                action: { permissionManager.openScreenRecordingSettings() }
            )
            permissionSection(
                title: "Accessibility",
                granted: permissionManager.hasAccessibility,
                action: { permissionManager.openAccessibilitySettings() }
            )
            permissionSection(
                title: "Full Disk Access",
                granted: permissionManager.hasFullDiskAccess,
                action: { permissionManager.openFullDiskAccessSettings() }
            )
            permissionSection(
                title: "Input Monitoring",
                granted: permissionManager.hasInputMonitoring,
                action: { permissionManager.openInputMonitoringSettings() }
            )
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func permissionSection(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? Color.green : Color.red.opacity(0.85))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(granted ? "Granted" : "Required for full functionality")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings…") {
                    action()
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 20) {
            Image(systemName: "eye.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text(SentinelConstants.appName)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Sentinel runs quietly from the menu bar, recording app focus, input activity, and optional screenshots so you can review your day with clarity. Your data stays on this Mac.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syncLaunchAtLoginState() {
        guard #available(macOS 13.0, *) else { return }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func refreshStorageUsage() {
        storageBytes = Self.directorySize(at: SentinelConstants.StoragePaths.appSupportDirectory)
    }

    private func performCleanOldData() {
        let dir = SentinelConstants.StoragePaths.screenshotsDirectory
        let cutoff = Calendar.current.date(byAdding: .day, value: -screenshotRetentionDays, to: Date()) ?? .distantPast
        var removed = 0
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            cleanMessage = "Could not read screenshots folder."
            return
        }
        for url in urls {
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            if date < cutoff {
                try? FileManager.default.removeItem(at: url)
                removed += 1
            }
        }
        refreshStorageUsage()
        cleanMessage = removed > 0 ? "Removed \(removed) screenshot file(s)." : "No old screenshots to remove."
    }

    private static func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize
            else { continue }
            total += Int64(size)
        }
        return total
    }
}
