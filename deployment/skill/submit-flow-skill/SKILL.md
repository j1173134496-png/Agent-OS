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
- The native conversation Attachment Broker stages user-uploaded PDFs and
  supplies a manifest in the run context. Pass only manifest-issued
  `attachment_id` values to `submit_flow.attach_file`. Never invent an ID or
  claim that upload means attachment, OCR, or report generation succeeded.
- This first web release supports `xinan_high_school` (新安高中部) only,
  one site and one reporting month per conversation. Resolve 新安高中 and
  深圳新安中学高中部 to that canonical key; ask rather than guessing for
  any other name. Ask for a new conversation for another site/month.
- Input materials are PDFs, not the example output Excel workbooks.
- If `pricing_required` is returned, report the missing confirmed monthly
  pricing snapshot. Do not invent a price or claim a pricing tool exists.
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
