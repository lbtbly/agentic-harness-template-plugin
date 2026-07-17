# SCHEDULED-AGENTS — ready-to-enable recipes

> A template never launches jobs behind your back: nothing is active by default.
> Each recipe = an exact prompt to paste into /schedule (cloud) or a local cron
> running `claude -p`.

## 1. Weekly doc-health (the memory system monitors itself)
- **When:** Monday 09:00.
- **Prompt:** "Run /core:doc-health and drop the full report into
  docs/reports/doc-health-<date>.md. Do not modify anything else."
- **Enable:** `/schedule` → weekly → paste the prompt.
  Or local cron: `0 9 * * 1 cd /path/to/project && claude -p "Run /core:doc-health…" --allowedTools "Read,Glob,Grep,Write(docs/reports/**)"`

## 2. Dependency & CVE watch
- **When:** Friday 09:00.
- **Prompt:** "For each structural lib listed in docs/STACK.md:
  current version vs latest stable, known CVEs (web search). Report
  with recommendations in docs/reports/deps-<date>.md. Do not update anything."

## 3. SUGGESTIONS.md triage
- **When:** on demand, or monthly.
- **Prompt:** "Does docs/SUGGESTIONS.md exceed 20 unchecked entries?
  If so, propose for each: promote to CODEMAP / open an ADR /
  create RUNBOOK-ACCESS / ignore (with reason). Report only, no action."
- **To act on proposals:** use `/core:triage-suggestions` (mutating skill) to accept suggestions
  (→ Backlog) or reject (→ Cancelled); the human-gated lifecycle is enforced.

## Common guardrails
- Always `-p` (one-shot) + tools limited to what's needed.
- Reports go to `docs/reports/` (created on first use); never schedule
  a destructive action.
- `ANTHROPIC_API_KEY`: machine/runner environment, never in the crontab.

## Observability (optional — names only, no infra shipped)
Claude Code exports OpenTelemetry metrics/events natively; the harness never
relies on agents printing their own logs (the nightly run already returns
per-phase token metrics in its summary + digest). To export to your collector,
set these env vars on the runner (values live in your vault/CI, never here):
- `CLAUDE_CODE_ENABLE_TELEMETRY=1`
- `OTEL_METRICS_EXPORTER` / `OTEL_LOGS_EXPORTER` (e.g. `otlp`)
- `OTEL_EXPORTER_OTLP_ENDPOINT` (+ `OTEL_EXPORTER_OTLP_HEADERS` if needed)
