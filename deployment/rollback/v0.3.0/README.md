# AgentOS V0.3.0 Rollback Bundle

This directory contains the retired V0.3.0 overlay and plugin files for rollback only.

The V0.3.1 active deployment does not load these files. Do not add new product
features here and do not mount this directory into the active Compose services.

Rollback target image:

```text
registry.librechat.ai/danny-avila/librechat@sha256:a950bb5fe847ae3b00797bf02d0b26bcd4c12f27240ebad6fa9eedafefc59d52
```

Rollback must preserve MongoDB data, uploads, logs, and audit records. Use the
V0.3.1 rollback report to record an actual switch and restore verification.
