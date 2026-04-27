import Foundation
import os

/// Builds personalized skill recommendations by sending the user's analyzed
/// behavior profile to an LLM and parsing structured JSON skills back.
@MainActor
struct LLMSkillGenerator {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "LLMSkillGenerator")

    let client: OpenAIClient

    enum GenerationError: LocalizedError {
        case malformedJSON(String)
        case noSkills
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .malformedJSON(let m): return "LLM 返回了无法解析的内容：\(m)"
            case .noSkills: return "LLM 没有生成任何 skill。"
            case .underlying(let e): return e.localizedDescription
            }
        }
    }

    func generate(from result: InsightEngine.AnalysisResult,
                  analytics: AnalyticsEngine,
                  days: Int) async throws -> [SkillRecommendation] {
        let context = buildContext(from: result, analytics: analytics, days: days)

        let messages: [OpenAIClient.ChatMessage] = [
            .init(role: "system", content: Self.systemPrompt),
            .init(role: "user", content: context)
        ]

        do {
            let raw = try await client.completeJSON(messages: messages, temperature: 0.5)
            return try parseResponse(raw)
        } catch let e as GenerationError {
            throw e
        } catch {
            throw GenerationError.underlying(error)
        }
    }

    // MARK: - Context Building

    private func buildContext(from result: InsightEngine.AnalysisResult,
                              analytics: AnalyticsEngine,
                              days: Int) -> String {
        var lines: [String] = []
        lines.append("# 用户行为画像（最近 \(days) 天）")
        lines.append("- 主要角色推断：\(result.workflowProfile.primaryRole)")

        let topApps = result.appProfile.topApps.prefix(12)
        if !topApps.isEmpty {
            lines.append("\n## Top 应用使用时长")
            for app in topApps {
                let h = String(format: "%.1f", app.hours)
                lines.append("- \(app.name) [\(app.bundleId)] · \(h)h")
            }
        }

        let cats = result.appProfile.categories.sorted { $0.value > $1.value }.prefix(8)
        if !cats.isEmpty {
            lines.append("\n## 应用类别累计时长（小时）")
            for c in cats {
                lines.append("- \(c.key): \(String(format: "%.1f", c.value))h")
            }
        }

        let langs = result.languageProfile.detected.prefix(10)
        if !langs.isEmpty {
            lines.append("\n## 检测到的文件类型/语言（按文件事件数）")
            for l in langs {
                lines.append("- \(l.language): \(l.fileCount) 个事件 (置信度 \(String(format: "%.2f", l.confidence)))")
            }
        }

        let trans = result.workflowProfile.topTransitions.prefix(8)
        if !trans.isEmpty {
            lines.append("\n## 高频应用切换（from → to · 次数）")
            for t in trans {
                lines.append("- \(t.from) → \(t.to) · \(t.count)")
            }
        }

        // Pull additional raw signals to help the LLM personalize.
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate

        if let titles = try? analytics.windowTitleSamples(from: startDate, to: endDate, limit: 60) {
            let unique = Self.dedupTitles(titles).prefix(20)
            if !unique.isEmpty {
                lines.append("\n## 窗口标题样本（去重，前 20 条）")
                for t in unique {
                    lines.append("- [\(t.appName)] \(t.windowTitle)")
                }
            }
        }

        if let paths = try? analytics.fileEventPaths(from: startDate, to: endDate, limit: 800) {
            let projects = Self.inferProjects(from: paths)
            if !projects.isEmpty {
                lines.append("\n## 活跃项目目录（按事件聚合）")
                for p in projects.prefix(10) {
                    lines.append("- \(p.root) · \(p.fileCount) 个不同文件 · 主要扩展名: \(p.topExts.joined(separator: ", "))")
                }
            }
        }

        // Insights summary
        if !result.insights.isEmpty {
            lines.append("\n## 已生成的初步洞察")
            for i in result.insights.prefix(8) {
                lines.append("- [\(i.category.rawValue)] \(i.title): \(i.detail) (置信度 \(String(format: "%.2f", i.confidence)))")
            }
        }

        lines.append("\n## 任务")
        lines.append("基于以上画像，为这位用户生成 5-8 个高度个性化的 OpenClaw（claw / 龙虾）Skills。")
        lines.append("Skills 是 markdown 文件，定义了 AI Agent 在某个细分场景下应该如何工作。")
        lines.append("要求：")
        lines.append("1) 真正贴合该用户的具体技术栈和工作流，**不要**输出泛泛的 'Python 助手' 这种通用 skill；")
        lines.append("2) 优先识别用户当前正在做的具体项目类型（例如：智能合约开发、macOS 原生应用、数据分析等）并为其专门定制；")
        lines.append("3) 同时混合 1-2 个能跨场景提效的工具型 skill（例如 git/PR 流程、文档摘要）；")
        lines.append("4) 每个 skill 的 SKILL.md 内容必须可直接落盘到 ~/.openclaw/skills/<id>/SKILL.md 使用，包含 YAML frontmatter（name, description, metadata.openclaw.emoji）和正文（# 标题、## 何时使用、## 主要能力、## 工作流程、## 示例命令）。")
        lines.append("5) match_reasons 必须引用用户实际数据（例如 \"你在过去 \(days) 天用了 X 小时 Cursor\" 而非笼统的 \"你是开发者\"）。")
        lines.append("\n严格按下面 JSON schema 返回，所有自然语言文案使用中文：")
        lines.append(Self.outputSchemaHint)

        return lines.joined(separator: "\n")
    }

    private static func dedupTitles(_ titles: [(appName: String, windowTitle: String)]) -> [(appName: String, windowTitle: String)] {
        var seen: Set<String> = []
        var result: [(appName: String, windowTitle: String)] = []
        for t in titles {
            let key = "\(t.appName.lowercased())|\(t.windowTitle.lowercased())"
            if seen.insert(key).inserted {
                result.append(t)
            }
        }
        return result
    }

    struct ProjectInfo {
        let root: String
        let fileCount: Int
        let topExts: [String]
    }

    /// Heuristic project root inference from file paths.
    /// Filters known build/cache directories before grouping.
    private static func inferProjects(from paths: [String]) -> [ProjectInfo] {
        let ignored: [String] = [
            "/node_modules/", "/.git/", "/build/", "/.build/", "/DerivedData/",
            "/dist/", "/.next/", "/target/", "/cache/", "/.cache/", "/vendor/",
            "/Pods/", "/.gradle/", "/__pycache__/", "/artifacts-zk/", "/artifacts/",
            "/.turbo/", "/.parcel-cache/", "/coverage/"
        ]
        let projectMarkers = ["package.json", "Cargo.toml", "go.mod", "Package.swift",
                              "pyproject.toml", "requirements.txt", "Gemfile",
                              "pom.xml", "build.gradle", "hardhat.config.ts",
                              "hardhat.config.js", "foundry.toml", ".git"]

        var grouped: [String: (files: Set<String>, exts: [String: Int])] = [:]

        for raw in paths {
            let lower = raw.lowercased()
            if ignored.contains(where: { lower.contains($0) }) { continue }

            // Walk up looking for a project marker; fall back to second-from-top dir under home.
            let url = URL(fileURLWithPath: raw)
            var root = url.deletingLastPathComponent()
            var found = false
            for _ in 0..<8 {
                let candidate = root.path
                if candidate.count <= 1 { break }
                for marker in projectMarkers {
                    let probe = root.appendingPathComponent(marker).path
                    if FileManager.default.fileExists(atPath: probe) {
                        found = true
                        break
                    }
                }
                if found { break }
                root.deleteLastPathComponent()
            }
            let key = found ? root.path : Self.shortenPath(url.deletingLastPathComponent().path)

            var entry = grouped[key] ?? (files: Set<String>(), exts: [:])
            entry.files.insert(raw)
            let ext = (raw as NSString).pathExtension.lowercased()
            if !ext.isEmpty {
                entry.exts[ext, default: 0] += 1
            }
            grouped[key] = entry
        }

        return grouped.map { (root, payload) in
            let topExts = payload.exts.sorted { $0.value > $1.value }.prefix(4).map { $0.key }
            return ProjectInfo(root: shortenPath(root), fileCount: payload.files.count, topExts: Array(topExts))
        }
        .sorted { $0.fileCount > $1.fileCount }
    }

    private static func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Parsing

    private func parseResponse(_ raw: String) throws -> [SkillRecommendation] {
        guard let data = raw.data(using: .utf8) else {
            throw GenerationError.malformedJSON("内容不是有效的 UTF-8")
        }

        struct LLMSkill: Codable {
            let skill_id: String
            let name: String
            let emoji: String?
            let description: String
            let match_score: Double?
            let match_reasons: [String]?
            let category: String?
            let skill_markdown: String?
        }
        struct LLMResponse: Codable { let skills: [LLMSkill] }

        let decoded: LLMResponse
        do {
            decoded = try JSONDecoder().decode(LLMResponse.self, from: data)
        } catch {
            throw GenerationError.malformedJSON(error.localizedDescription)
        }

        guard !decoded.skills.isEmpty else { throw GenerationError.noSkills }

        return decoded.skills.compactMap { llm in
            let cat = mapCategory(llm.category) ?? .productivity
            let reasons = (llm.match_reasons ?? []).filter { !$0.isEmpty }
            let score = max(0, min(1, llm.match_score ?? 0.7))
            let id = sanitizeSkillId(llm.skill_id)
            guard !id.isEmpty, !llm.name.isEmpty else { return nil }
            return SkillRecommendation(
                skillId: id,
                name: llm.name,
                emoji: llm.emoji?.isEmpty == false ? llm.emoji! : "✨",
                description: llm.description,
                matchScore: score,
                matchReasons: reasons.isEmpty ? ["LLM 基于你的使用画像生成"] : reasons,
                category: cat,
                isBuiltIn: false,
                skillMarkdown: llm.skill_markdown ?? ""
            )
        }
    }

    private func sanitizeSkillId(_ raw: String) -> String {
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "-_"))
        return raw.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
    }

    private func mapCategory(_ raw: String?) -> SkillRecommendation.SkillCategory? {
        guard let raw = raw?.lowercased() else { return nil }
        for c in SkillRecommendation.SkillCategory.allCases {
            if c.rawValue.lowercased() == raw { return c }
            if "\(c)".lowercased() == raw { return c }
        }
        switch raw {
        case "coding", "code", "programming", "dev", "development", "编程", "开发": return .coding
        case "devops", "infra", "ci": return .devops
        case "design", "ui": return .design
        case "productivity", "tool", "workflow": return .productivity
        case "communication", "comm", "chat": return .communication
        case "data", "analytics", "ml": return .data
        case "content", "writing": return .content
        case "research", "search": return .research
        default: return nil
        }
    }

    // MARK: - Prompts

    private static let systemPrompt: String = """
    你是 OpenClaw（昵称"龙虾"，一个 AI Coding Agent）的 Skill 设计师。
    你的工作是基于一名 macOS 用户最近的真实使用数据，为他/她量身定制一组 Skills。
    Skill = 一份 SKILL.md 文件，定义了 AI Agent 在某个细分任务下"什么时候用、能做什么、怎么做"。
    输出必须严格符合调用方提供的 JSON schema，且仅输出 JSON 对象，不要任何解释性文字。
    所有自然语言（name, description, match_reasons, skill_markdown 正文）一律用简体中文，但 SKILL.md 的 YAML frontmatter 字段名保持英文。
    """

    private static let outputSchemaHint: String = """
    {
      "skills": [
        {
          "skill_id": "string, lowercase, hyphen-separated, e.g. 'solidity-hardhat-helper'",
          "name": "string, 简短中文名, e.g. '合约开发助手'",
          "emoji": "single emoji char",
          "description": "string, 1-2 句中文，说明这个 skill 解决的具体问题",
          "match_score": "float 0-1，匹配度",
          "match_reasons": ["3-5 条中文短句，必须引用用户的真实数据特征"],
          "category": "枚举之一: coding | devops | design | productivity | communication | data | content | research",
          "skill_markdown": "完整 SKILL.md 文件内容（含 YAML frontmatter 和正文章节）"
        }
      ]
    }
    """
}
