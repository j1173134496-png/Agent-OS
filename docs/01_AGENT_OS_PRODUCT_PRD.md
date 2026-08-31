# 立能派 Agent OS 正式产品需求文档

> 文档版本：V0.0.0  
> 文档状态：READY FOR REVIEW  
> 产品工作名：立能派 Agent OS  
> 软件目标版本：V1.0.0  
> 最后更新：2026-08-25  
> 适用范围：V0.1.0—V1.0.0

---

## 1. 文档目的

本文定义立能派 Agent OS 从本机 Web 原型到公司内网正式版的产品目标、用户体验、功能需求、非功能需求、业务边界和验收标准。

本文是产品需求真相来源。实施顺序、版本架构、任务、人日和发布门禁以《版本化架构与持续推进任务书》为准。

本文不授权：

- 部署或运行平台。
- 修改 EMS_Date 或 Submit_Flow_Agent。
- 调用真实业务写接口。
- 保存、使用或传播任何真实 API Key、Authorization 或账号密码。

## 2. 背景

公司已经存在多个具备实际业务价值的 AI 或自动化项目，例如：

- Submit_Flow_Agent：完成光伏月度填报文件收集、识别、校验、人工复核和 Excel 生成。
- EMS_Date：完成光伏 EMS 历史数据对账、差值计算、Preview、审计和受控补录门禁。
- 后续可能接入 PPT、文案、生图、客服、知识库、代码分析等能力。

目前这些能力分别存在于独立项目、命令行工具或特定交互入口中。员工需要理解项目、路径、命令和运行规则，难以形成统一的公司产品体验。

公司需要一个统一 Agent 工作台：

1. 员工可以像普通大模型产品一样自然对话。
2. LLM 可以理解需求、追问信息、拆解任务并选择下一步。
3. 员工需要业务能力时，在当前会话点击添加公司插件。
4. 插件通过稳定合同调用现有确定性业务后端。
5. 业务进度、人工复核、结果文件和审计证据回到同一个聊天界面。
6. 后续可以持续增加插件，不需要重写平台主体。

## 3. 产品定位

### 3.1 一句话定位

公司内部可持续扩展的企业 Agent 平台：以对话为统一入口，以 LLM 为理解和编排中心，以插件为能力单元，以确定性业务系统为执行边界。

### 3.2 产品不是

- 不是只有固定按钮的传统业务后台。
- 不是把业务命令直接暴露给员工的 CLI 页面。
- 不是让 LLM 自由运行 Shell 的自动化工具。
- 不是重新实现 Submit Flow 或 EMS 的业务规则。
- 不是 V1 就完成所有公司后台、桌面端和岗位插件。

### 3.3 核心价值

| 价值 | 说明 |
|---|---|
| 统一入口 | 员工在一个聊天工作台使用通用对话和公司业务能力 |
| 降低门槛 | 员工不需要学习命令、代码和项目目录 |
| 可扩展 | 新业务通过 Skill、MCP 和 Adapter 接入 |
| 可控制 | 插件、模型、账号和数据权限可管理 |
| 可审计 | 每次工具调用可以关联用户、会话、任务和业务产物 |
| 可复用 | 保持业务后端独立，避免为每个界面重写业务逻辑 |

## 4. 建设目标

### 4.1 V1.0.0 产品目标

交付一套运行在公司内网的品牌化 Web Agent 工作台，至少满足：

- 员工可以使用账号登录。
- 员工可以与公司配置的大模型正常多轮对话。
- 员工可以在当前会话按需添加或移除业务插件。
- 未添加的插件能力不向 LLM 暴露。
- Submit Flow 能够完成文件收集到结果文件的完整闭环。
- EMS 能够完成只读配置校验、源文件检查和 Preview。
- 管理员可以管理基础账号、角色、模型和插件使用权限。
- 系统具备基础审计、备份、恢复、监控和回滚能力。

### 4.2 成功标准

| 编号 | 指标 | V1 验收目标 |
|---|---|---|
| KPI-01 | 普通对话成功率 | 约定测试集中不低于 98% |
| KPI-02 | 插件门禁准确率 | 100%，未选择插件时不可调用 |
| KPI-03 | Submit Flow 闭环成功率 | 固定验收样例 100% |
| KPI-04 | EMS Preview 写请求 | 0 |
| KPI-05 | 高优先级安全缺陷 | 0 |
| KPI-06 | 高优先级未关闭产品缺陷 | 0 |
| KPI-07 | 服务恢复 | 形成并通过一次备份恢复演练 |
| KPI-08 | 试点并发 | 10 个并发会话下核心流程可用 |
| KPI-09 | 审计关联 | 工具调用能够关联用户、会话、请求和业务任务 |

