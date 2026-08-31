# 立能派 Agent OS 版本化架构与持续推进任务书

> 文档版本：V0.0.0  
> 文档状态：READY FOR REVIEW  
> 路线范围：V0.0.0—V1.0.0  
> 发布策略：严格版本门禁  
> 估算方式：负责人角色 + 人日区间  
> 最后更新：2026-08-25

---

## 1. 文档用途

本文是立能派 Agent OS 的持续推进和版本验收主文档，用于：

- 明确每个版本必须形成的可见成品。
- 明确每个版本相对于上一版本的架构变化。
- 把版本拆成可以派发、验证和关闭的工程任务。
- 为项目经理、研发、测试、业务和安全提供统一验收依据。
- 防止项目只完成代码却没有形成可部署、可操作、可恢复的产品。

本文不替代产品 PRD。产品价值、功能需求和 V1 总体验收以《立能派 Agent OS 正式产品需求文档》为准。

## 2. 使用方法

### 2.1 版本推进

1. 当前版本进入 SPEC，补齐输入、输出、风险和测试。
2. 所有进入开发的任务必须达到 READY。
3. 完成开发后进入 REVIEW。
4. 自动化、集成、手工和安全验收全部通过后，版本进入 DONE。
5. 只有版本 Gate 为 PASS，下一版本才能进入 READY。

### 2.2 任务状态

~~~text
IDEA
  -> SPEC
  -> READY
  -> IN_PROGRESS
  -> REVIEW
  -> DONE

任意阶段可进入 BLOCKED
~~~

### 2.3 完成定义

任务 DONE 必须同时具备：

- 代码或文档交付物。
- 自动化测试或明确的人工验证步骤。
- 验证结果。
- 未修改范围说明。
- 风险和遗留项。
- 对应版本验收证据引用。

不允许只以“可以运行”“本地试过”或聊天中的口头说明作为完成证据。

## 3. 角色

| 角色代号 | 角色 | 主要职责 |
|---|---|---|
| PM | 产品/项目负责人 | 范围、优先级、验收和版本决策 |
| ARCH | 架构负责人 | 技术基线、合同、边界和 ADR |
| PLAT | 平台后端 | LibreChat、账号、会话、插件门禁、文件和审计 |
| FE | 前端 | 品牌化、插件选择、任务卡片和复核体验 |
| INT | 业务集成 | MCP Adapter、Submit Flow 和 EMS 接入 |
| QA | 测试 | 测试设计、自动化、回归和验收证据 |
| OPS | 运维 | Docker、网络、证书、备份、监控和回滚 |
| SEC | 安全 | 权限、密钥、SSRF、Prompt Injection 和审计 |
| BIZ | 业务负责人 | 业务样例、业务结果和人工复核验收 |

同一个人可以承担多个角色，但验收记录仍需标明以哪个角色确认。

## 4. 项目边界

~~~text
K:\Workers\AgentOS
  公司 Agent 平台、公司 UI、平台配置、MCP Adapter、测试和文档

K:\Workers\Submit_Flow_Agent
  现有业务后端；保持独立；AgentOS 通过 Task Service 合同调用

K:\Workers\EMS_Date
  现有业务后端；保持独立；AgentOS V1 仅调用只读命令
~~~

禁止：

- 把业务核心代码复制进 AgentOS。
- 让 LLM 绕过 Adapter 直接调用 CLI。
- 让业务后端依赖 LibreChat 内部对象。
- 让聊天历史代替 task.json、Preview 或业务审计产物。

## 5. 版本编号

| 形式 | 含义 |
|---|---|
| V0.0.0 | 需求和架构基线，没有运行软件 |
| V0.N.0 | 能力里程碑，必须可演示和验收 |
| V0.N.P | 缺陷、安全或兼容性修复，不新增范围 |
| V1.0.0 | 公司内网 Web 正式发布 |

每个版本必须创建 Release Record，至少记录：

~~~text
version
baseline_commit
upstream_version
container_digests
config_hash
release_date
included_tasks
test_summary
known_issues
rollback_target
approvers
~~~

## 6. 总体目标架构

~~~mermaid
flowchart TB
    U[员工浏览器]
    A[管理员浏览器]

    subgraph Edge[接入层]
        Caddy[Caddy 内网 HTTPS]
    end

    subgraph LibreChat[AgentOS Web 平台]
        UI[品牌化聊天 UI]
        Runtime[Agent Runtime]
        Cap[会话能力门禁]
        FileBroker[安全文件 Broker]
        ArtifactBroker[结果文件 Broker]
        Catalog[插件目录]
        Auth[账号、角色与权限]
        Audit[AgentOS 审计关联]
    end

    subgraph DockerData[平台数据]
        Mongo[(MongoDB)]
        Uploads[(上传文件)]
        Logs[(平台日志)]
    end

    subgraph Model[模型边界]
        Relay[公司中转 API]
        LLM[LLM]
    end

    subgraph WindowsAdapters[Windows Host MCP]
        SubmitMCP[Submit Flow MCP :8121]
        EmsMCP[EMS Preview MCP :8122]
    end

    subgraph Business[业务真相来源]
        Submit[Submit Task Service]
        EMS[EMS CLI / Preview]
        Outputs[(业务产物与审计)]
    end

    U --> Caddy
    A --> Caddy
    Caddy --> UI
    UI <--> Runtime
    Runtime <--> Cap
    Cap <--> Catalog
    UI <--> FileBroker
    UI <--> ArtifactBroker
    Auth --> UI
    Runtime <--> Relay
    Relay <--> LLM
    Runtime --> SubmitMCP
    Runtime --> EmsMCP
    SubmitMCP --> Submit
    EmsMCP --> EMS
    Submit --> Outputs
    EMS --> Outputs
    Outputs --> ArtifactBroker
    UI --> Mongo
    FileBroker --> Uploads
    Audit --> Mongo
    UI --> Logs
