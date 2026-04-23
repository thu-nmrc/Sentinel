import Foundation
import os

@MainActor
final class InsightEngine {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sentinel", category: "InsightEngine")
    private let analytics: AnalyticsEngine
    private let calendar = Calendar.current

    init(analytics: AnalyticsEngine) {
        self.analytics = analytics
    }

    struct AnalysisResult {
        let insights: [UserInsight]
        let appProfile: AppProfile
        let languageProfile: LanguageProfile
        let workflowProfile: WorkflowProfile
        let analyzedDays: Int
    }

    struct AppProfile {
        let topApps: [(name: String, bundleId: String, hours: Double)]
        let categories: [String: Double]
    }

    struct LanguageProfile {
        let detected: [(language: String, fileCount: Int, confidence: Double)]
    }

    struct WorkflowProfile {
        let topTransitions: [(from: String, to: String, count: Int)]
        let primaryRole: String
    }

    func analyze(days: Int = 7) async -> AnalysisResult {
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) else {
            return AnalysisResult(insights: [], appProfile: AppProfile(topApps: [], categories: [:]),
                                  languageProfile: LanguageProfile(detected: []),
                                  workflowProfile: WorkflowProfile(topTransitions: [], primaryRole: "通用"),
                                  analyzedDays: days)
        }

        var insights: [UserInsight] = []

        let appBreakdown = (try? analytics.appUsageBreakdown(from: startDate, to: endDate)) ?? []
        let windowTitles = (try? analytics.windowTitleSamples(from: startDate, to: endDate)) ?? []
        let filePaths = (try? analytics.fileEventPaths(from: startDate, to: endDate)) ?? []
        let clipboards = (try? analytics.clipboardTexts(from: startDate, to: endDate)) ?? []
        let transitions = (try? analytics.appSwitchSequences(from: startDate, to: endDate)) ?? []

        let appProfile = buildAppProfile(appBreakdown)
        let languageProfile = buildLanguageProfile(filePaths: filePaths, windowTitles: windowTitles)
        let workflowProfile = buildWorkflowProfile(transitions: transitions, appProfile: appProfile)

        insights.append(contentsOf: generateDevToolInsights(appProfile: appProfile))
        insights.append(contentsOf: generateLanguageInsights(languageProfile: languageProfile))
        insights.append(contentsOf: generateWorkflowInsights(workflowProfile: workflowProfile))
        insights.append(contentsOf: generatePlatformInsights(windowTitles: windowTitles, appProfile: appProfile))
        insights.append(contentsOf: generateContentInsights(clipboards: clipboards, appProfile: appProfile))

        insights.sort { $0.confidence > $1.confidence }