## 5. 范围

### 5.1 V1 包含

- Web 登录和基础账号体系。
- 品牌化中文聊天界面。
- 会话创建、历史记录、多轮对话和流式回答。
- 公司中转 API 与模型配置。
- 附件上传、会话附件引用和结果文件下载。
- 会话级插件选择器。
- Skill 注入、MCP 工具加载和工具权限门禁。
- 工具调用过程、任务状态、人工复核和结果卡片。
- Submit Flow 插件完整闭环。
- EMS Preview 插件只读闭环。
- 基础角色、插件授权、模型授权和管理员配置。
- 审计、日志、备份、恢复、内网 HTTPS 和运维文档。

### 5.2 V1 不包含

- EMS 的 test、execute、retry 或任何写入。
- 对 EMS 生产或 SIT 数据的新增、修改和删除。
- 自由 Shell、任意 Python、任意 SQL 和任意系统命令。
- 允许 LLM 直接传入本机绝对路径或运行目录。
- 独立自研的完整后台控制中心。
- Tauri 或 Electron 桌面客户端。
- 公网部署和匿名访问。
- 多租户商业 SaaS 能力。
- 自动定时任务。
- 多 Agent 并行编排作为必验功能。
- 除 Submit Flow 和 EMS 外的正式业务插件。

## 6. 用户与角色

### 6.1 员工

主要目标：

- 正常咨询、写作、分析和讨论。
- 添加自己被授权的插件。
- 用自然语言发起业务任务。
- 上传业务附件。
- 查看任务进度并完成必要复核。
- 下载结果文件。

### 6.2 管理员

主要目标：

- 创建、禁用和维护员工账号。
- 配置员工角色。
- 控制角色可使用的模型和插件。
- 管理服务端模型配置。
- 查看运行状态和基础审计信息。

### 6.3 AI/技术负责人

主要目标：

- 维护 LibreChat 基线与公司补丁。
- 维护模型中转 API 配置。
- 上架、下架和升级业务插件。
- 处理 Adapter 和业务后端故障。
- 维护备份、恢复和升级策略。

### 6.4 业务负责人

主要目标：

- 确认插件的业务流程与验收样例。
- 复核业务规则、输出内容和异常处理。
- 决定新业务能力是否可以发布。

### 6.5 安全/审计人员

主要目标：

- 核查账号、模型、插件和工具调用记录。
- 确认凭据没有进入客户端、日志和产物。
- 核查危险动作是否被门禁阻止。

## 7. 产品原则

1. **默认是聊天，不默认是执行**。
2. **用户主动添加插件后，Agent 才能使用对应能力**。
3. **LLM 负责理解和编排，不复制业务算法**。
4. **工具只能接收结构化、可验证、最小化的参数**。
5. **业务后端状态优先于聊天记忆**。
6. **高风险动作失败关闭，不能为了完成任务降低门禁**。
7. **所有密钥只存在于服务端**。
8. **所有业务产物必须可以追溯来源和任务**。
9. **新能力通过插件扩展，不在平台核心写岗位专属逻辑**。
10. **每个版本必须能够独立验收和回滚**。

## 8. 总体产品架构

~~~mermaid
flowchart TB
    Employee[公司员工]
    Admin[管理员]

    subgraph EmployeeSurface[员工执行端]
        Web[公司 Agent Web 工作台]
        Chat[普通对话与附件]
        Picker[会话级插件选择器]
        Cards[任务、复核与结果卡片]
    end

    subgraph AgentLayer[Agent 智能层]
        Runtime[LLM Agent Runtime]
        Context[会话上下文]
        Capability[能力门禁]
        Confirm[人工确认]
    end

    subgraph Platform[平台服务]
        ModelEndpoint[公司中转 API]
        Catalog[公司插件目录]
        Audit[账号、权限与审计]
    end

    subgraph Adapters[业务适配层]
        SubmitMCP[Submit Flow MCP Adapter]
        EmsMCP[EMS Preview MCP Adapter]
    end

    subgraph Business[确定性业务层]
        Submit[Submit Flow Task Service]
        EMS[EMS Preview Engine]
        Artifacts[Excel、JSON、报告与审计产物]
    end

    Employee --> Web
    Web --> Chat
    Web --> Picker
    Web --> Cards
    Chat <--> Runtime
    Picker --> Capability
    Catalog --> Capability
    Capability --> Runtime
    Runtime <--> Context
    Runtime <--> Confirm
    Runtime <--> ModelEndpoint
    Runtime --> SubmitMCP
    Runtime --> EmsMCP
    SubmitMCP --> Submit
    EmsMCP --> EMS
    Submit --> Artifacts
    EMS --> Artifacts
    Artifacts --> Cards
    Admin --> Audit
    Audit --> Web
    Audit --> Catalog
