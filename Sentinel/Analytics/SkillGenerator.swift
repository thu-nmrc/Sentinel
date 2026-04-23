import Foundation
import os

struct SkillGenerator {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "SkillGenerator")

    static var openClawSkillsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/skills", isDirectory: true)
    }

    static func exportSkill(_ skill: SkillRecommendation) -> SkillExportResult {
        let skillDir = openClawSkillsDirectory.appendingPathComponent(skill.skillId, isDirectory: true)
        let skillFile = skillDir.appendingPathComponent("SKILL.md")

        do {
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            try skill.skillMarkdown.write(to: skillFile, atomically: true, encoding: .utf8)
            log.info("Exported skill '\(skill.skillId)' to \(skillFile.path)")
            return SkillExportResult(skillId: skill.skillId, path: skillFile.path, success: true, error: nil)
        } catch {
            log.error("Failed to export skill '\(skill.skillId)': \(error.localizedDescription)")
            return SkillExportResult(skillId: skill.skillId, path: skillFile.path, success: false, error: error.localizedDescription)
        }
    }

    static func exportAll(_ skills: [SkillRecommendation]) -> [SkillExportResult] {
        skills.filter { !$0.isBuiltIn && !$0.skillMarkdown.isEmpty }
              .map { exportSkill($0) }
    }

    static func isSkillInstalled(_ skillId: String) -> Bool {
        let skillFile = openClawSkillsDirectory
            .appendingPathComponent(skillId, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        return FileManager.default.fileExists(atPath: skillFile.path)
    }

    static func removeSkill(_ skillId: String) -> Bool {
        let skillDir = openClawSkillsDirectory.appendingPathComponent(skillId, isDirectory: true)
        do {
            try FileManager.default.removeItem(at: skillDir)
            log.info("Removed skill '\(skillId)'")
            return true
        } catch {
            log.error("Failed to remove skill '\(skillId)': \(error.localizedDescription)")
            return false
        }
    }

    static func installedSkillIds() -> Set<String> {
        let dir = openClawSkillsDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        var ids: Set<String> = []
        for entry in entries {
            let skillMd = dir.appendingPathComponent(entry).appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillMd.path) {
                ids.insert(entry)
            }
        }
        return ids
    }
}