        return AnalysisResult(
            insights: insights,
            appProfile: appProfile,
            languageProfile: languageProfile,
            workflowProfile: workflowProfile,
            analyzedDays: days
        )
    }

    // MARK: - App Profile

    private func buildAppProfile(_ breakdown: [(bundleId: String, appName: String, totalDuration: TimeInterval)]) -> AppProfile {
        let topApps = breakdown.prefix(20).map { (name: $0.appName, bundleId: $0.bundleId, hours: $0.totalDuration / 3600) }

        var categories: [String: Double] = [:]
        for app in breakdown {
            let hours = app.totalDuration / 3600
            for cat in Self.categorizeApp(bundleId: app.bundleId, name: app.appName) {
                categories[cat, default: 0] += hours
            }
        }

        return AppProfile(topApps: topApps.map { $0 }, categories: categories)
    }

    private static let appCategoryMap: [String: [String]] = [
        "com.apple.dt.Xcode": ["IDE", "Apple开发"],
        "com.microsoft.VSCode": ["IDE", "编辑器"],
        "com.todesktop.230313mzl4w4u92": ["IDE", "编辑器"],  // Cursor
        "com.jetbrains.intellij": ["IDE", "Java开发"],
        "com.jetbrains.pycharm": ["IDE", "Python开发"],
        "com.jetbrains.WebStorm": ["IDE", "Web开发"],
        "com.jetbrains.goland": ["IDE", "Go开发"],
        "com.sublimetext.4": ["编辑器"],
        "com.googlecode.iterm2": ["终端"],
        "com.apple.Terminal": ["终端"],
        "io.alacritty": ["终端"],
        "com.github.wez.wezterm": ["终端"],
        "dev.warp.Warp-Stable": ["终端"],
        "com.apple.Safari": ["浏览器"],
        "com.google.Chrome": ["浏览器"],
        "org.mozilla.firefox": ["浏览器"],
        "com.microsoft.edgemac": ["浏览器"],
        "com.arc.Arc": ["浏览器"],
        "com.figma.Desktop": ["设计"],
        "com.bohemiancoding.sketch3": ["设计"],
        "com.adobe.Photoshop": ["设计", "图形处理"],
        "com.adobe.illustrator": ["设计", "图形处理"],
        "com.tinyspeck.slackmacgap": ["沟通"],
        "com.hnc.Discord": ["沟通"],
        "ru.keepcoder.Telegram": ["沟通"],
        "com.apple.MobileSMS": ["沟通"],
        "com.electron.dockerdesktop": ["DevOps", "容器"],
        "com.apple.finder": ["文件管理"],
        "com.notion.id": ["笔记", "项目管理"],
        "md.obsidian": ["笔记"],
        "com.electron.postman": ["API测试"],
        "com.insomnia.app": ["API测试"],
        "com.tencent.xinWeChat": ["沟通"],
        "us.zoom.xos": ["沟通", "会议"],
        "com.microsoft.teams2": ["沟通", "会议"],
        "com.spotify.client": ["娱乐"],
        "com.apple.Music": ["娱乐"],
    ]

    private static func categorizeApp(bundleId: String, name: String) -> [String] {
        if let cats = appCategoryMap[bundleId] { return cats }

        let lower = bundleId.lowercased() + " " + name.lowercased()
        if lower.contains("term") || lower.contains("console") || lower.contains("shell") { return ["终端"] }
        if lower.contains("code") || lower.contains("edit") || lower.contains("vim") || lower.contains("emacs") { return ["编辑器"] }
        if lower.contains("browser") || lower.contains("safari") || lower.contains("chrome") || lower.contains("firefox") { return ["浏览器"] }
        if lower.contains("chat") || lower.contains("messag") || lower.contains("slack") || lower.contains("discord") { return ["沟通"] }
        if lower.contains("design") || lower.contains("figma") || lower.contains("sketch") { return ["设计"] }
        if lower.contains("docker") || lower.contains("kube") { return ["DevOps"] }
        if lower.contains("postman") || lower.contains("insomnia") { return ["API测试"] }
        if lower.contains("note") || lower.contains("obsid") || lower.contains("notion") { return ["笔记"] }
        if lower.contains("database") || lower.contains("sequel") || lower.contains("mongo") || lower.contains("redis") { return ["数据库"] }
        return ["其他"]
    }

    // MARK: - Language Profile

    private static let extensionToLanguage: [String: String] = [
        "swift": "Swift", "py": "Python", "js": "JavaScript", "ts": "TypeScript",
        "tsx": "TypeScript", "jsx": "JavaScript", "go": "Go", "rs": "Rust",
        "java": "Java", "kt": "Kotlin", "rb": "Ruby", "php": "PHP",
        "c": "C", "cpp": "C++", "h": "C/C++", "m": "Objective-C",
        "cs": "C#", "dart": "Dart", "lua": "Lua", "r": "R",
        "scala": "Scala", "zig": "Zig", "ex": "Elixir", "exs": "Elixir",
        "html": "HTML", "css": "CSS", "scss": "CSS", "less": "CSS",
        "vue": "Vue", "svelte": "Svelte",
        "sql": "SQL", "sh": "Shell", "bash": "Shell", "zsh": "Shell",
        "yml": "YAML", "yaml": "YAML", "json": "JSON", "toml": "TOML",
        "md": "Markdown", "mdx": "Markdown",
        "dockerfile": "Docker", "tf": "Terraform", "hcl": "Terraform",
        "proto": "Protobuf", "graphql": "GraphQL", "gql": "GraphQL",
        "sol": "Solidity", "move": "Move",
    ]

    private func buildLanguageProfile(filePaths: [String], windowTitles: [(appName: String, windowTitle: String)]) -> LanguageProfile {
        var langCounts: [String: Int] = [:]

        for path in filePaths {
            let ext = (path as NSString).pathExtension.lowercased()
            if let lang = Self.extensionToLanguage[ext] {
                langCounts[lang, default: 0] += 1
            }
            let filename = (path as NSString).lastPathComponent.lowercased()
            if filename == "dockerfile" || filename.hasPrefix("dockerfile.") {
                langCounts["Docker", default: 0] += 1
            }
            if filename == "makefile" || filename == "cmakelists.txt" {
                langCounts["C/C++", default: 0] += 1
            }
            if filename == "package.json" || filename == "tsconfig.json" {
                langCounts["TypeScript", default: 0] += 1
            }
            if filename == "cargo.toml" { langCounts["Rust", default: 0] += 1 }
            if filename == "go.mod" { langCounts["Go", default: 0] += 1 }
            if filename == "podfile" || filename == "package.swift" { langCounts["Swift", default: 0] += 1 }
        }

        for (_, title) in windowTitles {
            let lower = title.lowercased()
            for (ext, lang) in Self.extensionToLanguage {
                if lower.hasSuffix(".\(ext)") || lower.contains(".\(ext) ") {
                    langCounts[lang, default: 0] += 1
                }
            }
        }

        let total = max(1, langCounts.values.reduce(0, +))
        let detected = langCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (language: $0.key, fileCount: $0.value, confidence: min(1.0, Double($0.value) / Double(total) * 3)) }

        return LanguageProfile(detected: detected)
    }

    // MARK: - Workflow Profile

    private func buildWorkflowProfile(transitions: [(from: String, to: String, count: Int)], appProfile: AppProfile) -> WorkflowProfile {
        let top = Array(transitions.prefix(15))

        let cats = appProfile.categories
        let ide = (cats["IDE"] ?? 0) + (cats["编辑器"] ?? 0)
        let terminal = cats["终端"] ?? 0
        let browser = cats["浏览器"] ?? 0
        let design = cats["设计"] ?? 0
        let comm = cats["沟通"] ?? 0
        let devops = cats["DevOps"] ?? 0

        let role: String
        if design > ide && design > terminal && design > 0 { role = "设计师" }
        else if devops > 0.05 { role = "DevOps工程师" }
        else if ide > 0.05 && terminal > 0.01 && browser > 0.01 { role = "全栈工程师" }
        else if ide > 0.05 && terminal > 0.01 { role = "后端工程师" }
        else if ide > 0.05 && browser > 0.02 { role = "前端工程师" }
        else if comm > ide && comm > 0 { role = "项目管理" }
        else if ide > 0.01 { role = "开发者" }
        else { role = "通用" }

        return WorkflowProfile(topTransitions: top, primaryRole: role)
    }

    // MARK: - Insight Generation

    private func generateDevToolInsights(appProfile: AppProfile) -> [UserInsight] {
        var results: [UserInsight] = []
        let ides = appProfile.topApps.filter { app in
            Self.appCategoryMap[app.bundleId]?.contains("IDE") == true ||
            Self.appCategoryMap[app.bundleId]?.contains("编辑器") == true
        }
        if !ides.isEmpty {
            results.append(UserInsight(
                category: .devTool,
                title: "主力开发工具",
                detail: ides.map { "\($0.name) (\(String(format: "%.1f", $0.hours))h)" }.joined(separator: ", "),
                confidence: min(1.0, ides.reduce(0) { $0 + $1.hours } / 2.0),
                relatedApps: ides.map(\.name),
                dataPoints: ides.count
            ))
        }

        let terminals = appProfile.topApps.filter { app in
            Self.categorizeApp(bundleId: app.bundleId, name: app.name).contains("终端")
        }
        if !terminals.isEmpty {
            results.append(UserInsight(
                category: .devTool,
                title: "终端使用",
                detail: "重度终端用户，累计 \(String(format: "%.1f", terminals.reduce(0) { $0 + $1.hours }))h",
                confidence: min(1.0, terminals.reduce(0) { $0 + $1.hours } / 1.0),
                relatedApps: terminals.map(\.name),
                dataPoints: terminals.count
            ))
        }

        return results
    }

    private func generateLanguageInsights(languageProfile: LanguageProfile) -> [UserInsight] {
        var results: [UserInsight] = []
        let topLangs = languageProfile.detected.prefix(5)
        for lang in topLangs where lang.confidence > 0.01 {
            results.append(UserInsight(
                category: .language,
                title: "\(lang.language) 开发",
                detail: "检测到 \(lang.fileCount) 个相关文件事件",
                confidence: lang.confidence,
                relatedApps: [],
                dataPoints: lang.fileCount
            ))
        }
        return results
    }

    private func generateWorkflowInsights(workflowProfile: WorkflowProfile) -> [UserInsight] {
        var results: [UserInsight] = []

        if workflowProfile.primaryRole != "通用" {
            results.append(UserInsight(
                category: .workflow,
                title: "角色画像: \(workflowProfile.primaryRole)",
                detail: "根据应用使用模式推断",
                confidence: 0.8,
                relatedApps: [],
                dataPoints: workflowProfile.topTransitions.count
            ))
        }

        let editorBrowserSwitch = workflowProfile.topTransitions.filter { t in
            let apps = [t.from.lowercased(), t.to.lowercased()]
            let hasEditor = apps.contains { $0.contains("code") || $0.contains("xcode") || $0.contains("cursor") || $0.contains("intellij") }
            let hasBrowser = apps.contains { $0.contains("chrome") || $0.contains("safari") || $0.contains("firefox") || $0.contains("arc") }
            return hasEditor && hasBrowser
        }
        if !editorBrowserSwitch.isEmpty {
            let total = editorBrowserSwitch.reduce(0) { $0 + $1.count }
            results.append(UserInsight(
                category: .workflow,
                title: "编辑器-浏览器频繁切换",
                detail: "共 \(total) 次，可能在查阅文档或调试前端",
                confidence: min(1.0, Double(total) / 50.0),
                relatedApps: editorBrowserSwitch.flatMap { [$0.from, $0.to] },
                dataPoints: total
            ))
        }

        return results
    }

    private func generatePlatformInsights(windowTitles: [(appName: String, windowTitle: String)], appProfile: AppProfile) -> [UserInsight] {
        var results: [UserInsight] = []

        let patterns: [(keyword: String, platform: String, category: String)] = [
            ("github.com", "GitHub", "代码托管"),
            ("gitlab", "GitLab", "代码托管"),
            ("notion.so", "Notion", "知识管理"),
            ("linear.app", "Linear", "项目管理"),
            ("jira", "Jira", "项目管理"),
            ("figma.com", "Figma", "设计协作"),
            ("vercel.com", "Vercel", "部署平台"),
            ("netlify", "Netlify", "部署平台"),
            ("aws.amazon", "AWS", "云平台"),
            ("console.cloud.google", "GCP", "云平台"),
            ("portal.azure", "Azure", "云平台"),
            ("stackoverflow", "StackOverflow", "技术问答"),
            ("docker", "Docker", "容器化"),
        ]

        var platformCounts: [String: Int] = [:]
        for (_, title) in windowTitles {
            let lower = title.lowercased()
            for p in patterns where lower.contains(p.keyword) {
                platformCounts[p.platform, default: 0] += 1
            }
        }

        for (platform, count) in platformCounts.sorted(by: { $0.value > $1.value }).prefix(5) {
            let category = patterns.first { $0.platform == platform }?.category ?? "平台"
            results.append(UserInsight(
                category: .platform,
                title: "\(platform) 使用",
                detail: "\(category)，\(count) 次窗口访问",
                confidence: min(1.0, Double(count) / 5.0),
                relatedApps: [platform],
                dataPoints: count
            ))
        }

        return results
    }

    private func generateContentInsights(clipboards: [(sourceApp: String?, text: String)], appProfile: AppProfile) -> [UserInsight] {
        var results: [UserInsight] = []

        var codeClips = 0
        var urlClips = 0
        for clip in clipboards {
            let text = clip.text
            if text.contains("func ") || text.contains("class ") || text.contains("import ") ||
               text.contains("def ") || text.contains("const ") || text.contains("let ") ||
               text.contains("var ") || text.contains("return ") || text.contains("=>") {
                codeClips += 1
            }
            if text.hasPrefix("http://") || text.hasPrefix("https://") {
                urlClips += 1
            }
        }

        if codeClips > 0 {
            results.append(UserInsight(
                category: .contentType,
                title: "频繁复制代码",
                detail: "\(codeClips) 次代码相关剪贴板操作",
                confidence: min(1.0, Double(codeClips) / 10.0),
                relatedApps: [],
                dataPoints: codeClips
            ))
        }

        if urlClips > 0 {
            results.append(UserInsight(
                category: .contentType,
                title: "频繁复制URL",
                detail: "\(urlClips) 次URL复制，可能在做调研",
                confidence: min(1.0, Double(urlClips) / 5.0),
                relatedApps: [],
                dataPoints: urlClips
            ))
        }

        return results
    }
}