~~~

## 9. 信息架构

### 9.1 登录页

- 公司品牌标识。
- 账号与密码登录。
- 不提供公开自助注册。
- 登录错误不暴露账号是否存在。
- 显示必要的内部使用与数据提示。

### 9.2 会话列表

- 新建会话。
- 查看历史会话。
- 修改会话标题。
- 搜索会话。
- 删除会话需要明确确认。
- 展示当前会话是否启用了业务插件。

### 9.3 主聊天区

- 多轮消息。
- 流式生成。
- 停止生成。
- 重新生成。
- 文件上传。
- 插件按钮。
- 当前插件标签。
- 工具活动。
- 任务状态。
- 人工复核。
- 结果文件。

### 9.4 插件选择器

插件项至少展示：

- 图标。
- 名称。
- 一句话描述。
- 风险级别。
- 可执行的主要能力。
- 是否需要人工确认。
- 当前是否已添加。

### 9.5 管理区

V1 复用和封装 LibreChat 已有管理能力，至少包含：

- 用户状态。
- 角色。
- 模型可用性。
- 插件可用性。
- 基础系统配置。
- 审计查询入口。

## 10. 核心用户流程

### 10.1 普通对话

~~~mermaid
sequenceDiagram
    actor U as 员工
    participant W as Web 工作台
    participant A as Agent Runtime
    participant L as 公司中转 API

    U->>W: 输入普通问题
    W->>A: 会话上下文与用户消息
    A->>L: 模型请求
    L-->>A: 流式回答
    A-->>W: 流式消息
    W-->>U: 展示回答
~~~

普通对话不自动加载 Submit Flow 或 EMS 工具。

### 10.2 添加插件

~~~mermaid
sequenceDiagram
    actor U as 员工
    participant W as Web 工作台
    participant C as 插件目录
    participant G as 能力门禁
    participant A as Agent Runtime

    U->>W: 打开插件列表
    W->>C: 查询当前用户可用插件
    C-->>W: 返回授权插件
    U->>W: 添加 Submit Flow
    W->>G: 保存当前会话插件选择
    G->>A: 注入 Skill 与允许的工具 Schema
    A-->>W: 插件已就绪
~~~

移除插件后，新一轮模型调用不得再携带该插件工具 Schema。

### 10.3 Submit Flow 完整闭环

~~~mermaid
flowchart TD
    S[员工添加 Submit Flow] --> D[自然语言描述填报任务]
    D --> Q{信息和文件是否完整}
    Q -- 否 --> ASK[Agent 追问并收集附件]
    ASK --> Q
    Q -- 是 --> CREATE[创建业务任务]
    CREATE --> RUN[运行 Task Service]
    RUN --> STATUS{任务状态}
    STATUS -- completed --> FILES[展示 Excel、JSON 和报告]
    STATUS -- need_review --> REVIEW[展示字段级复核卡片]
    REVIEW --> CONFIRM{用户是否确认}
    CONFIRM -- 修改或确认 --> RERUN[提交结构化确认并重新运行]
    RERUN --> STATUS
    CONFIRM -- 取消 --> CANCEL[停止，不生成最终结果]
    STATUS -- failed --> ERROR[展示安全错误与审计引用]
~~~

### 10.4 EMS 只读 Preview

~~~mermaid
flowchart TD
    S[员工添加 EMS 插件] --> P[选择已注册站区配置]
    P --> V[validate-config]
    V --> I[inspect-source]
    I --> Q{只读查询条件是否可靠}
    Q -- 否 --> B[BLOCKED：展示原因]
    Q -- 是 --> R[preview]
    R --> C[展示逐日差异和汇总]
    C --> F[下载 Preview JSON、CSV 和摘要]
    F --> E[流程结束，不进入写入]
~~~

