import Foundation

struct SkillCatalog {

    // MARK: - LLM-driven recommendation (primary path)

    /// Generates skill recommendations using an LLM that consumes the user's full analysis profile.
    /// Built-in OpenClaw skills (github, slack, notion, ...) are still surfaced via rule matching
    /// because they are platform-bound and don't need LLM creativity.
    @MainActor
    static func recommendWithLLM(from result: InsightEngine.AnalysisResult,
                                 analytics: AnalyticsEngine,
                                 days: Int,
                                 client: OpenAIClient) async throws -> [SkillRecommendation] {
        async let llmTask: [SkillRecommendation] = {
            let generator = LLMSkillGenerator(client: client)
            return try await generator.generate(from: result, analytics: analytics, days: days)
        }()

        let builtIns = matchBuiltInSkills(result)
        let llmSkills = try await llmTask

        var all = builtIns + llmSkills
        all.sort { $0.matchScore > $1.matchScore }
        return all
    }

    // MARK: - Rule-based recommendation (fallback when no API key / LLM unavailable)

    static func recommend(from result: InsightEngine.AnalysisResult) -> [SkillRecommendation] {
        var all: [SkillRecommendation] = []

        all.append(contentsOf: matchBuiltInSkills(result))
        all.append(contentsOf: generateCustomSkills(result))

        all.sort { $0.matchScore > $1.matchScore }
        return all
    }

    // MARK: - Built-in OpenClaw Skills

    private static func matchBuiltInSkills(_ result: InsightEngine.AnalysisResult) -> [SkillRecommendation] {
        var matched: [SkillRecommendation] = []
        let cats = result.appProfile.categories
        let appNames = Set(result.appProfile.topApps.map { $0.name.lowercased() })
        let insights = result.insights

        let hasGitHub = insights.contains { $0.relatedApps.contains("GitHub") }
        let hasTerminal = (cats["终端"] ?? 0) > 0.01
        let hasBrowser = (cats["浏览器"] ?? 0) > 0.01
        let hasIDE = (cats["IDE"] ?? 0) + (cats["编辑器"] ?? 0) > 0.01
        let hasNotion = appNames.contains { $0.contains("notion") } || insights.contains { $0.relatedApps.contains("Notion") }
        let hasDesign = (cats["设计"] ?? 0) > 0.01

        if hasGitHub || hasTerminal {
            matched.append(SkillRecommendation(
                skillId: "github",
                name: "github",
                emoji: "🐙",
                description: "GitHub CLI 操作：PR、Issue、CI 状态查看与管理",
                matchScore: hasGitHub ? 0.95 : 0.7,
                matchReasons: hasGitHub
                    ? ["检测到你频繁访问 GitHub", "终端使用活跃，适合 gh CLI"]
                    : ["终端使用活跃，gh CLI 可提升 Git 工作流效率"],
                category: .coding,
                isBuiltIn: true,
                skillMarkdown: ""
            ))
        }

        if hasIDE && hasTerminal {
            matched.append(SkillRecommendation(
                skillId: "coding-agent",
                name: "coding-agent",
                emoji: "🧩",
                description: "将编码任务委派给 Codex/Claude Code/Pi 等 AI Agent",
                matchScore: 0.85,
                matchReasons: ["你是活跃的开发者", "IDE + 终端高频使用", "可以用 AI Agent 加速编码"],
                category: .coding,
                isBuiltIn: true,
                skillMarkdown: ""
            ))
        }

        if hasBrowser {
            matched.append(SkillRecommendation(
                skillId: "summarize",
                name: "summarize",
                emoji: "🧾",
                description: "快速摘要 URL、本地文件、YouTube 视频内容",
                matchScore: 0.7,
                matchReasons: ["你频繁使用浏览器", "summarize 可快速提取网页/视频内容"],
                category: .research,
                isBuiltIn: true,
                skillMarkdown: ""
            ))
        }

        if hasNotion {
            matched.append(SkillRecommendation(
                skillId: "notion",
                name: "notion",
                emoji: "📝",
                description: "通过 Notion API 管理页面、数据库和内容块",
                matchScore: 0.9,
                matchReasons: ["检测到你使用 Notion", "可以直接在龙虾中操作 Notion"],
                category: .productivity,
                isBuiltIn: true,
                skillMarkdown: ""
            ))
        }

        if hasDesign {
            let designApps = result.appProfile.topApps.filter {
                let lower = $0.name.lowercased()
                return lower.contains("figma") || lower.contains("sketch") || lower.contains("photoshop")
            }
            if !designApps.isEmpty {
                matched.append(SkillRecommendation(
                    skillId: "openai-image-gen",
                    name: "openai-image-gen",
                    emoji: "🎨",
                    description: "使用 OpenAI DALL·E 生成和编辑图片",
                    matchScore: 0.75,
                    matchReasons: ["检测到设计工具使用", "AI 图片生成可以加速设计工作流"],
                    category: .design,
                    isBuiltIn: true,
                    skillMarkdown: ""
                ))
            }
        }

        let commHours = (cats["沟通"] ?? 0)
        if commHours > 0.01 {
            if appNames.contains(where: { $0.contains("slack") }) {
                matched.append(SkillRecommendation(
                    skillId: "slack",
                    name: "slack",
                    emoji: "💬",
                    description: "通过 Slack API 发送消息、管理频道",
                    matchScore: 0.8,
                    matchReasons: ["检测到你使用 Slack \(String(format: "%.1f", commHours))h", "可在龙虾中直接操作 Slack"],
                    category: .communication,
                    isBuiltIn: true,
                    skillMarkdown: ""
                ))
            }
            if appNames.contains(where: { $0.contains("discord") }) {
                matched.append(SkillRecommendation(
                    skillId: "discord",
                    name: "discord",
                    emoji: "🎮",
                    description: "Discord Bot 操作与消息管理",
                    matchScore: 0.75,
                    matchReasons: ["检测到你使用 Discord", "可在龙虾中直接操作 Discord"],
                    category: .communication,
                    isBuiltIn: true,
                    skillMarkdown: ""
                ))
            }
        }

        return matched
    }