~~~

## 7. 固定架构决策

### ADR-001 LibreChat 为员工端底座

- 基线使用 V0.8.7 稳定版。
- 锁定 Tag、Commit 和镜像 Digest。
- 公司修改保留独立变更记录，禁止长期直接追踪 main 或 latest。

### ADR-002 Docker + Windows Host Adapter

- LibreChat、MongoDB 和官方依赖运行在 Docker Desktop Linux 容器。
- Submit Flow 与 EMS Adapter 运行在 Windows 主机。
- 原因：EMS 旧版 xls 解析依赖 Windows Excel COM。

### ADR-003 私网 MCP

- Submit Flow 使用 streamable HTTP MCP，端口 8121。
- EMS Preview 使用 streamable HTTP MCP，端口 8122。
- LibreChat 只在 mcpSettings.allowedAddresses 精确放行：

~~~yaml
mcpSettings:
  allowedAddresses:
    - host.docker.internal:8121
    - host.docker.internal:8122
~~~

- Windows 防火墙只允许本机与 Docker Desktop 虚拟网络访问。
- Adapter 还必须验证内部服务令牌，网络放行不能代替应用鉴权。

### ADR-004 MCP + Skill 为稳定插件合同

- Skill 负责识别意图、收集输入、编排和解释。
- MCP Tool 负责结构化调用。
- AgentOS 插件元数据负责名称、图标、角色、风险和能力组合。
- 不把 LibreChat 实验性 Agent Plugins 当作唯一分发和兼容边界。

### ADR-005 服务端能力门禁

- 插件选择属于 user_id + conversation_id。
- 未选择或无权限时，不发送工具 Schema。
- MCP Adapter 仍需独立校验调用者、插件、操作和参数。

### ADR-006 文件和产物 Broker

- LLM 工具参数只携带 attachment_id、artifact_id 等不透明 ID。
- AgentOS File Broker 校验用户和会话归属后向 Adapter 提供受控文件。
- Adapter 不接受用户提交的绝对路径。
- Artifact Broker 校验用户与业务任务关系后提供下载。

### ADR-007 V1 管理能力

- V1 复用并封装 LibreChat 账号、角色、权限和配置能力。
- 不复制或重新分发未获授权的可选管理面板代码。
- 独立公司控制中心进入 V1.x 后续路线。

## 8. 平台公共合同

### 8.1 AgentOS 插件元数据

~~~json
{
  "id": "submit-flow",
  "name": "智能填报",
  "version": "0.1.0",
  "description": "收集业务文件、校验数据并生成填报结果",
  "icon": "submit-flow",
  "skillIds": ["submit-flow"],
  "mcpServerIds": ["submit-flow-mcp"],
  "riskLevel": "controlled-write-local",
  "allowedRoles": ["employee", "admin"],
  "confirmationPolicy": "business-review",
  "enabled": true
}
~~~

禁止未知顶层字段；插件 ID 和 MCP Server ID 全局唯一。

### 8.2 隐藏调用上下文

平台向 Adapter 注入，LLM 不得生成或修改：

~~~text
user_id
conversation_id
request_id
selected_plugin_id
role_claims
service_auth
~~~

### 8.3 统一工具结果