## 11. 功能需求

### 11.1 账号与访问

#### FR-001 账号登录

- 用户必须登录后才能访问会话、附件、插件和结果。
- 账号由管理员创建或批准。
- 登录状态失效后，任何模型和业务调用必须失败。

验收：

- 正确账号可登录。
- 错误密码、禁用账号和未登录请求均失败。
- 错误信息不泄露内部实现和凭据。

#### FR-002 角色与授权

- V1 至少支持管理员和员工两类角色。
- 插件和模型授权可按角色配置。
- 后端必须再次校验权限，不能只依赖前端隐藏。

#### FR-003 关闭公开注册

- V0.7.0 起关闭公开自助注册。
- 第一个管理员初始化完成后，新增用户只能通过管理员流程。

### 11.2 普通对话

#### FR-010 多轮会话

- 支持新建、继续和查看历史会话。
- 模型能够获得当前会话允许的上下文。
- 不同用户和不同会话不得串联消息。

#### FR-011 流式输出

- 回答应逐步显示。
- 用户可以停止生成。
- 网络中断必须明确显示状态，不得把半截消息标记为完整成功。

#### FR-012 模型配置

- 模型通过公司中转 API 调用。
- Base URL、API Key 和模型 ID 只从服务端配置加载。
- 进入 V0.4.0 前必须验证 Tool Calling 和 JSON Schema。

#### FR-013 会话持久化

- 平台服务重启后，会话和消息仍可读取。
- 临时工具状态与业务任务状态需要明确区分。

### 11.3 文件与产物

#### FR-020 文件上传

- 支持 Submit Flow 所需 PDF 和约定文件类型。
- 文件大小、类型和数量必须校验。
- LLM 和 MCP 工具只接收平台生成的附件 ID，不接收用户提交的任意路径。

#### FR-021 文件访问控制

- 用户只能读取自己有权访问的会话附件和业务产物。
- 下载链接需要鉴权和有效期控制。
- 文件名需要安全化，禁止路径穿越。

#### FR-022 结果展示

- 结果文件在任务卡片中按类型、名称、大小和状态展示。
- 缺失文件或损坏文件不能显示为成功。

### 11.4 插件目录与能力门禁

#### FR-030 插件目录

- 插件必须有稳定 ID、版本、描述、图标、风险级别、Skill 和 MCP Server 映射。
- 只展示当前用户被授权的插件。
- 下架插件后不能在新会话中启用。

#### FR-031 会话级添加

- 插件选择属于当前会话。
- 新建会话默认不继承业务插件。
- 用户可以在发送消息前查看当前启用插件。

#### FR-032 工具隐藏

- 未添加插件时，模型请求不得包含该插件工具定义。
- 直接伪造工具调用请求仍需被服务端拒绝。
- 插件移除后，后续消息不得继续调用其工具。

#### FR-033 Skill 注入

- Skill 只描述任务识别、信息收集、调用顺序和结果解释。
- Skill 不复制 Submit Flow 或 EMS 的计算规则。
- Skill 不包含凭据和真实业务秘密。

#### FR-034 工具确认

- 工具可以声明自动、需要确认或禁止三种策略。
- 人工确认必须关联精确的请求、操作、参数摘要和会话。
- 确认不能跨会话、跨任务或长期复用。

### 11.5 Submit Flow

#### FR-040 创建任务

- Agent 根据自然语言收集站点、月份和附件。
- Adapter 只接受已注册 site_key、合法月份和平台附件 ID。
- 任务创建后返回稳定 task_id。

#### FR-041 运行任务

- 只调用现有 Task Service 或等价受控接口。
- 不允许 Worker 执行自由用户文本。
- 不允许 Agent 直接写 Excel 或跳过校验。

#### FR-042 查询状态

- task.json 是唯一任务状态真相。
- 聊天界面将 collecting_files、ready_to_run、running、need_review、completed 和 failed 映射为清晰状态。

#### FR-043 人工复核

- need_review 时展示字段名、当前值、问题、来源证据和建议。
- 用户只提交允许确认的字段。
- Adapter 校验字段并生成业务后端需要的确认文件。

#### FR-044 结果文件

- completed 时返回业务后端真实输出。
- 至少支持 Excel、recognized_data.json、validation_report.json 和审计引用。
- 文件生成失败时不得把任务显示为 completed。

#### FR-045 幂等与重试

