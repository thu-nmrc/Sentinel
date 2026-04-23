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

    @State private var storageBytes: Int64 = 0
    @State private var showCleanConfirm = false
    @State private var cleanMessage: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape.fill") }

            storageTab
                .tabItem { Label("Storage", systemImage: "internaldrive.fill") }

            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield.fill") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle.fill") }
        }
        .frame(width: 620, height: 480)
        .padding(8)
        .onAppear {
            syncLaunchAtLoginState()
            refreshStorageUsage()
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
