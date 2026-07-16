#!/usr/bin/env node
// pm-jira — CONTRACT STUB (ADR-0007: implemented on demand).
// Contract ops: health capabilities push-session pull-session push-spec
// get-spec list-specs push-epic push-backlog get-epic list-epics push-plan
// get-plan push-status pull-status push-digest.
// Auth env NAMES (values live in the vault, never in the repo): JIRA_API_TOKEN, JIRA_BASE_URL, JIRA_EMAIL.
// Interactive mode may use the jira MCP server; headless MUST use REST-via-token
// (MCP oauth/stdio is fragile in cron — ADR-0007). Feedback always comes from
// the code forge (gh/glab) via the orch CLI, never from this board.
process.stderr.write('pm-jira: not implemented yet — contract stub (ADR-0007). ' +
  'Implement the ops above or switch state.config.json to none/github-projects/gitlab.\n');
process.exit(64);