- 重试必须基于 task_id 和业务状态。
- 不允许因为模型重复输出而创建未提示的重复任务。
- 失败重试需要保留原始失败和新请求审计关系。

### 11.6 EMS Preview

#### FR-050 配置选择

- 用户通过 profile_id 选择服务端已注册配置。
- LLM 不得提交配置文件路径、Base URL 或凭据。

#### FR-051 配置校验

- 调用现有 validate-config。
- 清晰展示环境、站区、设备、日期范围和校验结果。
- 输出不得包含 Authorization。

#### FR-052 源文件检查

- 调用现有 inspect-source。
- 旧版 xls 通过 Windows Excel COM 只读解析。
- 解析结束或异常时必须释放工作簿与 Excel 进程。

#### FR-053 Preview

- 调用现有 preview。
- 展示记录数、状态分类、总差异、UNKNOWN 和计划可执行性。
- V1 只用于审查，不向用户展示执行按钮。

#### FR-054 写入硬禁用

- V1 MCP Server 不注册 test、execute、retry。
- Adapter 拒绝任何包含写入动作的请求。
- 测试需要证明真实写请求数为 0。

### 11.7 任务卡片与错误

#### FR-060 任务卡片

- 显示插件、操作、任务 ID、状态、摘要、下一步和产物。
- 卡片状态必须来自工具结果或业务后端，不由 LLM 自行编造。

#### FR-061 复核卡片

- 支持字段级输入、确认和取消。
- 提交前展示最终确认摘要。

#### FR-062 错误展示

- 对用户展示可行动的错误摘要。
- 内部堆栈、路径、凭据和原始敏感响应只进入受控日志。
- 每个错误提供 request_id 或 audit_ref。

### 11.8 管理与审计

#### FR-070 用户管理

- 创建、禁用、恢复用户。
- 禁用用户后已有登录会话应在合理时间内失效。

#### FR-071 插件授权

- 管理员可以控制角色是否可见和可使用某插件。
- 权限变化必须在下一次能力加载时生效。

#### FR-072 模型授权

- 管理员可以控制角色可见模型。
- 员工不能输入自定义 Base URL 或 API Key。

#### FR-073 审计

工具调用至少记录：

- 时间。
- 用户 ID。
- 会话 ID。
- 插件 ID 与版本。
- 操作。
- request_id。
- task_id 或 run_id。
- 状态。
- 耗时。
- 脱敏错误。
- 产物引用。

## 12. 工具合同

### 12.1 Submit Flow 工具

~~~text
submit_flow.create_task
submit_flow.run_task
submit_flow.get_task
submit_flow.get_review
submit_flow.confirm_task
submit_flow.list_outputs
~~~

### 12.2 EMS V1 工具

~~~text
ems.list_profiles
ems.validate_config
ems.inspect_source
ems.preview
ems.get_artifact
~~~

### 12.3 禁止字段

所有业务工具禁止接收：

~~~text
command
cmd
shell
script
python
sql
prompt
user_text
natural_language_instruction
runtime_root
absolute_path
authorization
cookie
password
~~~

### 12.4 统一结果

~~~json
{
  "request_id": "req_xxx",
  "plugin_id": "submit-flow",
  "operation": "run_task",
  "status": "completed",
  "summary": "任务完成",
  "task_id": "task_xxx",
  "run_id": null,
  "next_action": null,
  "review": null,
  "artifacts": [],
  "error": null,
  "audit_ref": "audit_xxx"
}
~~~

状态只允许：

~~~text
completed
need_review
running
blocked
failed
cancelled
~~~

## 13. 数据与真相来源

| 数据 | 真相来源 | 聊天是否可覆盖 |
|---|---|---|
| 用户和角色 | 平台账号数据库 | 否 |
| 会话消息 | LibreChat 会话存储 | 仅按产品操作修改 |
| 插件授权 | 平台权限与插件目录 | 否 |
| Submit 任务状态 | task.json / Task Service | 否 |
| Submit 复核项 | review_report.json | 否 |
| Submit 输出 | Task Service outputs | 否 |
| EMS 配置 | 服务端 profile 映射 | 否 |
| EMS Preview | runs 目录中的真实产物 | 否 |
| 审计状态 | 审计事件存储 | 否 |

LLM 可以解释这些状态，但不能替代或修改真相来源。

## 14. 安全设计

### 14.1 信任边界

