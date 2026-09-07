# 立能派 Agent OS

> 公司内部可持续扩展的企业 Agent 平台。员工通过自然语言与大模型对话，在需要时按会话添加公司业务插件，由 LLM 负责理解、分析、拆解和编排，由确定性业务后端负责真实执行。

## 项目状态

| 项目 | 当前值 |
|---|---|
| 文档基线 | V0.0.0 |
| 软件版本 | V0.3.2 原生能力架构实现；运行闭环与 V0.3.3 验收持续推进 |
| 当前阶段 | Windows → Mac mini M2 可移植 Git 交付与原生能力运行验收 |
| 员工端首选底座 | LibreChat V0.8.7 稳定版，实施时锁定 Tag、Commit 与镜像 Digest |
| 首期运行形态 | Windows / macOS Apple Silicon + Docker Desktop + Web 浏览器 |
| V1.0.0 目标 | 公司内网 Web 正式版 |
| 首批业务能力 | Submit Flow 完整闭环、EMS 只读 Preview |
| 当前写入授权 | 仅 AgentOS 本机部署配置；未授权业务代码改动或 EMS 写入 |

## 文档入口

1. [正式产品 PRD](docs/01_AGENT_OS_PRODUCT_PRD.md)
   - 产品定位、用户、需求、体验、总体架构、安全边界、成功指标和 V1 验收标准。
2. [版本化架构与持续推进任务书](docs/02_VERSIONED_ARCHITECTURE_AND_TASKBOOK.md)
   - V0.0.0 至 V1.0.0 的版本目标、架构变化、任务、依赖、人日、测试、验收门禁和回滚要求。
3. [V0.0.0—V0.5.0 周报式推进与汇报看板](docs/03_V0.0.0_TO_V0.5.0_WEEKLY_PROGRESS_REPORT.md)
   - 沿用既有“周次 → 工作项 → 状态”样式，汇总历史业务成果，并安排 V0.0.0 至 V0.5.0 的逐周任务、交付物、Gate、阻塞项和汇报口径。
4. [V0.1.0 本机运维与手工验收](docs/04_V0.1.0_LOCAL_OPERATIONS.md)
   - V0.1 本机启动、停止、健康检查、持久化位置和手工验收清单。
5. [V0.1.0 Release Record](docs/releases/V0.1.0_RELEASE_RECORD.md)
   - 上游 Tag、Commit、镜像 digest、配置范围和当前验收证据。
6. [V0.2.0 本机运维与验收](docs/05_V0.2.0_LOCAL_OPERATIONS.md)
   - 品牌化配置、真实中转参数、测试命令、Gate 和阻塞处理。
7. [V0.2.0 Release Record](docs/releases/V0.2.0_RELEASE_RECORD.md)
   - V0.2.0 当前交付物、运行证据、能力矩阵和验收结论。
8. [V0.3.0 本机运维与验收](docs/06_V0.3.0_LOCAL_OPERATIONS.md)
   - V0.3 插件目录、会话级能力选择、图片能力入口、验证命令和故障处理。
9. [V0.3.0 Release Record](docs/releases/V0.3.0_RELEASE_RECORD.md)
   - V0.3.0 交付范围、Gate 证据、外部阻塞和下一步输入。
10. [V0.3.1-V0.4.0 原生能力体系重构实施任务书](docs/07_V0.3.1_TO_V0.4.0_NATIVE_CAPABILITY_REFACTOR_TASKBOOK.md)
   - 模型与推理选择、原生 Skills/Tools/智能体市场、图片能力、Submit/EMS 归属、迁移任务、测试 Gate 和回滚要求。
11. [V0.3.2 运行闭环与 V0.3.3 验收任务书](docs/08_V0.3.2_RUNTIME_CLOSURE_AND_V0.3.3_ACCEPTANCE_TASKBOOK.md)
   - 原生 Marketplace/Agent/Skill/MCP 的运行闭环、安全门禁、测试和发布要求。