    // MARK: - Custom Generated Skills

    private static func generateCustomSkills(_ result: InsightEngine.AnalysisResult) -> [SkillRecommendation] {
        var customs: [SkillRecommendation] = []
        let langs = result.languageProfile.detected.prefix(3)
        let cats = result.appProfile.categories
        let role = result.workflowProfile.primaryRole

        if let topLang = langs.first, topLang.confidence > 0.05 {
            let skill = makeLanguageSkill(language: topLang.language, fileCount: topLang.fileCount)
            customs.append(skill)
        }

        let ideHours = (cats["IDE"] ?? 0) + (cats["编辑器"] ?? 0)
        let termHours = cats["终端"] ?? 0
        if ideHours > 0.02 && termHours > 0.01 {
            customs.append(makeDevWorkflowSkill(result: result))
        }

        if (cats["API测试"] ?? 0) > 0.01 {
            customs.append(makeAPITestingSkill(result: result))
        }

        if (cats["数据库"] ?? 0) > 0.01 {
            customs.append(makeDatabaseSkill(result: result))
        }

        if (cats["DevOps"] ?? 0) > 0.01 || (cats["容器"] ?? 0) > 0.01 {
            customs.append(makeDockerSkill(result: result))
        }

        if role == "前端工程师" || (cats["浏览器"] ?? 0) > 0.05 && ideHours > 0.02 {
            customs.append(makeFrontendSkill(result: result))
        }

        return customs
    }

    // MARK: - Skill Generators