~~~mermaid
flowchart LR
    Browser[不可信浏览器输入]
    Web[认证 Web 服务]
    Model[外部模型边界]
    Gate[Schema 与权限门禁]
    MCP[受控 MCP Adapter]
    Business[业务后端]
    Secrets[服务端密钥]

    Browser --> Web
    Web --> Model
    Web --> Gate
    Gate --> MCP
    MCP --> Business
    Secrets --> Web
    Secrets --> MCP
~~~

网页、附件、模型输出和用户自然语言均视为不可信输入。

### 14.2 必须保护

- 模型 API Key。
- EMS Authorization。
- 账号密码和 Session。
- 内部文件路径。
- 业务原始文件。
- Excel 和报告产物。
- 审计日志。

### 14.3 强制控制

- 服务端权限校验。
- JSON Schema 严格校验。
- additionalProperties 关闭或等价白名单。
- 附件 ID 到路径的服务端映射。
- 插件选择与工具加载绑定。
- 私网 MCP 精确 host:port 放行。
- Adapter 内部令牌。
- 日志脱敏。
- 超时、并发限制和熔断。
- 文件类型、大小和路径校验。
- 内网 HTTPS。
- 关闭公开注册。

### 14.4 Prompt Injection

系统必须拒绝模型或附件中的以下诱导：

- 要求忽略平台规则。
- 要求调用未选择插件。
- 要求输出或读取密钥。
- 要求运行 Shell、Python、SQL。
- 要求访问任意路径或 URL。
- 要求绕过人工复核和业务校验。

## 15. 非功能需求

### NFR-001 可靠性

- 业务请求必须有 request_id。
- 长任务超时不能丢失业务 task_id。
- Adapter 故障不能导致平台整体崩溃。
- 重启后可以从业务真相来源恢复状态。

### NFR-002 性能

- 普通对话首个流式内容目标不超过 5 秒，不包含模型自身排队异常。
- 普通页面操作目标 P95 不超过 2 秒。
- V0.9.0 支持 10 个并发试点会话。
- 业务长任务采用进度状态，不要求同步等待完成。

### NFR-003 可维护性

- 上游 LibreChat 版本、Commit 和镜像 Digest 固定。
- 公司修改形成独立补丁和变更记录。
- 平台核心不复制业务算法。
- Adapter 和工具合同具备自动化测试。

### NFR-004 可审计性

- 关键操作能够从用户追踪到业务任务和产物。
- 审计日志不可记录完整密钥。
- 时间统一包含时区。

### NFR-005 可恢复性

- MongoDB、上传文件、配置、插件元数据和审计数据进入备份范围。
- V0.9.0 完成一次从备份恢复到隔离环境的演练。
- 发布前保留上一稳定版本和配置。

### NFR-006 兼容性

- 首期支持公司 Windows 11 员工浏览器。
- 优先支持最新版 Chrome 和 Edge。
- 页面最低宽度按 1280 像素桌面体验验收。

## 16. 可观测性

至少采集：

- Web 服务健康。
- MongoDB 健康。
- MCP Adapter 健康。
- 模型调用成功率和耗时。
- 工具调用成功率和耗时。
- Submit Flow 状态分布。
- EMS Preview 状态分布。
- 5xx、超时和鉴权失败。
- 磁盘空间与备份状态。

V1 不要求建设复杂监控大盘，但必须提供健康检查、结构化日志和可执行排查手册。

## 17. V1 验收场景

### AC-001 普通对话

- 员工登录并完成 20 轮连续对话。
- 对话中未添加插件。
- 请求记录中没有 Submit Flow 或 EMS 工具 Schema。

### AC-002 插件门禁

- 员工添加 Submit Flow 后只出现 Submit Flow 工具。
- 移除后下一轮工具消失。
- 无 EMS 权限的员工看不到 EMS。

### AC-003 Submit Flow 成功路径

- 上传完整样例。
- 创建并运行任务。
- 任务 completed。
- 下载预期 Excel、JSON 和校验报告。

### AC-004 Submit Flow 复核路径

- 使用固定 need_review 样例。
- 展示字段问题和证据。
- 用户提交结构化确认。
- 任务完成并保留确认审计。

### AC-005 Submit Flow 失败路径

- 缺文件、月份冲突或业务校验失败。
- 系统不生成伪造成功结果。
- 用户获得明确下一步和 audit_ref。

### AC-006 EMS Preview

- 选择受控 profile。
- 完成 validate、inspect 和 preview。
- 展示逐日差异与汇总。
- 真实写请求数为 0。

