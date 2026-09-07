# AgentOS Windows → Mac mini M2 Git 迁移与续开发交付书

## 1. 文档目的

本文是 AgentOS 从当前 Windows 工作站迁移到 Mac mini M2 的唯一执行基线。迁移目标不是复制整台机器，而是形成一个可审计、可克隆、可在空数据库上重建系统能力的 Git 交付物。

目标仓库：`https://github.com/j1173134496-png/Agent-OS.git`（Private）。

本次已确认的决策：

1. 目标设备是 Apple Silicon M2（`arm64`）。
2. 数据库只迁移系统配置，不迁移用户、聊天、会话、历史任务或审计数据。
3. Submit Flow 保持独立仓库，Mac 可访问公司内部 Git；禁止把 Submit 源码复制进 AgentOS。

## 2. 迁移后仓库应包含什么

| 类别 | Git 中的来源 | 迁移方式 |
|---|---|---|
| AgentOS 平台代码 | `source/librechat-maintained/` | 作为普通目录纳入单一仓库，不再使用缺失 `.gitmodules` 的悬空 gitlink |
| 部署配置 | `deployment/compose.yaml`、`deployment/librechat.yaml` | 提交无密钥配置；真实值由 `.env` 在目标机注入 |
| 模型与推理合同 | `deployment/agentos-reasoning-matrix.json` | Git 声明式恢复 |
| 智能体市场内容 | `deployment/agents/*.json` | `Sync-AgentOSAgents.ps1` 写入新数据库 |
| Skills | `deployment/skill/*/SKILL.md` | 容器挂载并由 Agent 清单引用 |
| 权限策略 | `Sync-AgentOSV032Policy.ps1` | 首位管理员建立后写入 ADMIN/USER 权限 |
| 插件/回滚能力 | 已跟踪的兼容代码、回滚脚本和发布记录 | 保留用于回退，不作为员工端新入口 |
| 文档与 Gate | `docs/`、`scripts/Test-*` | 作为续开发和验收依据 |
| 数据库系统配置 | `deployment/system-config/system-config-manifest.json` | 空库 + 声明式脚本重建，不提交 MongoDB 文件 |

## 3. 明确禁止进入 Git 的内容

- `.env`、API Key、JWT Secret、Submit 服务 Token、数据库口令。
- `deployment/data/` 下的 MongoDB、Meilisearch、pgvector 原始文件。
- 用户、Session、对话、消息、交易、审计事件。
- `deployment/uploads/`、`deployment/images/` 中的附件、头像和生成图片。
- 日志、运行缓存、`node_modules`、构建产物、测试临时文件。
- Submit Flow 与 EMS 的业务源码副本。

这些排除项不是“遗漏”，而是本次系统配置迁移的数据边界。目标机使用新数据库，可避免把 Windows 测试账号和历史业务数据带入新的开发环境。

## 4. 仓库结构原则

迁移前 `source/librechat-maintained` 是一个嵌套 Git 仓库，AgentOS 根仓库只记录 gitlink，且没有 `.gitmodules`。这种状态下普通 `git clone` 得不到 LibreChat 源码。

正式迁移必须把该目录转换为根仓库中的普通源码目录，并保留一份转换前 Git bundle 作为本机离线备份。完成后在 Mac 上执行一次普通 `git clone` 即可获得 AgentOS 全部平台源码，不需要猜测或手动补子模块。

## 5. Windows 端发布步骤

1. 冻结当前 AgentOS 与嵌套 LibreChat 工作树，记录分支、提交和差异。
2. 执行密钥扫描，确认真实 `.env`、Token 和用户数据未被跟踪。
3. 提交嵌套 LibreChat 当前开发改动，并生成离线 Git bundle。
4. 把 gitlink 转换为根仓库内的普通源码目录。
5. 提交 Agent、Skill、MCP、权限、Gate、跨平台脚本和本迁移文档。
6. 获取 GitHub 私有仓库的现有 `main`，使用允许无共同祖先的普通合并保留远端初始提交；禁止 force push。
7. 在新的临时目录执行干净克隆，检查源码、排除项、配置生成和静态 Gate。
8. 推送 `main` 和带日期的 Windows 交接 Tag。

## 6. Mac mini M2 首次部署

### 6.1 前置条件

- macOS 已更新。
- 安装 Git、Docker Desktop for Apple Silicon、PowerShell 7（命令名 `pwsh`）。
- Docker Desktop 已启动，至少预留 8 GB 内存和足够磁盘空间。
- 能访问 GitHub 私有仓库、公司 LLM 地址和 Submit 内部 Git。

### 6.2 获取两个独立仓库

```bash
git clone https://github.com/j1173134496-png/Agent-OS.git
cd Agent-OS

# 在 Agent-OS 外的同级目录克隆 Submit；实际 URL 使用公司内部 Git 地址。
# git clone <SUBMIT_INTERNAL_GIT_URL> ../Submit_Flow_Agent
```

Submit 的运行地址通过 `.env` 中的 `SUBMIT_MCP_URL` 注入。AgentOS 不依赖 Windows 盘符，也不直接挂载 Submit 源码目录。

