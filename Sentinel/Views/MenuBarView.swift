import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appTracking: AppTrackingService
    @EnvironmentObject private var permissionManager: PermissionManager
    @EnvironmentObject private var screenCapture: ScreenCaptureService
    @EnvironmentObject private var inputMonitor: InputMonitorService
    @EnvironmentObject private var fileWatcher: FileWatcherService
    @EnvironmentObject private var clipboard: ClipboardService

    @AppStorage(SentinelConstants.UserDefaultsKeys.isRecording) private var isRecording = false
    @AppStorage(SentinelConstants.UserDefaultsKeys.todayRecordingSeconds) private var persistedTodaySeconds = 0.0
    @AppStorage(SentinelConstants.UserDefaultsKeys.todayRecordingDayKey) private var todayDayKey = ""

    @State private var sessionStart: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            recordingSection
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(appTracking.currentApp.isEmpty ? "No active app" : appTracking.currentApp)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "app.badge.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .labelStyle(.titleAndIcon)

                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(todayRecordingTotal.formattedDuration)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.vertical, 4)

            VStack(spacing: 2) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: SentinelWindowID.dashboard.rawValue)
                } label: {
                    Label("Open Dashboard", systemImage: "rectangle.split.2x1")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.001))
                .contentShape(Rectangle())

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: SentinelWindowID.settings.rawValue)
                } label: {
                    Label("Settings…", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.001))
                .contentShape(Rectangle())
            }

            Divider()
                .padding(.vertical, 4)

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Sentinel", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.bottom, 10)
        }
        .onAppear {
            rollDayIfNeeded()
            permissionManager.checkAllPermissions()
            permissionManager.startPeriodicRecheck()
            if isRecording {
                sessionStart = Date()
                startAllServices()
            }
        }
        .onChange(of: isRecording) { _, recording in
            rollDayIfNeeded()
            if recording {
                sessionStart = Date()
                startAllServices()
            } else {
                commitSessionToToday()
                stopAllServices()
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            rollDayIfNeeded()
        }
    }

    private var recordingSection: some View {
        Toggle(isOn: $isRecording) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isRecording ? Color.green : Color(nsColor: .separatorColor))
                    .frame(width: 8, height: 8)
                    .shadow(color: isRecording ? .green.opacity(0.45) : .clear, radius: 4)
                Text(isRecording ? "Recording" : "Stopped")
                    .font(.system(.headline, design: .rounded))
            }
        }
        .toggleStyle(.switch)
    }

    private var todayRecordingTotal: TimeInterval {
        let key = Self.dayKey(for: Date())
        let base = (todayDayKey == key) ? persistedTodaySeconds : 0
        var total = base
        if isRecording, let start = sessionStart {
            total += Date().timeIntervalSince(start)
        }
        return total
    }

    private func rollDayIfNeeded() {
        let key = Self.dayKey(for: Date())
        guard todayDayKey != key else { return }
        sessionStart = isRecording ? Date() : nil
        todayDayKey = key
        persistedTodaySeconds = 0
    }

    private func commitSessionToToday() {
        guard let start = sessionStart else { return }
        persistedTodaySeconds += Date().timeIntervalSince(start)
        sessionStart = nil
    }

    private func startAllServices() {
        appTracking.start()
        screenCapture.start()
        inputMonitor.start()
        fileWatcher.start()
        clipboard.start()
    }

    private func stopAllServices() {
        appTracking.stop()
        screenCapture.stop()
        inputMonitor.stop()
        fileWatcher.stop()
        clipboard.stop()
    }
}

private extension MenuBarView {
    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