### AC-007 安全

- 任意路径、Shell、Python、SQL 和写入意图全部被拒绝。
- 浏览器、消息、日志和结果中没有完整密钥。

### AC-008 权限

- 管理员和员工权限符合矩阵。
- 禁用账号无法继续使用。
- 未授权插件不能通过直接 API 绕过。

### AC-009 恢复

- 从备份恢复账号、会话、配置和必要文件。
- 业务任务仍以原业务后端状态为准。

### AC-010 内网试点

- 3 个试点账号通过公司内网访问。
- 非允许网段无法访问。
- 10 个并发会话下核心流程可用。

## 18. 发布判定

V1.0.0 必须满足：

- V0.1.0—V0.9.0 关键门禁通过。
- P0、P1 缺陷为 0。
- 安全验收通过。
- UAT 验收通过。
- 备份恢复通过。
- 回滚演练通过。
- 管理员、技术负责人和业务负责人签署验收。
- 员工手册和运维手册可用。

## 19. 后续路线

V1.x 可按实际价值增加：

- Tauri 或 Electron 桌面客户端。
- 独立公司控制中心。
- SSO、LDAP 或企业身份系统。
- 部门、岗位和数据范围的细粒度 RBAC。
- 成本、配额和部门报表。
- PPT、文案、生图、客服和代码插件。
- 更成熟的多 Agent、沙箱和长任务调度。

任何后续 EMS 写入能力必须独立立项，不从 V1 Preview 插件自然继承。

## 20. 已确认决策

| 决策 | 结果 |
|---|---|
| 员工端底座 | LibreChat 首选 |
| 首期形态 | Web |
| 部署起点 | 本机 Windows + Docker Desktop |
| 模型接入 | LibreChat 服务端连接公司中转 API |
| 插件选择 | 当前会话按需添加 |
| 未选择插件 | 不暴露 Skill 和工具 |
| 首批插件 | Submit Flow、EMS Preview |
| Submit Flow | 完整闭环 |
| EMS | V1 只读 Preview |
| V1 后台 | 复用并封装 LibreChat 管理能力 |
| V1 最终形态 | 公司内网 Web 正式版 |
| 版本推进 | 严格门禁 |
| 工期 | 角色 + 人日区间 |

## 21. 待提供输入

| 输入 | 最晚需要版本 | 缺失时处理 |
|---|---|---|
| 中转 API Base URL | V0.2.0 | 阻止模型集成进入 READY |
| API Key | V0.2.0 集成测试 | 仅由用户放入本地私密配置 |
| 模型 ID | V0.2.0 | 阻止实际对话验收 |
| Tool Calling 能力 | V0.2.0 | 不通过则阻止 V0.4.0 |
| 公司正式名称、Logo、主题色 | V0.2.0 | 已接入立能派 Agent OS 品牌资源 |
| 内网网段 | V0.7.0 | 不开放局域网 |
| 试点账号 | V0.7.0 | 只做本机验收 |

## 22. 术语

| 术语 | 含义 |
|---|---|
| Agent Runtime | 负责会话、LLM 调用、工具选择和运行控制的智能体运行层 |
| Skill | 指导 Agent 如何识别和完成某类任务的指令包 |
| MCP | 模型与外部工具之间的结构化协议 |
| Adapter | 把平台工具合同映射到现有业务后端的受控适配层 |
| Capability Gate | 根据用户权限和会话选择决定哪些能力可被模型看到 |
| Task Card | 在聊天中显示业务任务状态、下一步和结果的结构化组件 |
| need_review | Submit Flow 发现需要人工确认字段时的业务状态 |
| Preview | EMS 只读解析、查询、计算和计划生成过程 |
| UAT | 用户验收测试 |
| Release Gate | 版本进入下一阶段前必须满足的验收条件 |

## 23. 参考基线

- LibreChat：https://github.com/danny-avila/LibreChat
- LibreChat Docker：https://www.librechat.ai/docs/local/docker
- LibreChat MCP：https://www.librechat.ai/docs/features/mcp
- DeepSeek Harness：https://github.com/deepseek-ai/deepseek-harness
- DeerFlow：https://github.com/bytedance/deer-flow
- OpenAI Codex 开源组件：https://learn.chatgpt.com/docs/open-source
- EMS 项目：K:\Workers\EMS_Date
- Submit Flow 项目：K:\Workers\Submit_Flow_Agent
