# V0.1.0 第三方许可证记录

本版本使用官方上游镜像，不修改上游镜像内容。该记录用于追溯来源，不代表 AgentOS 可以将上游组件作为自有代码重新分发。

| 组件 | 来源 | 版本/引用 | 许可证记录 |
|---|---|---|---|
| LibreChat API | `https://github.com/danny-avila/LibreChat` | Tag `v0.8.7`, commit `9e74cc0e57b395926122bd4062c1fcedc48ed465` | 上游仓库 `LICENSE` 为 AGPL-3.0；使用前应保留上游版权与许可证声明 |
| MongoDB Community Server | `https://github.com/docker-library/mongo` | `8.0.20` | 官方镜像与 MongoDB Community Server 许可证/服务端公共许可证说明，以发布时官方声明为准 |
| Meilisearch | `https://github.com/meilisearch/meilisearch` | `v1.35.1` | MIT License |
| pgvector/PostgreSQL | `https://github.com/pgvector/pgvector` | `0.8.0-pg15-trixie` | pgvector 使用 PostgreSQL License；基础 PostgreSQL 镜像按其自身许可证声明执行 |
| LibreChat RAG API | LibreChat 官方镜像仓库 | digest 已记录于 Release Record | 随 LibreChat 上游发布物使用；正式对外分发前需重新核对镜像内许可证清单 |

## 记录要求

- 不把上游镜像改名后当作 AgentOS 自研组件发布。
- V0.1 仅用于公司本机内部验证，正式内网发布前重新核对依赖许可证和镜像 digest。
- 上游升级必须新建 Release Record，记录新的 Tag、Commit、digest 和许可证复核结果。