12. [Windows → Mac mini M2 Git 迁移交付书](docs/09_WINDOWS_TO_MAC_M2_GIT_MIGRATION.md)
   - 仓库边界、系统配置重建、M2 初始化、验证、回滚和 Submit 独立交接要求。

## Mac mini M2 快速入口

本仓库只迁移系统配置，不携带用户、会话、Session、上传文件、生成图片或原始 MongoDB 数据。首次在 Mac 上运行：

```bash
pwsh -NoProfile -File ./scripts/New-AgentOSEnv.ps1
# 编辑 .env 中的公司 LLM 与 Submit 私密参数后：
chmod +x ./scripts/macos/*.sh
./scripts/macos/bootstrap-agentos.sh
```

注册首位管理员后执行 `./scripts/macos/apply-system-config.sh`，系统将从 Git 中的声明式清单恢复角色权限、Skills 和智能体市场内容。完整说明见迁移交付书。

## V0.2.0 当前状态

- 本地服务、中文登录页、立能派 Logo/Favicon、服务端配置挂载、自定义端点隔离和 Chat/Responses 配置合同已通过验证。
- 当前私密 `.env` 已配置公司中转 API；五个文本模型已完成真实对话验证。两个图片模型已经接入 Agent 图片工具，但中转站当前返回“该分组未启用图片生成”，图片能力在外部权限层 `BLOCKED`。
- 默认文本模型为 `gpt-5.5`，默认图片模型为 `gpt-image-2`；图片模型不会混入文本聊天下拉框。
- 服务地址：<http://localhost:3080>。本机注册仍开启，密码由操作者首次注册时设置；项目没有预置通用账号密码。
- 使用 `scripts/Test-AgentOSV02Gate.ps1` 可一次性复核全部 V0.2 Gate。运行报告位于 `deployment/runtime/v0.2/`，该目录已被 Git 忽略，不包含真实密钥。

## V0.3.0 当前状态

- 会话级插件目录、添加/移除 UI、Skill 加载、工具白名单、Capability Gate 和审计引用已完成。
- 当前目录包含 `agentos-demo` 和 `agentos-image` 两个受控插件；未选择插件时不向模型暴露业务工具。
- 图片能力通过 `gpt-5.5 Agent` → `AI 能力` → `AI 生图` 使用，默认图片模型为 `gpt-image-2`，可选 `gpt-image-1.5`。图片模型不会混入普通文本模型下拉框。
- V0.3 静态 Gate 和动态 Gate 均通过；动态报告包含 28 项检查。图片实际生成请求的代码链路已接入，但中转站返回 `Image generation is not enabled for this group`，因此图片模型仍为外部权限阻塞。
- 新会话默认能力为 0；草稿会在首次真实对话创建时迁移到该会话，之后新建会话不会继承插件选择。
- 使用 `scripts/rollback/v0.3.0/Test-AgentOSV03Static.ps1` 和 `scripts/rollback/v0.3.0/Test-AgentOSV03.ps1` 可复核历史 V0.3.0 Gate。运行报告位于 `deployment/runtime/v0.3/`，该目录已被 Git 忽略。

## 一句话架构

```text
员工 Web 工作台
  -> LibreChat 对话与 Agent Runtime
  -> 会话级插件能力门禁
  -> 公司中转 LLM API / 公司业务 MCP Adapter
  -> Submit_Flow_Agent / EMS_Date 等确定性业务后端
  -> 任务进度、人工复核、审计记录和结果文件返回聊天界面
```

## 核心原则

