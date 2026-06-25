---
name: weekly-oss-recommend
description: 每周推荐优秀开源项目。根据用户技术栈（Python后端、Go、Vue3、LangChain、LangGraph、CrewAI、AutoGen、智能体开发），搜索 GitHub 相关优质仓库，翻译 README，以资深架构师视角分析亮点与不足，给出学习建议。仅推送到飞书（feishu:oc_92c9b46accd79149769c935fed40c9a4）。
version: 1.0.0
platforms: [all]
metadata:
  hermes:
    tags: [open-source, recommendation, github, python, go, vue3, ai-agent]
    related_skills: [weekly-oss-recommend]
---

# 优秀开源项目推荐

## 任务背景
用户当前技术栈：Python后端、Go、Vue3、LangChain、LangGraph、CrewAI、AutoGen，聚焦前后端开发与 AI Agent 智能体开发。
每次推荐 1 个高质量开源项目，输出为一份结构化推荐报告。
仅推送到飞书，不要推送到 QQ。

## 执行步骤

### 1. 搜索 GitHub 项目
根据以下策略选择搜索关键词（每次轮换，避免重复）：

**搜索词轮换池（按方向分类，每次轮换不同方向）：**

### Python AI Agent 方向
- `ai agent framework` stars:>1000 language:python
- `llm orchestration` stars:>800 language:python
- `autonomous agent` stars:>500 language:python
- `RAG framework` stars:>1000 language:python
- `multi-agent system` stars:>500 language:python
- `AI function calling` stars:>200 language:python
- `conversational AI agent` stars:>200 language:python
- `ai workflow` stars:>300 language:python
- `LLM application` stars:>500 language:python

### Python 其他方向
- `python async web framework` stars:>3000
- `python data pipeline` stars:>1000
- `fastapi` stars:>5000

### Go 方向
- `go web framework` stars:>2000 language:Go
- `go AI framework` stars:>200 language:Go
- `go LLM` stars:>200 language:Go
- `golang microservice` stars:>1000 language:Go
- `go concurrency` stars:>1000 language:Go
- `go CLI tool` stars:>1000 language:Go
- `golang API framework` stars:>500 language:Go
- `go distributed system` stars:>500 language:Go

### 前端 Vue3 方向
- `vue3 admin` stars:>2000 language:TypeScript
- `vue3 AI chat` stars:>200 language:TypeScript
- `vue3 component library` stars:>1000 language:TypeScript
- `vue3 dashboard` stars:>500 language:TypeScript
- `nuxt` stars:>2000 language:TypeScript

### 主流框架/生态
- `crewai alternative` stars:>300 language:python
- `langgraph workflow` stars:>200 language:python
- `AI code generation` stars:>1000
- `prompt engineering` stars:>2000
- `vector database` stars:>1000

**搜索规则：**
- 使用 `mcp_github_search_repositories` 工具搜索
- 按 stars 降序排列
- 排除已推荐过的项目（若上下文中有历史记录）
- 优先选择近 3 个月内活跃的项目（看最近 commit 时间）
- 首选 README 内容详实、有示例代码的项目

### 2. 获取项目详情
用 `mcp_github_get_file_contents` 获取项目的 README.md。

### 3. 翻译与分析
将 README 关键部分翻译为中文（保留专有名词英文），然后以资深架构师身份撰写分析报告。

### 4. 输出格式

```markdown
# 🌟 本周开源项目推荐

## 📦 项目名称
**GitHub:** https://github.com/{owner}/{repo}
**⭐ Stars:** {数量} | **🍴 Forks:** {数量} | **📅 最近更新:** {日期}
**📝 一句话介绍:** {中文简介}

---

## 📖 README 翻译（摘要）

{翻译后的项目介绍、核心功能、快速安装和使用示例，保留代码块原样}

---

## 🏆 亮点分析（资深架构师视角）

### 核心优势
1. **{亮点1标题}** — {详细说明}
2. **{亮点2标题}** — {详细说明}
3. **{亮点3标题}** — {详细说明}

### 架构设计亮点
- {分析项目的架构设计为何优秀}

### 生态与社区
- {社区活跃度、文档质量、贡献者情况}

---

## ⚠️ 不足与风险

### 短板
1. **{不足1}** — {说明原因和影响}
2. **{不足2}** — {说明原因和影响}

### 潜在风险
- {维护风险、兼容性风险、扩展性限制等}

---

## 📚 学习路径建议

### 如何学习亮点
1. **{学习点1}** — {具体学习步骤和资源}
2. **{学习点2}** — {具体学习步骤和资源}

### 如何规避不足
1. **{规避策略1}** — {实操建议}
2. **{规避策略2}** — {实操建议}

### 推荐阅读
- {相关文档、博客、视频等补充资源}
```

## 注意事项
- 每次推荐必须是不同的项目，不要重复推荐
- 优先推荐星标数在 500-10000 之间的项目（太大的可能太知名，太小的不够成熟）
- 分析要客观，既说优点也说缺点
- 学习建议要具体可执行，不要泛泛而谈
- 翻译要准确流畅，技术术语保留英文

## 版本维护
- 版本号在 SKILL.md frontmatter 的 `version` 字段中维护（当前: 1.0.0）
- 更新时需同步更新 GitHub 和 Gitee 两个仓库
- `hermes skills update` **不会**更新本 skill，需手动从仓库同步