    private static func makeLanguageSkill(language: String, fileCount: Int) -> SkillRecommendation {
        let id = "\(language.lowercased())-assistant"
        let langLower = language.lowercased()
        let emoji: String
        switch langLower {
        case "python": emoji = "🐍"
        case "swift": emoji = "🦅"
        case "javascript", "typescript": emoji = "⚡"
        case "go": emoji = "🐹"
        case "rust": emoji = "🦀"
        case "java", "kotlin": emoji = "☕"
        case "ruby": emoji = "💎"
        case "c", "c++", "c/c++": emoji = "⚙️"
        default: emoji = "💻"
        }

        let body = Self.languageSkillBody(language: language)

        return SkillRecommendation(
            skillId: id,
            name: id,
            emoji: emoji,
            description: "\(language) 开发助手：代码审查、重构建议、最佳实践指导和项目脚手架。基于你 \(fileCount) 个文件活动检测到的 \(language) 使用习惯定制。",
            matchScore: min(0.95, 0.6 + Double(fileCount) / 200.0),
            matchReasons: [
                "检测到 \(fileCount) 个 \(language) 相关文件事件",
                "为你的 \(language) 开发习惯量身定制"
            ],
            category: .coding,
            isBuiltIn: false,
            skillMarkdown: body
        )
    }

    private static func makeDevWorkflowSkill(result: InsightEngine.AnalysisResult) -> SkillRecommendation {
        let topApps = result.appProfile.topApps.prefix(5).map(\.name)
        let topLangs = result.languageProfile.detected.prefix(3).map(\.language)
        let body = devWorkflowSkillBody(apps: topApps, languages: topLangs, role: result.workflowProfile.primaryRole)

        return SkillRecommendation(
            skillId: "my-dev-workflow",
            name: "my-dev-workflow",
            emoji: "🔧",
            description: "个人开发工作流助手：基于你的 \(result.workflowProfile.primaryRole) 角色和常用工具(\(topApps.prefix(3).joined(separator: "、")))定制的工作流自动化。",
            matchScore: 0.88,
            matchReasons: [
                "角色: \(result.workflowProfile.primaryRole)",
                "常用工具: \(topApps.prefix(3).joined(separator: "、"))",
                "常用语言: \(topLangs.joined(separator: "、"))"
            ],
            category: .productivity,
            isBuiltIn: false,
            skillMarkdown: body
        )
    }

    private static func makeAPITestingSkill(result: InsightEngine.AnalysisResult) -> SkillRecommendation {
        SkillRecommendation(
            skillId: "api-tester",
            name: "api-tester",
            emoji: "🔌",
            description: "API 测试助手：快速构建 curl 请求、解析响应、对比 API 版本。检测到你使用 API 测试工具。",
            matchScore: 0.78,
            matchReasons: ["检测到 API 测试工具使用", "可用 curl/httpie 直接在终端测试"],
            category: .coding,
            isBuiltIn: false,
            skillMarkdown: apiTestingSkillBody()
        )
    }

    private static func makeDatabaseSkill(result: InsightEngine.AnalysisResult) -> SkillRecommendation {
        SkillRecommendation(
            skillId: "db-assistant",
            name: "db-assistant",
            emoji: "🗄️",
            description: "数据库助手：SQL 查询构建、schema 设计建议、数据迁移脚手架。检测到数据库工具使用。",
            matchScore: 0.75,
            matchReasons: ["检测到数据库管理工具使用"],
            category: .data,
            isBuiltIn: false,
            skillMarkdown: databaseSkillBody()
        )
    }

    private static func makeDockerSkill(result: InsightEngine.AnalysisResult) -> SkillRecommendation {
        SkillRecommendation(
            skillId: "docker-helper",
            name: "docker-helper",
            emoji: "🐳",
            description: "Docker/容器助手：Dockerfile 编写、docker-compose 配置、容器调试。检测到 Docker 使用。",
            matchScore: 0.8,
            matchReasons: ["检测到 Docker/容器工具使用", "可在龙虾中直接管理容器"],
            category: .devops,
            isBuiltIn: false,
            skillMarkdown: dockerSkillBody()
        )
    }