1. **复用成熟开源产品**：不从零开发聊天、会话、Agent、MCP、Skill、账号和管理基础设施。
2. **LLM 是大脑，业务后端是执行器**：模型负责理解和编排，业务规则与真实执行继续由确定性代码负责。
3. **插件按需授权**：未在当前会话添加的插件，不加载 Skill，也不向模型暴露工具定义。
4. **结构化白名单调用**：禁止 Shell、任意 Python/SQL、任意路径、任意 URL 和自由命令执行。
5. **业务状态是真相**：Submit Flow 以 `task.json` 为真相来源；EMS 以配置、源数据、查询证据和 Preview 产物为真相来源。
6. **默认只读、最小权限**：EMS V1 只开放配置校验、源文件检查和 Preview，不开放任何写入工具。
7. **密钥不进入终端**：模型 API Key、EMS Authorization 和其他凭据只保存在服务端私密配置中。
8. **版本必须可验收**：每个 `V0.N.0` 都必须形成可运行成品、测试证据和版本验收记录。

## V1 产品边界

### 包含

- 公司品牌化 Web Agent 工作台。
- 普通多轮对话、流式输出、会话与附件管理。
- 公司中转 API 接入。
- 会话级插件选择器与能力门禁。
- Submit Flow 文件收集、运行、人工复核、确认和结果文件闭环。
- EMS 配置校验、源文件检查、只读 Preview 和报告展示。
- 内网账号、基础角色与插件权限。
- 调用审计、错误追踪、备份恢复和内网部署。

### 不包含

- EMS 生产或 SIT 写入。
- 任意业务脚本、Shell、Python 或 SQL 执行入口。
- 独立自研的完整后台管理系统。
- Tauri/Electron 桌面客户端。
- 公网开放、大规模多租户和高并发集群。
- 未经单独 PRD 与授权的第三个业务插件。

## 版本路线摘要

| 版本 | 版本名称 | 可验收结果 |
|---|---|---|
| V0.0.0 | 文档与立项基线 | PRD、架构、任务书评审完成 |
| V0.1.0 | 本机基础版 | LibreChat 在本机稳定运行并持久化 |
| V0.2.0 | 品牌化对话版 | 公司外壳与中转 API 多轮对话可用 |
| V0.3.0 | 插件框架版 | 插件按会话添加，未添加时能力不可见 |
| V0.4.0 | Submit Flow 版 | 成功、人工复核和结果文件闭环 |
| V0.5.0 | EMS Preview 版 | 只读校验、解析、Preview 和报告闭环 |
| V0.6.0 | 本机集成 MVP | 两项业务能力在统一工作台演示通过 |
| V0.7.0 | 内网试点版 | 受控员工账号可通过内网安全访问 |
| V0.8.0 | 管理与权限版 | 账号、角色、插件授权和基础审计可管理 |
| V0.9.0 | Release Candidate | 安全、性能、恢复、UAT 和运维门禁通过 |
| V1.0.0 | 内网 Web 正式版 | 发布、培训、监控、备份和回滚体系完整 |

## 版本管理

- `V0.N.0`：新增一个可独立演示和验收的能力里程碑。
- `V0.N.P`：只修复缺陷和安全问题，不扩大功能范围。
- `V1.0.0`：全部正式发布门禁通过，不代表项目停止演进。
- 后续桌面端、独立控制中心和更多岗位插件进入 `V1.x` 或 `V2.0.0` 路线。

## 仓库边界

```text
K:\Workers\AgentOS              公司 Agent 平台与适配层
K:\Workers\Submit_Flow_Agent   现有填报业务后端，保持独立
K:\Workers\EMS_Date            现有 EMS 确定性业务后端，保持独立
```

AgentOS 不复制两个业务仓库的核心算法，不把聊天记录当作业务状态，不绕过业务后端已有门禁。业务接入通过独立、可测试、可审计的 Adapter 完成。

## 当前仍需确认的信息

- 中转站为图片模型分组开通图片生成权限，并重新运行 V0.2 模型矩阵。
- 内网试点账号和允许访问的网段。
- V0.4.0 Submit Flow 接入前的业务工具合同和验收样例。

Base URL、API Key、模型 ID、协议和品牌资源已经写入本机私密配置或部署文件，不应复制到聊天、文档或 Git。
