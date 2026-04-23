import AppKit
import Foundation
import GRDB
import os
import ScreenCaptureKit
import Vision

@MainActor
final class OCRService: ObservableObject {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "OCR")

    @Published private(set) var todayOCRCount: Int = 0

    private var isProcessing = false

    nonisolated init() {}

    func captureAndRecognize(activeApp: String, windowTitle: String?) async {
        guard !isProcessing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            Self.log.info("Screen recording permission not granted, skipping OCR")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                Self.log.error("No displays available for OCR capture")
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.captureResolution = .nominal

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            let ocrText = await performOCR(on: cgImage)

            guard let ocrText, !ocrText.isEmpty else {
                Self.log.debug("OCR returned no text")
                return
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            guard let jpegData = nsImage.jpegData(quality: 0.5) else { return }

            let timestamp = Date()
            let nameFormatter = DateFormatter()
            nameFormatter.locale = Locale(identifier: "en_US_POSIX")
            nameFormatter.timeZone = TimeZone.current
            nameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "ocr_\(nameFormatter.string(from: timestamp)).jpg"
            let dir = SentinelConstants.StoragePaths.screenshotsDirectory
            let fileURL = dir.appendingPathComponent(filename)

            try jpegData.write(to: fileURL, options: .atomic)

            var record = ScreenshotRecord(
                id: nil,
                timestamp: timestamp,
                filePath: fileURL.path,
                activeApp: activeApp,
                windowTitle: windowTitle,
                displayId: Int(display.displayID),
                ocrText: ocrText
            )

            try await DatabaseManager.shared.dbQueue.write { db in
                try record.insert(db)
            }

            todayOCRCount += 1
            Self.log.info("OCR captured \(ocrText.count) chars from \(activeApp, privacy: .public)")
        } catch {
            Self.log.error("OCR capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func performOCR(on image: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    Self.log.error("VNRecognizeTextRequest error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let fullText = lines.joined(separator: "\n")
                continuation.resume(returning: fullText.isEmpty ? nil : fullText)
            }
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Self.log.error("VNImageRequestHandler failed: \(error.localizedDescription, privacy: .public)")
                continuation.resume(returning: nil)
            }
        }
    }
}
