# 🌟 Weekly OSS Recommend

每周推荐优秀开源项目 — 根据你的技术栈自动搜索、翻译 README、架构师视角分析。

## 🎯 功能

覆盖 **5 个技术方向**，共 **28 个搜索关键词**：

| 方向 | 关键词数 | 示例 |
|------|----------|------|
| Python AI Agent | 9 | agent framework, RAG, LLM app |
| Python 其他 | 3 | web framework, data pipeline |
| Go 语言 | 8 | web framework, AI, LLM, microservice |
| Vue3 前端 | 5 | admin, chat, component library |
| 主流框架/生态 | 3 | crewai alternative, prompt engineering |

## 📦 安装

### 方式一：一键安装（推荐）

告诉你的 Hermes Agent：

> 请帮我安装 weekly-oss-recommend skill，从 https://github.com/P1M0U/skills-space 仓库

Agent 会自动执行：

```bash
# 克隆仓库
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 复制 skill 目录
cp -r /tmp/skills-space/weekly-oss-recommend ~/.hermes/skills/

# 清理
rm -rf /tmp/skills-space
```

### 方式二：手动安装

```bash
# 克隆仓库
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 复制 skill 目录
cp -r /tmp/skills-space/weekly-oss-recommend ~/.hermes/skills/

# 清理
rm -rf /tmp/skills-space
```

## 🚀 使用

### 手动触发

在 Hermes 会话中说：

```
推荐一个开源项目
```

或

```
本周有什么好的开源项目推荐
```

### 定时任务

```bash
# 周六 + 周日早上 10:00 自动推荐，推送到飞书
hermes cron create --name "优秀开源项目推荐（周六）" \
  --schedule "0 2 * * 6" \
  --skill weekly-oss-recommend \
  --prompt "推荐一个优秀开源项目" \
  --deliver "feishu:oc_92c9b46accd79149769c935fed40c9a4"

hermes cron create --name "优秀开源项目推荐（周日）" \
  --schedule "0 2 * * 0" \
  --skill weekly-oss-recommend \
  --prompt "推荐一个优秀开源项目" \
  --deliver "feishu:oc_92c9b46accd79149769c935fed40c9a4"
```

## 📊 输出格式

每次推荐包含：

1. **项目概览** — GitHub 链接、Stars、Forks、最近更新时间
2. **README 翻译** — 关键部分翻译为中文，代码块保留原样
3. **亮点分析** — 资深架构师视角的核心优势和架构设计
4. **不足与风险** — 客观的短板和潜在风险
5. **学习路径** — 如何学习亮点、如何规避不足

## ⚠️ 注意事项

- 每次推荐不同的项目，自动避免重复
- 优先推荐 500-10000 Stars 的项目
- 仅推送到飞书，不推送到其他平台
- 需要 GitHub MCP 工具支持（`mcp_github_search_repositories`）

## 🔗 镜像仓库

- GitHub: https://github.com/P1M0U/skills-space
- Gitee: https://gitee.com/pimou/skills-space

## 📄 License

MIT