### 6.3 生成私密环境

```bash
pwsh -NoProfile -File ./scripts/New-AgentOSEnv.ps1
```

编辑 `.env`，至少设置：

- `AGENTOS_LLM_BASE_URL`：公司中转基础地址，不重复填写 `/v1`。
- `AGENTOS_LLM_API_KEY`：目标环境真实 Key。
- `SUBMIT_MCP_URL`：从 AgentOS 容器可访问的 Submit Streamable HTTP MCP 地址。
- `SUBMIT_MCP_TOKEN`：目标环境独立服务 Token，禁止复用或从 Windows 明文复制到 Git。

如 Submit 运行在同一台 Mac 宿主机，可继续使用 `host.docker.internal`。如运行在其他内网设备，应填写该设备的受控内网地址并同步更新允许地址配置。

### 6.4 两阶段初始化

第一阶段会构建原生 `linux/arm64` AgentOS API 镜像，启动空 MongoDB 和 Web：

```bash
chmod +x ./scripts/macos/*.sh
./scripts/macos/bootstrap-agentos.sh
```

打开 `http://localhost:3080`，注册首位管理员。首次注册完成后执行：

```bash
./scripts/macos/apply-system-config.sh
```

第二阶段会同步 ADMIN/USER 权限、Skill 引用、智能体市场清单和 ACL。它不会创建或复制普通用户，也不会恢复旧聊天。

后续日常启动：

```bash
./scripts/macos/start-agentos.sh
```

## 7. M2 容器策略

Windows 发布配置继续保留已验证的 `linux/amd64` 镜像 digest。Mac 脚本通过进程环境覆盖配置：

- API 从仓库源码构建为 `agentos/librechat:v0.3.2-m2`。
- API 和 MongoDB 使用 `linux/arm64`。
- MongoDB 首次使用与 Windows 一致的 `8.0.20` 版本标签。

Mac 标签属于开发迁移配置，不等于新的正式发布 digest。完成 M2 全量验收后，应构建并登记 arm64 或 multi-arch digest，并在新 Release Record 中固定它；在此之前不得把 M2 本地标签描述为正式生产制品。

## 8. 验收清单

### 8.1 Git 完整性

- 普通 clone 后存在 `source/librechat-maintained/package.json`，且目录内没有独立 `.git`。
- `git status` 干净。
- `.env`、数据目录、上传、用户图片和日志均未被跟踪。
- 根仓库能追溯 Windows 交接提交、远端初始提交和交接 Tag。

### 8.2 系统配置恢复

- 空库启动后可注册首位 ADMIN。
- `Sync-AgentOSV032Policy.ps1` 成功，ADMIN/USER 权限与声明一致。
- `Sync-AgentOSAgents.ps1` 成功，“智能填报助手”出现在智能体市场。
- 普通 USER 可使用但不能创建/公开分享公司 Agent。
- 新数据库没有 Windows 用户、会话、消息或历史任务。

### 8.3 运行验收

```bash
./scripts/macos/verify-agentos.sh
```

最低通过条件：API/MongoDB 健康、`/readyz` 为 200、静态 Gate 通过、V0.3.2 Gate 无配置漂移。LLM、图片和 Submit 联调必须基于 Mac 的真实网络与权限重新生成证据，Windows 上的旧报告不能替代。

## 9. Submit Flow 独立交接要求

Submit 当前仍是独立产品仓库。Mac 虽然能访问内部 Git，但只有已经 commit/push 的内容能够迁移。Windows 上未提交的 Submit 改动必须由 Submit 项目单独整理、密钥扫描、测试和推送；不得通过 AgentOS 仓库夹带。

AgentOS 只保存以下集成合同：MCP Server 标识、工具白名单、Agent/Skill 绑定、内部鉴权参数名和验收规则。OCR、任务状态机、人工复核、Excel 生成与业务数据继续由 Submit 仓库负责。

## 10. 回滚与故障处理

- GitHub 推送不覆盖远端历史；如迁移快照异常，从交接 Tag 或转换前 bundle 创建修复分支。
- Mac 初始化失败时保留 `.env`，停止容器后删除的只能是明确的新建开发数据目录；未经确认不得删除 Git 仓库或其他业务目录。
- 原生 arm64 构建失败时可临时把 API/Mongo 平台改为 `linux/amd64` 使用 Docker 模拟，但必须记录性能差异，且不能把模拟运行当作 M2 原生验收通过。
- Submit 不可达时，智能体不得降级为无工具的普通聊天并伪装成任务已提交；应显示明确不可用状态并保留失败审计。

## 11. 后续版本纪律

1. 每次变更先更新任务书与 Release Record，再生成测试证据。
2. `.env` 永远由模板在目标机生成，密钥通过安全渠道单独配置。
3. 数据库可迁移项必须先变成声明式清单/脚本，禁止直接提交数据库目录。
4. 正式发布需固定 API、MongoDB 和支持服务的多架构 digest。
5. Windows 与 Mac 分别执行 Gate；报告必须包含平台、架构、Git commit、配置哈希和生成时间。
