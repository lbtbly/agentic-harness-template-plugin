#!/bin/bash
# Subsystem 5 — packaging: the marketplace + every plugin manifest is valid,
# every listed plugin exists, skills/agents/hooks live where Claude Code looks,
# and no stale template-* namespace leaks into the shipped files.
cd "$(dirname "$0")" || exit 1
PASS=0; FAIL=0
check() { if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); echo "  ok   — $1"; else FAIL=$((FAIL+1)); echo "  FAIL — $1"; fi; }
command -v jq >/dev/null 2>&1 || { echo "  skip — jq not available"; echo "---"; echo "0 ok, 0 failure(s)"; exit 0; }
R=".."
MP="$R/.claude-plugin/marketplace.json"

jq -e . "$MP" >/dev/null 2>&1; check "marketplace.json is valid JSON" $?
jq -e '.name == "harness"' "$MP" >/dev/null 2>&1; check "marketplace is named harness" $?
jq -e '.owner.name | length > 0' "$MP" >/dev/null 2>&1; check "marketplace has an owner" $?
jq -e '.plugins | length >= 4' "$MP" >/dev/null 2>&1; check "marketplace lists the plugins" $?

# every listed plugin dir + manifest exists and parses
miss=0
while IFS=$'\t' read -r name src; do
  d="$R/${src#./}"
  [ -d "$d" ] || { echo "         missing plugin dir: $src"; miss=1; }
  jq -e '.name == "'"$name"'"' "$d/.claude-plugin/plugin.json" >/dev/null 2>&1 || { echo "         bad/missing plugin.json for $name"; miss=1; }
done < <(jq -r '.plugins[] | "\(.name)\t\(.source)"' "$MP")
check "every listed plugin has a dir + matching plugin.json" $miss

# component layout: skills as <name>/SKILL.md, agents as .md with name frontmatter
for p in core orchestrator workbench; do
  bad=0
  for s in "$R/plugins/$p/skills"/*/; do
    [ -d "$s" ] || continue
    [ -f "$s/SKILL.md" ] || { echo "         $s missing SKILL.md"; bad=1; }
  done
  check "plugin $p skills use <name>/SKILL.md layout" $bad
  bad=0
  for a in "$R/plugins/$p/agents"/*.md; do
    [ -e "$a" ] || continue
    grep -q "^name: " "$a" || { echo "         $a missing name frontmatter"; bad=1; }
  done
  check "plugin $p agents carry name frontmatter" $bad
done

# hooks.json parses and only references scripts that exist in the plugin
for p in core formatting; do
  HJ="$R/plugins/$p/hooks/hooks.json"
  jq -e . "$HJ" >/dev/null 2>&1; check "plugin $p hooks.json is valid JSON" $?
  bad=0
  while IFS= read -r cmd; do
    f=$(echo "$cmd" | sed 's|.*CLAUDE_PLUGIN_ROOT}/||; s|"$||')
    [ -f "$R/plugins/$p/$f" ] || { echo "         hooks.json references missing $f"; bad=1; }
  done < <(jq -r '.. | .command? // empty' "$HJ" | grep CLAUDE_PLUGIN_ROOT)
  check "plugin $p hook commands resolve via CLAUDE_PLUGIN_ROOT" $bad
done

# field-test findings (2026-07-16): the scaffolded base must carry BOTH safety
# invariants enable-orchestrator's guard checks, the chosen CI forge must reach
# state.config.json (pull-feedback's source), and CI templates offer the
# subscription auth lane (ADR-0019)
jq -e '.permissions.defaultMode == "plan"' "$R/plugins/core/templates/settings.json" >/dev/null 2>&1; check "settings template: defaultMode plan" $?
jq -e '.disableBypassPermissionsMode == "disable"' "$R/plugins/core/templates/settings.json" >/dev/null 2>&1; check "settings template: disableBypassPermissionsMode present" $?
grep -q 'state.config.json.*forge\|forge.*state.config.json' "$R/plugins/core/skills/new-project/SKILL.md"; check "new-project records the chosen forge in state.config.json" $?
grep -q "CLAUDE_CODE_OAUTH_TOKEN" "$R/plugins/ci/skills/setup/SKILL.md"; check "ci setup skill offers the subscription token lane" $?
grep -q "claude_code_oauth_token" "$R/plugins/ci/templates/github/claude.yml"; check "ci claude.yml supports the subscription token" $?

# the scaffolder skill exists and bakes in the reload gotcha
NP="$R/plugins/core/skills/new-project/SKILL.md"
[ -f "$NP" ]; check "new-project scaffolder exists" $?
grep -q "reload-plugins" "$NP"; check "new-project bakes in /reload-plugins" $?
grep -q "feature-list.schema.json" "$NP"; check "new-project scaffolds the DoD contract" $?
grep -qi "autonomous" "$NP"; check "new-project offers the autonomous profile" $?

# no stale reference namespace leaks into shipped files
if grep -rn "template-core\|template-orchestrator\|template-workbench\|template-marketplace\|template-formatting\|template-ci" \
    "$R/plugins" "$R/.claude-plugin" --include="*.md" --include="*.json" --include="*.sh" --include="*.js" --include="*.yml" -l 2>/dev/null | grep -q .; then
  grep -rn "template-core\|template-orchestrator\|template-marketplace" "$R/plugins" "$R/.claude-plugin" -l 2>/dev/null | sed 's/^/         stale: /'
  check "no stale template-* namespace in shipped files" 1
else
  check "no stale template-* namespace in shipped files" 0
fi

# the morning report template ships with the ordinal-slot contract
DT="$R/plugins/orchestrator/templates/orchestrator/digest-template.html"
[ -f "$DT" ]; check "digest-template.html ships" $?
grep -q "ONE FOLDER PER DAY" "$DT"; check "digest template states the folder-per-day + append contract" $?
grep -q 'class="shots"' "$DT"; check "digest template ships a screenshots gallery" $?
grep -q 'shots/{{EPIC_ID}}' "$DT"; check "screenshots use relative shots/<epic> paths (portable folder)" $?
! grep -qi "4a6cf7\|7d96ff" "$DT"; check "cold blue palette replaced (warm palette)" $?

# runtime templates ship for all three schedulers
for f in github-actions.yml gitlab-ci.yml routines.md; do
  [ -f "$R/plugins/orchestrator/templates/orchestrator/runtime/$f" ]; check "runtime template $f ships" $?
done
# subscription auth is the documented primary lane, and it must never use --bare
# (DEVIATIONS §4: --bare skips OAuth reads entirely)
for f in github-actions.yml gitlab-ci.yml routines.md; do
  grep -q "CLAUDE_CODE_OAUTH_TOKEN" "$R/plugins/orchestrator/templates/orchestrator/runtime/$f"
  check "runtime $f documents the subscription token lane" $?
done
! grep -h -- "--bare" "$R/plugins/orchestrator/templates/orchestrator/runtime/"*.yml "$R/plugins/orchestrator/templates/orchestrator/runtime/"*.sh 2>/dev/null | grep -v "^\s*#" | grep -q .
check "no actual claude invocation uses --bare (comments excepted)" $?

echo "---"; echo "$PASS ok, $FAIL failure(s)"; [ "$FAIL" -eq 0 ]
