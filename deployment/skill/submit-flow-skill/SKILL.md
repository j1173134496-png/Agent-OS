---
name: submit-flow-skill
description: Use the company Submit Flow Agent to collect monthly filing PDFs, run the controlled task service, handle review, and return authorized artifacts.
---

# Submit Flow Skill

Use the Submit Flow MCP tools only for the user's current authenticated
conversation. The task service and its audit events are the source of truth.

## Rules

- Ask for the site and reporting month when either is missing.
- Do not request or invent a local path, URL, shell command, Python, SQL, or
  arbitrary JSON file path.
- Use the Attachment Broker to stage each PDF, then pass only its
  `attachment_id` to `submit_flow.attach_file`.
- Do not claim a task is complete from tool text. Call
  `submit_flow.get_task` and use its structured status.
- If the task reports `collecting_files`, tell the user which required file
  roles are still missing.
- If the task reports `ready_to_run`, call `submit_flow.run_task` once.
- If the task reports `need_review`, call `submit_flow.get_review`, present the
  listed fields and evidence, and wait for the user to confirm field values.
- Send only field-level values to `submit_flow.confirm_task`; never send a
  path or a replacement task document.
- Return artifacts only from `submit_flow.list_outputs` and retain their
  `artifact_id` values for authorized download.
- Treat `completed`, `need_review`, `failed`, and `pricing_required` as
  explicit business states. Never silently reinterpret them.

## User-facing flow

1. Resolve site and month.
2. Create or resume the bound task.
3. Collect the required PDFs through the platform attachment flow.
4. Attach them by opaque ID and run the task.
5. Show review blockers when present and wait for field confirmations.
6. After completion, list the generated reports and workbooks.