~~~json
{
  "request_id": "req_xxx",
  "plugin_id": "submit-flow",
  "operation": "run_task",
  "status": "completed",
  "summary": "校验通过，已生成结果文件。",
  "task_id": "task_xxx",
  "run_id": null,
  "next_action": null,
  "review": null,
  "artifacts": [
    {
      "artifact_id": "artifact_xxx",
      "name": "result.xlsx",
      "media_type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    }
  ],
  "error": null,
  "audit_ref": "audit_xxx"
}
~~~

### 8.4 标准错误

| 错误码 | 含义 | 用户处理 |
|---|---|---|
| AUTH_REQUIRED | 登录或服务鉴权失败 | 重新登录或联系管理员 |
| PLUGIN_NOT_SELECTED | 当前会话未启用插件 | 添加插件 |
| PLUGIN_FORBIDDEN | 当前角色无插件权限 | 联系管理员 |
| INVALID_ARGUMENT | 参数不符合 Schema | 修正输入 |
| FILE_NOT_ACCESSIBLE | 附件不存在或无权访问 | 重新上传 |
| BUSINESS_BLOCKED | 业务门禁阻断 | 按摘要补充或复核 |
| BUSINESS_FAILED | 业务执行失败 | 查看 audit_ref |
| ADAPTER_UNAVAILABLE | Adapter 不可用 | 稍后重试或联系技术人员 |
| MODEL_INCOMPATIBLE | 模型缺少必要能力 | 切换已支持模型 |
| TIMEOUT | 请求超时 | 查询任务状态，不盲目重建任务 |

## 9. 总路线与依赖

~~~mermaid
flowchart LR
    V000[V0.0.0 文档基线]
    V010[V0.1.0 本机基础]
    V020[V0.2.0 对话]
    V030[V0.3.0 插件框架]
    V040[V0.4.0 Submit Flow]
    V050[V0.5.0 EMS Preview]
    V060[V0.6.0 本机 MVP]
    V070[V0.7.0 内网试点]
    V080[V0.8.0 管理权限]
    V090[V0.9.0 RC]
    V100[V1.0.0 正式版]

    V000 --> V010 --> V020 --> V030 --> V040 --> V050 --> V060 --> V070 --> V080 --> V090 --> V100
~~~

| 版本 | 名称 | 人日 |
|---|---|---:|
| V0.0.0 | 文档与立项基线 | 2–4 |
| V0.1.0 | LibreChat 本机基础版 | 2–4 |
| V0.2.0 | 公司品牌化智能对话版 | 3–6 |
| V0.3.0 | 公司插件基础框架 | 6–10 |
| V0.4.0 | Submit Flow 完整闭环 | 10–16 |
| V0.5.0 | EMS 只读 Preview | 6–10 |
| V0.6.0 | 本机集成演示 MVP | 5–8 |
| V0.7.0 | 内网试点版 | 6–10 |
| V0.8.0 | 管理与权限版 | 7–12 |
| V0.9.0 | Release Candidate | 7–12 |
| V1.0.0 | 内网 Web 正式版 | 3–6 |
| 合计 | 含文档、开发、测试与运维 | 57–98 |

---

# 10. V0.0.0 文档与立项基线

## 10.1 用户看到的结果

没有运行软件。项目形成可评审、可派发、可验收的正式基线。

## 10.2 架构状态

~~~mermaid
flowchart LR
    Ideas[初始想法与讨论稿]
    Repos[EMS 与 Submit 现状]
    Research[开源底座核查]
    PRD[正式 PRD]
    Taskbook[版本架构与任务书]

    Ideas --> PRD
    Repos --> PRD
    Research --> PRD
    PRD --> Taskbook
~~~

## 10.3 范围

- 固化产品目标和非目标。
- 固化 LibreChat 首选和 V1 范围。
- 固化版本路线、任务状态和门禁。
- 固化两个业务接入边界。
- 记录待提供输入。

## 10.4 任务

| 任务 | 负责人 | 人日 | 交付 |
|---|---|---:|---|
| AOS-000-01 正式 PRD | PM、ARCH | 1–2 | PRD 文档 |
| AOS-000-02 版本架构任务书 | ARCH、PM | 1–2 | 本文档 |
| AOS-000-03 文档一致性复核 | QA、BIZ | 0.5–1 | 评审意见与修订 |

## 10.5 验收门禁

- 产品目标、V1 范围和非目标无冲突。
- V0.1.0—V1.0.0 均有明确成品和退出条件。
- Submit Flow 与 EMS 边界得到业务负责人确认。
- 目标目录和文档索引有效。

---

# 11. V0.1.0 LibreChat 本机基础版

## 11.1 成品效果

用户访问 localhost:3080，能够看到 LibreChat 登录页，创建本机管理员账号，进入聊天界面。此版本不要求真实模型和业务插件可用。

## 11.2 架构

~~~mermaid
flowchart LR
    Browser[本机浏览器] --> API[LibreChat V0.8.7 :3080]
    API --> Mongo[(MongoDB)]
    API --> Uploads[(本地上传目录)]
    API --> Logs[(本地日志目录)]
~~~

## 11.3 实施内容

- 创建 AgentOS Git 仓库。
- 记录上游仓库、许可证、Tag、Commit 和镜像 Digest。
- 创建公司 override 配置，不直接修改上游默认 Compose。
- 固定 3080 为 Web 端口；3000 已被其他进程占用，不使用。
- 配置 MongoDB 持久卷、上传目录和日志目录。
- 建立 .env.example 和密钥忽略规则。
- 建立启动、停止、状态和日志读取说明。

## 11.4 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付与验收 |
|---|---|---:|---|---|
| AOS-010-01 初始化仓库 | PLAT | 0.5 | V0.0.0 | 目录、Git、基础忽略规则 |
| AOS-010-02 锁定 LibreChat | ARCH、PLAT | 0.5 | 010-01 | Tag、Commit、Digest、许可证记录 |
| AOS-010-03 Docker 配置 | OPS、PLAT | 1–2 | 010-02 | Compose override、持久卷、端口 |
| AOS-010-04 健康检查 | PLAT、QA | 0.5–1 | 010-03 | Web、Mongo、容器状态检查 |
| AOS-010-05 运维最小手册 | OPS | 0.5 | 010-03 | 启停、日志、常见错误 |

## 11.5 测试

- 首次启动。
- 首个管理员注册。
- 登录与退出。
- 创建一条无模型会话。
- Docker 重启。
- Windows 重启后恢复。
- 仓库秘密扫描。

## 11.6 Gate 0.1

- localhost:3080 可访问。
- 服务重启后账号与会话仍存在。
- 没有使用 latest 镜像。
- 没有明文密钥进入 Git。
- 所有容器版本可以从 Release Record 追溯。

---

# 12. V0.2.0 公司品牌化智能对话版

## 12.1 成品效果

用户看到公司品牌工作台，能够选择已配置模型，进行连续多轮和流式对话。

## 12.2 架构

~~~mermaid
sequenceDiagram
    actor U as 员工
    participant UI as AgentOS Web
    participant LC as LibreChat Server
    participant Relay as 公司中转 API
    participant LLM as 大模型

    U->>UI: 输入消息
    UI->>LC: 会话请求
    LC->>Relay: OpenAI 兼容请求
    Relay->>LLM: 模型调用
    LLM-->>Relay: 流式结果
    Relay-->>LC: 流式结果
    LC-->>UI: 增量消息
    UI-->>U: 展示回答
~~~

## 12.3 实施内容

- 配置 APP_TITLE、Logo、Favicon、欢迎语和中文默认界面。
- 服务端配置中转 API Base URL、API Key 和模型 ID。
- 禁止员工输入自定义 API Key 和 Base URL。
- 建立 API 兼容性探针。
- 验证 Chat Completions 或 Responses 协议。
- 验证流式输出。
- 验证 Tool/Function Calling。
- 验证 JSON Schema 参数。
- 建立模型能力矩阵。

## 12.4 兼容性门禁

| 能力 | 必须 | 不满足时 |
|---|---|---|
| 基础多轮对话 | 是 | 阻止 V0.2.0 |
| 流式输出 | 是 | 阻止 V0.2.0 |
| Tool Calling | 是，进入 V0.4.0 前 | 阻止业务插件 |
| JSON Schema | 是，进入 V0.4.0 前 | 阻止业务插件 |
| 文件原生输入 | 否 | 使用平台文件 Broker |
| 图像理解 | 否 | 不进入 V1 必验 |

## 12.5 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-020-01 品牌资源配置 | FE、PM | 1–2 | V0.1.0 | 公司外壳 |
| AOS-020-02 中转 API 配置 | PLAT | 0.5–1 | 用户提供 API | 服务端自定义端点 |
| AOS-020-03 能力探针 | PLAT、QA | 1–2 | 020-02 | 兼容性报告 |
| AOS-020-04 对话回归 | QA | 0.5–1 | 020-03 | 20 轮测试 |
| AOS-020-05 密钥和日志复核 | SEC | 0.5 | 020-02 | 脱敏验证 |

## 12.6 Gate 0.2

- 公司品牌不再显示 LibreChat 默认用户品牌。
- 20 轮连续对话通过。
- 流式中断有明确状态。
- 服务端日志和浏览器中没有完整 API Key。
- Tool Calling 和 JSON Schema 结果形成证据；若不通过，V0.4.0 保持 BLOCKED。

---

# 13. V0.3.0 公司插件基础框架

## 13.1 成品效果

聊天输入区出现公司插件按钮。用户可以查看授权插件、添加到当前会话、看到已选标签并移除。演示插件能够返回结构化结果。

## 13.2 架构

~~~mermaid
flowchart LR
    User[员工]
    Picker[插件选择器]
    Catalog[部署插件目录]
    Selection[(会话插件选择)]
    Gate[Capability Gate]
    Agent[Agent Runtime]
    Demo[Demo MCP]

    User --> Picker
    Picker --> Catalog
    Picker --> Selection
    Selection --> Gate
    Catalog --> Gate
    Gate --> Agent
    Agent --> Demo
~~~

## 13.3 插件加载规则

1. Catalog 返回当前用户有权使用的插件。
2. 用户选择插件后保存 user_id + conversation_id + plugin_id。
3. 新一轮请求加载该插件 Skill。
4. 新一轮请求只发送该插件允许的 MCP Tool Schema。
5. 服务端和 Adapter 同时校验选择状态。
6. 移除插件后，下一轮请求不再发送工具。

## 13.4 存储

初期使用部署配置作为插件目录真相，MongoDB 保存：

~~~text
conversation_id
user_id
selected_plugin_ids
updated_at
~~~

V0.8.0 再增加角色授权管理，不在 V0.3.0 建设完整插件后台。

## 13.5 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-030-01 插件 Manifest Schema | ARCH、PLAT | 1–2 | V0.2.0 | Schema 与示例 |
| AOS-030-02 插件目录加载 | PLAT | 1–2 | 030-01 | 服务端 Catalog |
| AOS-030-03 会话选择存储 | PLAT | 1–2 | 030-01 | Conversation capability |
| AOS-030-04 插件选择 UI | FE | 2–3 | 030-02 | 列表、添加、移除、标签 |
| AOS-030-05 Capability Gate | PLAT | 2–3 | 030-03 | Skill 和工具动态加载 |
| AOS-030-06 Demo MCP | INT | 1 | 030-01 | 无副作用演示工具 |
| AOS-030-07 门禁安全测试 | QA、SEC | 1–2 | 030-05、06 | 越权和注入测试 |

## 13.6 测试

- 未选择插件，模型请求工具数为 0。
- 选择 Demo 插件，只出现 Demo 工具。
- 移除后工具消失。
- 新会话默认无业务插件。
- A 会话选择不影响 B 会话。
- A 用户选择不影响 B 用户。
- 伪造直接调用被拒绝。
- 无权限插件不出现在 Catalog。

## 13.7 Gate 0.3

- 插件选择和实际工具暴露完全一致。
- 服务端拒绝所有前端绕过。
- Demo Tool 有 request_id、结构化结果和审计事件。
- 无 Shell、任意路径和自由命令能力。

---

# 14. V0.4.0 Submit Flow 完整闭环

## 14.1 成品效果

员工在会话添加“智能填报”，上传业务文件，用自然语言说明站点和月份。系统能够收集缺失信息、创建任务、执行、展示人工复核并返回 Excel 和报告。

## 14.2 架构

~~~mermaid
flowchart TB
    UI[AgentOS 会话]
    Gate[Submit Flow Capability Gate]
    FileBroker[安全文件 Broker]
    MCP[Submit Flow MCP :8121]
    Link[(用户-会话-任务关联)]
    TaskService[Submit Task Service]
    Worker[白名单 Worker]
    Engine[Business Engine]
    Outputs[(task.json / review / Excel / audit)]
    ArtifactBroker[Artifact Broker]

    UI --> Gate
    UI --> FileBroker
    Gate --> MCP
    FileBroker --> MCP
    MCP --> Link
    MCP --> TaskService
    TaskService --> Worker
    Worker --> Engine
    Engine --> Outputs
    Outputs --> MCP
    MCP --> ArtifactBroker
    ArtifactBroker --> UI
~~~

## 14.3 工具与状态

工具：

~~~text
submit_flow.create_task
submit_flow.run_task
submit_flow.get_task
submit_flow.get_review
submit_flow.confirm_task
submit_flow.list_outputs
~~~

状态映射：

| 业务状态 | 平台状态 | UI |
|---|---|---|
| collecting_files | blocked | 提示继续上传 |
| ready_to_run | running-ready | 显示可运行 |
| running | running | 进度卡 |
| need_review | need_review | 复核卡 |
| confirmed | running | 正在重新运行 |
| completed | completed | 结果卡 |
| failed | failed | 错误与 audit_ref |

## 14.4 文件流程

1. LibreChat 保存上传文件。
2. 工具只传 attachment_id。
3. File Broker 校验 user_id、conversation_id、文件类型和大小。
4. File Broker 向 MCP Adapter 提供受控文件流或临时只读文件。
5. Adapter 调用 Task Service add_file。
6. 业务后端管理自己的 inputs 和 outputs。
7. Artifact Broker 只向任务所属用户提供结果。

## 14.5 人工复核

- review_report.json 是复核真相。
- 复核卡展示字段、问题、当前值和证据。
- 用户提交 field_confirmations，不提交任意 JSON 文件路径。
- Adapter 生成受控 confirmed_data.json。
- confirm_task 后重新读取 task.json。

## 14.6 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-040-01 Submit MCP 合同 | ARCH、INT | 1–2 | V0.3.0 | Tool Schema 与结果映射 |
| AOS-040-02 Windows MCP 服务 | INT | 2–3 | 040-01 | :8121 健康与鉴权 |
| AOS-040-03 File Broker | PLAT、INT | 2–3 | 040-01 | 附件安全解析与传输 |
| AOS-040-04 Task Link 存储 | PLAT | 1–2 | 040-01 | 用户、会话、任务关联 |
| AOS-040-05 运行与状态卡 | FE、PLAT | 2–3 | 040-02、04 | 任务状态 UI |
| AOS-040-06 复核卡与确认 | FE、INT | 2–3 | 040-02 | need_review 闭环 |
| AOS-040-07 Artifact Broker | PLAT、INT | 2–3 | 040-04 | 结果安全下载 |
| AOS-040-08 E2E 与安全测试 | QA、SEC、BIZ | 2–4 | 全部 | 成功、复核、失败证据 |

## 14.7 必测场景

- 完整样例直接 completed。
- 低置信度进入 need_review。
- 用户确认后 completed。
- 用户取消复核。
- 缺文件停在 collecting_files。
- 月份冲突。
- 业务校验失败。
- Adapter 超时后查询原 task_id。
- 重复点击不重复创建任务。
- 其他用户不能下载结果。
- 任意路径和额外字段被拒绝。

## 14.8 Gate 0.4

- 三条主路径成功、复核、失败全部通过。
- Task Service 与 audit/events.jsonl 一致。
- 聊天不能伪造 completed。
- Worker 只执行允许动作。
- 结果文件可下载且权限正确。
- 业务核心代码未复制到 AgentOS。

---

# 15. V0.5.0 EMS 只读 Preview

## 15.1 成品效果

员工添加 EMS 插件，选择已配置站区，完成配置校验、源表检查和只读 Preview，查看逐日差异、汇总、阻断项并下载报告。

## 15.2 架构

~~~mermaid
flowchart LR
    UI[AgentOS 会话]
    Gate[EMS Capability Gate]
    MCP[EMS Preview MCP :8122]
    Profiles[服务端 Profile Registry]
    CLI[EMS 确定性 CLI]
    Excel[Windows Excel COM]
    Query[EMS 生产只读 GET]
    Runs[(Preview JSON / CSV / Summary)]
    Broker[Artifact Broker]

    UI --> Gate
    Gate --> MCP
    MCP --> Profiles
    Profiles --> CLI
    CLI --> Excel
    CLI --> Query
    CLI --> Runs
    Runs --> Broker
    Broker --> UI
~~~

## 15.3 工具

~~~text
ems.list_profiles
ems.validate_config
ems.inspect_source
ems.preview
ems.get_artifact
~~~

明确不存在：

~~~text
ems.test
ems.execute
ems.retry
ems.delete
ems.write
~~~

## 15.4 Profile Registry

对外只展示：

~~~text
profile_id
display_name
environment
station_name
date_range
enabled
~~~

Adapter 内部映射 config_path。LLM、浏览器和工具参数均不能提交路径和凭据。

## 15.5 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-050-01 EMS MCP 合同 | ARCH、INT | 1–2 | V0.4.0 | Tool Schema |
| AOS-050-02 Profile Registry | INT、PLAT | 1–2 | 050-01 | 安全配置别名 |
| AOS-050-03 Windows MCP 服务 | INT | 2–3 | 050-01 | :8122 服务 |
| AOS-050-04 Preview 卡片 | FE、PLAT | 1–2 | 050-03 | 汇总、分类、阻断展示 |
| AOS-050-05 报告下载 | PLAT、INT | 1 | 050-03 | Preview 产物 |
| AOS-050-06 只读安全测试 | QA、SEC、BIZ | 2–3 | 全部 | 0 写请求证据 |

## 15.6 必测场景

- 合法 Profile 校验成功。
- Profile 不存在。
- 源文件缺失。
- Excel COM 不可用。
- 查询合同阻断。
- Preview 含 NEEDS_BACKFILL。
- Preview 含 UNKNOWN。
- Preview 不可执行。
- Preview 产物下载。
- 写入意图和伪造工具调用被拒绝。
- Excel 异常后没有残留锁。

## 15.7 Gate 0.5

- 工具清单中不存在写工具。
- Preview 真实写请求数为 0。
- Profile 不暴露 config_path 或 Authorization。
- 原始 xls 未修改。
- 结果数字来自 Preview 产物，不由 LLM 推算替代。

---

# 16. V0.6.0 本机集成演示 MVP

## 16.1 成品效果

一个品牌一致、流程连贯的本机产品：普通对话、Submit Flow 和 EMS Preview 在同一工作台完成。

## 16.2 架构

~~~mermaid
flowchart TD
    Start[新建会话]
    Chat[普通对话]
    Pick{选择插件}
    Submit[Submit Flow 完整闭环]
    EMS[EMS 只读 Preview]
    Cards[统一任务与结果卡]
    Audit[统一 request_id 与审计]

    Start --> Chat
    Chat --> Pick
    Pick -- 智能填报 --> Submit
    Pick -- EMS --> EMS
    Submit --> Cards
    EMS --> Cards
    Cards --> Audit
~~~

## 16.3 实施内容

- 统一插件卡片视觉与状态文案。
- 统一 completed、need_review、blocked 和 failed 表现。
- 统一 request_id、task_id、run_id 和 audit_ref。
- 增加 Adapter 健康状态。
- 增加演示数据准备和重置说明。
- 建立一键本机启动检查。
- 完成从空会话开始的演示脚本。

## 16.4 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-060-01 统一任务卡 | FE | 1–2 | V0.4、0.5 | 一致 UI |
| AOS-060-02 统一审计关联 | PLAT、INT | 1–2 | V0.4、0.5 | 请求关联 |
| AOS-060-03 健康和错误体验 | PLAT、FE | 1–2 | 060-02 | 健康与错误提示 |
| AOS-060-04 演示基线 | QA、BIZ | 1–2 | 全部 | 固定样例、重置说明 |
| AOS-060-05 本机 E2E | QA | 1–2 | 全部 | 完整验收报告 |

## 16.5 Gate 0.6

- 普通对话不加载业务工具。
- 两个插件各自独立选择和运行。
- Submit Flow 完整闭环通过。
- EMS Preview 只读闭环通过。
- 重启后会话、任务关联和结果仍可追踪。
- 形成可以交给非开发人员照做的演示步骤。

---

# 17. V0.7.0 内网试点版

## 17.1 成品效果

3 名试点员工可以从公司局域网使用 HTTPS 地址访问 AgentOS，使用各自账号进行对话和授权插件操作。

## 17.2 架构

~~~mermaid
flowchart LR
    P1[试点电脑 1]
    P2[试点电脑 2]
    P3[试点电脑 3]
    FW[Windows 防火墙允许网段]
    Caddy[Caddy :443 / tls internal]
    AgentOS[LibreChat :3080]
    MCP1[Submit MCP :8121]
    MCP2[EMS MCP :8122]

    P1 --> FW
    P2 --> FW
    P3 --> FW
    FW --> Caddy
    Caddy --> AgentOS
    AgentOS --> MCP1
    AgentOS --> MCP2
~~~

## 17.3 网络策略

- 工作域名默认使用 agentos.internal，正式域名可在进入 READY 前替换。
- 使用 Caddy 内部 CA 证书。
- 试点电脑安装并信任内部根证书。
- 只对允许网段开放 443。
- 3080、8121、8122 不直接对员工网段开放。
- MCP 端口仅允许 Docker Desktop 虚拟网络和本机。
- 关闭自助注册。

## 17.4 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-070-01 内网拓扑与端口 | OPS、SEC | 1–2 | V0.6.0 | 网络方案 |
| AOS-070-02 Caddy HTTPS | OPS | 1–2 | 070-01 | 443 入口 |
| AOS-070-03 防火墙规则 | OPS、SEC | 1 | 070-01 | 最小端口 |
| AOS-070-04 账号与注册策略 | PLAT | 1 | 070-02 | 管理员建号 |
| AOS-070-05 试点终端配置 | OPS | 1–2 | 070-02 | 证书、域名、访问 |
| AOS-070-06 内网安全测试 | QA、SEC | 1–2 | 全部 | 越权与端口测试 |

## 17.5 Gate 0.7

- 3 个独立试点账号登录成功。
- 非允许网段无法访问。
- HTTP 自动转 HTTPS 或不提供 HTTP。
- 员工不能直连 3080、8121、8122。
- 禁用账号无法继续调用模型和插件。
- 证书、域名和终端配置有操作手册。

---

# 18. V0.8.0 管理与权限版

## 18.1 成品效果

管理员可以管理员工账号、角色、可用模型和插件。员工只看到自己被授权的能力，基础调用审计可查询。

## 18.2 架构

~~~mermaid
flowchart TB
    Admin[管理员]
    AdminUI[LibreChat 管理与 AgentOS 配置]
    Users[(用户与角色)]
    Plugins[(插件授权)]
    Models[(模型授权)]
    Audit[(审计事件)]
    Gate[服务端权限门禁]
    Employee[员工请求]

    Admin --> AdminUI
    AdminUI --> Users
    AdminUI --> Plugins
    AdminUI --> Models
    Employee --> Gate
    Users --> Gate
    Plugins --> Gate
    Models --> Gate
    Gate --> Audit
~~~

## 18.3 权限模型

V1 最小角色：

| 能力 | 管理员 | 员工 |
|---|---:|---:|
| 普通对话 | 是 | 是 |
| 使用被授权模型 | 是 | 是 |
| 使用被授权插件 | 是 | 是 |
| 创建/禁用用户 | 是 | 否 |
| 调整角色 | 是 | 否 |
| 调整插件授权 | 是 | 否 |
| 查看系统审计 | 是 | 否 |
| 查看他人业务文件 | 默认否 | 否 |

插件授权以服务端为准。前端隐藏只是体验，不是安全控制。

## 18.4 审计事件

~~~text
login_success
login_failed
user_disabled
conversation_created
plugin_selected
plugin_removed
tool_requested
tool_completed
tool_blocked
review_submitted
artifact_downloaded
permission_changed
~~~

## 18.5 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-080-01 管理能力许可核查 | ARCH、SEC | 1 | V0.7.0 | 许可记录 |
| AOS-080-02 角色模型 | PLAT、PM | 1–2 | 080-01 | 角色与权限矩阵 |
| AOS-080-03 插件授权 | PLAT、FE | 2–3 | 080-02 | 角色到插件 |
| AOS-080-04 模型授权 | PLAT | 1–2 | 080-02 | 角色到模型 |
| AOS-080-05 审计事件 | PLAT、INT | 2–3 | 080-02 | 可查询审计 |
| AOS-080-06 权限安全测试 | QA、SEC | 2–3 | 全部 | 纵向与横向越权测试 |

## 18.6 Gate 0.8

- 管理员和员工角色权限正确。
- 无权限插件不显示且后端拒绝。
- 模型权限在服务端生效。
- 禁用账号生效。
- 审计能够从用户关联到工具、任务和产物。
- 可选管理面板许可已核查，不复制未授权代码。

---

# 19. V0.9.0 Release Candidate

## 19.1 成品效果

功能冻结，进入正式发布前的安全、性能、恢复和用户验收阶段。此版本原则上不再增加业务功能。

## 19.2 运行架构

~~~mermaid
flowchart TB
    Service[AgentOS 运行服务]
    Health[健康检查]
    Metrics[指标与结构化日志]
    Backup[定时备份]
    Restore[隔离恢复环境]
    Release[版本包与配置清单]
    Rollback[上一稳定版本]

    Service --> Health
    Service --> Metrics
    Service --> Backup
    Backup --> Restore
    Service --> Release
    Release --> Rollback
~~~

## 19.3 备份范围

- MongoDB。
- 上传文件。
- AgentOS 配置。
- 插件目录和 Skill。
- AgentOS 审计数据。
- Release Record。

不把现有业务仓库的所有运行数据复制进 AgentOS 备份；业务项目继续按各自策略备份。

## 19.4 监控

- Web 健康。
- MongoDB 健康。
- MCP Adapter 健康。
- 中转 API 成功率和耗时。
- 工具调用成功率和耗时。
- 5xx、超时和权限拒绝。
- 磁盘空间。
- 最近一次备份结果。

## 19.5 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-090-01 功能冻结与缺陷清单 | PM、QA | 1 | V0.8.0 | RC 范围 |
| AOS-090-02 安全审计 | SEC、QA | 2–3 | 090-01 | 安全报告 |
| AOS-090-03 并发与稳定性测试 | QA、OPS | 1–2 | 090-01 | 10 会话基线 |
| AOS-090-04 备份与恢复 | OPS、PLAT | 2–3 | 090-01 | 恢复演练 |
| AOS-090-05 升级与回滚演练 | OPS、ARCH | 1–2 | 090-04 | 回滚证据 |
| AOS-090-06 UAT | PM、BIZ、QA | 2–3 | 全部 | UAT 报告 |
| AOS-090-07 运维与用户手册 | OPS、PM | 1–2 | 全部 | 正式手册 |

## 19.6 安全测试

- 未登录访问。
- 弱口令和会话失效。
- 横向文件访问。
- 插件未选择直接调用。
- 角色越权。
- 路径穿越。
- SSRF。
- Prompt Injection。
- 工具额外字段。
- Adapter 内部令牌错误。
- 密钥和日志泄露。
- EMS 写入意图。

## 19.7 Gate 0.9

- P0/P1 缺陷为 0。
- 10 个并发会话核心流程通过。
- 备份恢复成功。
- 回滚成功。
- UAT 通过。
- 安全报告无未关闭高风险项。
- 运维和员工手册可执行。

---

# 20. V1.0.0 公司内网 Web 正式版

## 20.1 成品效果

公司员工通过内网 HTTPS 地址登录 AgentOS，正常使用大模型对话，并按授权使用智能填报和 EMS Preview。系统具备正式版本、责任人、监控、备份和回滚。

## 20.2 最终架构

~~~mermaid
flowchart LR
    Employees[公司员工]
    HTTPS[内网 HTTPS]
    AgentOS[立能派 Agent OS Web]
    LLM[公司中转 LLM API]
    SubmitPlugin[智能填报插件]
    EMSPlugin[EMS Preview 插件]
    Submit[Submit Flow]
    EMS[EMS Date]
    Admin[管理员与审计]

    Employees --> HTTPS --> AgentOS
    AgentOS <--> LLM
    AgentOS --> SubmitPlugin --> Submit
    AgentOS --> EMSPlugin --> EMS
    Admin --> AgentOS
~~~

## 20.3 发布内容

- V1.0.0 代码标签。
- 上游基线和公司变更清单。
- 固定镜像 Digest。
- 生产配置模板。
- 数据备份。
- 安装升级手册。
- 回滚包。
- 管理员手册。
- 员工手册。
- 测试与 UAT 报告。
- 安全验收报告。
- 已知问题清单。

## 20.4 任务

| 任务 | 负责人 | 人日 | 依赖 | 交付 |
|---|---|---:|---|---|
| AOS-100-01 RC 缺陷关闭 | PLAT、FE、INT、QA | 1–2 | V0.9.0 | 缺陷为 0 |
| AOS-100-02 正式配置冻结 | ARCH、OPS | 0.5–1 | 100-01 | 配置哈希 |
| AOS-100-03 正式发布与验证 | OPS、QA | 1–2 | 100-02 | 发布记录 |
| AOS-100-04 责任与值守交接 | PM、OPS | 0.5–1 | 100-03 | 责任矩阵 |
| AOS-100-05 最终验收签署 | PM、BIZ、SEC | 0.5–1 | 全部 | 验收报告 |

## 20.5 Gate 1.0

- V0.1.0—V0.9.0 Gate 全部 PASS。
- 正式环境版本与 Release Record 一致。
- 普通对话、插件门禁、Submit Flow、EMS Preview、权限和恢复验收通过。
- 无 P0/P1 缺陷。
- 无未接受的高风险安全问题。
- 业务、技术、运维和安全责任人明确。
- 可以在约定时间内回滚到 V0.9.0。

---

# 21. 全局测试矩阵

| 测试域 | 单元 | 合同 | 集成 | E2E | 安全/UAT |
|---|---:|---:|---:|---:|---:|
| 登录与权限 | 是 | 是 | 是 | 是 | 是 |
| 普通对话 | 少量 | 是 | 是 | 是 | UAT |
| 插件目录 | 是 | 是 | 是 | 是 | 是 |
| Capability Gate | 是 | 是 | 是 | 是 | 是 |
| File Broker | 是 | 是 | 是 | 是 | 是 |
| Submit MCP | 是 | 是 | 是 | 是 | 是 |
| EMS MCP | 是 | 是 | 是 | 是 | 是 |
| Artifact Broker | 是 | 是 | 是 | 是 | 是 |
| 审计 | 是 | 是 | 是 | 是 | 是 |
| 备份恢复 | 否 | 否 | 是 | 是 | UAT |

## 22. 全局风险

| 风险 | 影响 | 控制 | 阻断条件 |
|---|---|---|---|
| LibreChat 上游快速变化 | 公司补丁冲突 | 锁版本、变更清单、升级演练 | 未锁 Tag/Digest |
| Agent Plugins 实验性 | 插件包格式变化 | MCP + Skill 为稳定边界 | 核心能力绑定实验 API |
| 中转 API 不支持 Tool Calling | 无法可靠调用业务工具 | V0.2 能力探针 | Tool Calling/Schema 不通过 |
| EMS 依赖 Excel COM | 容器无法直接运行 | Windows Host MCP | Excel COM 不可用或残留锁 |
| LLM 幻觉任务状态 | 用户收到错误结果 | 业务状态真相、结构化卡片 | UI 使用模型文本替代业务状态 |
| 文件越权 | 业务数据泄露 | File/Artifact Broker | 未验证用户与任务归属 |
| Prompt Injection | 越权工具和数据访问 | 能力门禁、Schema、Adapter 再校验 | 仅靠系统提示词防护 |
| 内网端口暴露 | Adapter 被直接调用 | 防火墙、内部令牌、精确端口 | 8121/8122 对员工网段开放 |
| 密钥泄露 | 模型或业务系统失陷 | 服务端密钥、脱敏、扫描 | Key 进入浏览器/Git/日志 |
| 管理面板许可 | 合规风险 | V0.8 前许可核查 | 复制未授权代码 |
| 单机故障 | 服务中断 | 备份、恢复、回滚 | V1 前未完成恢复演练 |

## 23. 变更控制

新增需求必须记录：

~~~text
change_id
requester
business_value
target_version
scope_change
architecture_impact
security_impact
estimate_change
acceptance_change
decision
~~~

以下变更必须另立 PRD 或新版本，不得插入当前版本：

- EMS 写入。
- 公网开放。
- 桌面客户端。
- 独立控制中心。
- 第三个正式业务插件。
- 自动调度。
- 自由代码执行或沙箱。

## 24. 发布豁免

严格门禁下仅允许书面豁免非关键项。豁免必须包含：

- 未通过项目。
- 用户与业务影响。
- 临时控制。
- 责任人。
- 修复版本。
- 截止时间。
- PM、ARCH、QA 和必要的 SEC/BIZ 签字。

以下项目不可豁免：

- 明文密钥泄露。
- 未授权文件访问。
- 未选择插件仍可调用。
- EMS V1 产生写请求。
- Submit Flow 绕过业务校验。
- 无法回滚或无法恢复核心数据。

## 25. V1 后续候选

| 候选版本 | 能力 |
|---|---|
| V1.1.0 | 使用反馈优化、更多试点员工、用量报表 |
| V1.2.0 | Tauri 或 Electron 桌面壳 |
| V1.3.0 | PPT、文案或生图插件 |
| V1.4.0 | SSO、部门与岗位权限 |
| V1.5.0 | 独立公司控制中心 |
| V2.0.0 | 多 Agent、沙箱、长任务和更完整企业 Agent OS |

这些候选不构成当前承诺，需根据 V1 使用数据重新立项。

## 26. 项目当前状态

| 项目 | 状态 |
|---|---|
| V0.0.0 文档 | 用户已完成目标对齐，保留 Gate 评审记录 |
| V0.1.0 实施 | IN PROGRESS |
| 平台代码 | 已创建 V0.1 部署与运维脚本 |
| LibreChat 部署 | 配置完成，待本机启动验证 |
| 中转 API | 待用户提供 |
| Submit Flow 接入 | 未开始 |
| EMS Preview 接入 | 未开始 |
| 现有业务仓库改动 | 无，仍保持独立 |

当前已根据用户明确通知进入 V0.1.0 实施。V0.1.0 只有在本机启动、持久化、重启恢复和手工验收证据完成后，才能将 Gate 标记为 PASS。