    private static func makeFrontendSkill(result: InsightEngine.AnalysisResult) -> SkillRecommendation {
        let frameworks = result.languageProfile.detected.filter {
            ["TypeScript", "JavaScript", "Vue", "Svelte", "CSS", "HTML"].contains($0.language)
        }.map(\.language)

        return SkillRecommendation(
            skillId: "frontend-helper",
            name: "frontend-helper",
            emoji: "🌐",
            description: "前端开发助手：组件设计、CSS/样式调试、构建优化。检测到前端技术栈 \(frameworks.joined(separator: "/"))。",
            matchScore: 0.82,
            matchReasons: ["检测到前端技术栈", "编辑器-浏览器频繁切换"],
            category: .coding,
            isBuiltIn: false,
            skillMarkdown: frontendSkillBody(frameworks: frameworks)
        )
    }

    // MARK: - SKILL.md Body Templates

    private static func languageSkillBody(language: String) -> String {
        """
        ---
        name: \(language.lowercased())-assistant
        description: "\(language) development assistant: code review, refactoring suggestions, best practices, and project scaffolding. Use when: (1) writing or reviewing \(language) code, (2) setting up new \(language) projects, (3) debugging \(language) issues, (4) optimizing \(language) performance."
        metadata: { "openclaw": { "emoji": "\(languageEmoji(language))" } }
        ---

        # \(language) Assistant

        Personalized \(language) development assistant based on your usage patterns.

        ## When to Use

        ✅ **USE this skill when:**
        - Writing or reviewing \(language) code
        - Setting up new \(language) projects
        - Debugging \(language)-specific issues
        - Need \(language) best practices or idiomatic patterns
        - Refactoring existing \(language) code

        ❌ **DON'T use when:**
        - General programming questions not specific to \(language)
        - Infrastructure/deployment (use devops skills)

        ## Code Review Checklist

        When reviewing \(language) code:
        1. Check for idiomatic \(language) patterns
        2. Verify error handling completeness
        3. Look for performance anti-patterns
        4. Ensure proper naming conventions
        5. Validate test coverage

        ## Project Setup

        ```bash
        # Quick project scaffold
        \(scaffoldCommand(language))
        ```

        ## Best Practices

        \(bestPractices(language))
        """
    }

    private static func devWorkflowSkillBody(apps: [String], languages: [String], role: String) -> String {
        """
        ---
        name: my-dev-workflow
        description: "Personal dev workflow: automate repetitive tasks based on your \(role) role. Tools: \(apps.prefix(3).joined(separator: ", ")). Languages: \(languages.joined(separator: ", ")). Use when: (1) starting new tasks, (2) switching between tools, (3) automating repeated patterns."
        metadata: { "openclaw": { "emoji": "🔧" } }
        ---

        # My Dev Workflow

        Personalized workflow assistant for a **\(role)**.

        ## Your Environment

        - **Tools**: \(apps.joined(separator: ", "))
        - **Languages**: \(languages.joined(separator: ", "))

        ## When to Use

        ✅ **USE this skill when:**
        - Starting a new development task
        - Need to set up project boilerplate
        - Automating repetitive dev patterns
        - Context-switching between tools

        ## Quick Actions

        ### New Feature Workflow
        ```bash
        # 1. Create branch
        git checkout -b feature/your-feature

        # 2. Scaffold (if needed)
        # ... based on your stack

        # 3. Dev loop
        # Edit → Test → Commit

        # 4. PR
        gh pr create --title "feat: description" --body "..."
        ```

        ### Daily Start
        ```bash
        # Check what's pending
        gh pr list --author @me
        gh issue list --assignee @me

        # Pull latest
        git pull --rebase
        ```

        ### Quick Debug
        ```bash
        # Recent logs
        git log --oneline -10

        # What changed
        git diff --stat HEAD~3
        ```
        """
    }

    private static func apiTestingSkillBody() -> String {
        """
        ---
        name: api-tester
        description: "API testing assistant: build curl requests, parse responses, compare API versions, generate test suites. Use when: (1) testing API endpoints, (2) debugging HTTP requests, (3) generating API documentation."
        metadata: { "openclaw": { "emoji": "🔌", "requires": { "bins": ["curl"] } } }
        ---

        # API Tester

        Quick API testing from the command line.

        ## When to Use

        ✅ **USE this skill when:**
        - Testing REST/GraphQL endpoints
        - Debugging HTTP request/response issues
        - Comparing API versions or environments
        - Generating curl commands from API specs

        ## Quick Commands

        ### GET Request
        ```bash
        curl -s "https://api.example.com/endpoint" | jq .
        ```

        ### POST with JSON
        ```bash
        curl -s -X POST "https://api.example.com/endpoint" \\
          -H "Content-Type: application/json" \\
          -H "Authorization: Bearer $TOKEN" \\
          -d '{"key": "value"}'
        ```

        ### Measure Response Time
        ```bash
        curl -w "\\nTime: %{time_total}s\\nStatus: %{http_code}\\n" -o /dev/null -s "URL"
        ```

        ## Tips
        - Use `jq` for JSON formatting and filtering
        - Use `-v` for verbose output including headers
        - Save common requests as shell aliases
        """
    }

    private static func databaseSkillBody() -> String {
        """
        ---
        name: db-assistant
        description: "Database assistant: SQL query building, schema design, migration scaffolding, performance analysis. Use when: (1) writing complex SQL, (2) designing schemas, (3) debugging query performance, (4) planning migrations."
        metadata: { "openclaw": { "emoji": "🗄️" } }
        ---

        # Database Assistant

        Help with database operations and SQL.

        ## When to Use

        ✅ **USE this skill when:**
        - Writing or optimizing SQL queries
        - Designing database schemas
        - Planning data migrations
        - Debugging query performance

        ## Query Patterns

        ### Pagination
        ```sql
        SELECT * FROM table
        ORDER BY created_at DESC
        LIMIT 20 OFFSET 0;
        ```

        ### Common Table Expressions
        ```sql
        WITH recent AS (
            SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days'
        )
        SELECT customer_id, COUNT(*) as order_count
        FROM recent
        GROUP BY customer_id
        ORDER BY order_count DESC;
        ```

        ## Performance Tips
        - Always check EXPLAIN ANALYZE for slow queries
        - Add indexes on frequently filtered/joined columns
        - Avoid SELECT * in production code
        - Use connection pooling for high-throughput apps
        """
    }

    private static func dockerSkillBody() -> String {
        """
        ---
        name: docker-helper
        description: "Docker/container assistant: Dockerfile writing, docker-compose configuration, container debugging, image optimization. Use when: (1) writing Dockerfiles, (2) configuring docker-compose, (3) debugging container issues, (4) optimizing image size."
        metadata: { "openclaw": { "emoji": "🐳", "requires": { "bins": ["docker"] } } }
        ---

        # Docker Helper

        Container management and Docker best practices.

        ## When to Use

        ✅ **USE this skill when:**
        - Writing or optimizing Dockerfiles
        - Setting up docker-compose
        - Debugging container issues
        - Optimizing image sizes

        ## Quick Commands

        ### Container Management
        ```bash
        # List running containers
        docker ps

        # Logs
        docker logs -f container_name

        # Shell into container
        docker exec -it container_name /bin/sh

        # Cleanup
        docker system prune -af
        ```

        ### Docker Compose
        ```bash
        # Start all services
        docker compose up -d

        # Rebuild and restart
        docker compose up -d --build

        # View logs
        docker compose logs -f service_name
        ```

        ## Dockerfile Best Practices
        - Use multi-stage builds to reduce image size
        - Order layers from least to most frequently changed
        - Use .dockerignore to exclude unnecessary files
        - Pin base image versions (avoid :latest in production)
        - Combine RUN commands to reduce layers
        """
    }

    private static func frontendSkillBody(frameworks: [String]) -> String {
        let stack = frameworks.isEmpty ? "Web" : frameworks.joined(separator: "/")
        return """
        ---
        name: frontend-helper
        description: "Frontend development assistant for \(stack): component design, CSS debugging, build optimization, responsive design. Use when: (1) building UI components, (2) debugging CSS/layout, (3) optimizing frontend builds, (4) responsive design issues."
        metadata: { "openclaw": { "emoji": "🌐" } }
        ---

        # Frontend Helper

        Frontend development assistant for your **\(stack)** stack.

        ## When to Use

        ✅ **USE this skill when:**
        - Building or refactoring UI components
        - Debugging CSS/layout issues
        - Optimizing frontend build performance
        - Handling responsive design
        - Setting up frontend tooling

        ## Quick Patterns

        ### Component Scaffold
        Create clean, reusable components with proper typing and separation of concerns.

        ### CSS Debug
        ```bash
        # Quick outline all elements
        * { outline: 1px solid red !important; }
        ```

        ### Performance Check
        ```bash
        # Bundle size analysis
        npx source-map-explorer build/static/js/*.js

        # Lighthouse audit
        npx lighthouse http://localhost:3000 --output html
        ```

        ## Tips
        - Use CSS Grid for layout, Flexbox for alignment
        - Lazy load below-the-fold components
        - Optimize images with next/image or similar
        - Use CSS custom properties for theming
        """
    }

    // MARK: - Helpers

    private static func languageEmoji(_ lang: String) -> String {
        switch lang.lowercased() {
        case "python": return "🐍"
        case "swift": return "🦅"
        case "javascript", "typescript": return "⚡"
        case "go": return "🐹"
        case "rust": return "🦀"
        case "java", "kotlin": return "☕"
        case "ruby": return "💎"
        default: return "💻"
        }
    }

    private static func scaffoldCommand(_ lang: String) -> String {
        switch lang.lowercased() {
        case "python": return "python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt"
        case "swift": return "swift package init --type executable"
        case "typescript": return "npx create-next-app@latest my-app --typescript"
        case "javascript": return "npm init -y && npm install"
        case "go": return "go mod init myproject"
        case "rust": return "cargo init myproject"
        case "java": return "mvn archetype:generate -DgroupId=com.example -DartifactId=myapp"
        case "kotlin": return "gradle init --type kotlin-application"
        default: return "# Initialize your \(lang) project"
        }
    }

    private static func bestPractices(_ lang: String) -> String {
        switch lang.lowercased() {
        case "python":
            return """
            - Use type hints for function signatures
            - Follow PEP 8 style guide
            - Use virtual environments for dependency isolation
            - Prefer f-strings over format/concatenation
            - Use pathlib over os.path
            """
        case "swift":
            return """
            - Use value types (structs) by default
            - Leverage protocol-oriented programming
            - Use async/await for concurrency
            - Prefer let over var
            - Use guard for early returns
            """
        case "typescript", "javascript":
            return """
            - Use strict TypeScript configuration
            - Prefer const over let, avoid var
            - Use async/await over callbacks/promises
            - Leverage union types and type guards
            - Keep functions small and focused
            """
        case "go":
            return """
            - Handle errors explicitly, don't ignore them
            - Use goroutines and channels for concurrency
            - Keep interfaces small (1-3 methods)
            - Use table-driven tests
            - Run go vet and golint regularly
            """
        case "rust":
            return """
            - Leverage the ownership system, avoid unnecessary clones
            - Use Result/Option for error handling
            - Prefer iterators over manual loops
            - Write unit tests alongside code
            - Use clippy for linting
            """
        default:
            return """
            - Follow language-specific style guides
            - Write tests for critical paths
            - Keep functions focused and small
            - Document non-obvious logic
            """
        }
    }
}
