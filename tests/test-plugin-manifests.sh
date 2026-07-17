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
jq -e '.permissions.disableBypassPermissionsMode == "disable"' "$R/plugins/core/templates/settings.json" >/dev/null 2>&1; check "settings template: permissions.disableBypassPermissionsMode present (correct path)" $?
jq -e 'has("disableBypassPermissionsMode") | not' "$R/plugins/core/templates/settings.json" >/dev/null 2>&1; check "settings template: no redundant top-level copy" $?
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

# R7 — every hook entry carries an explicit numeric timeout
for hp in core formatting; do
  n_hooks=$(jq '[.hooks[][] | .hooks[]] | length' "$R/plugins/$hp/hooks/hooks.json")
  n_to=$(jq '[.hooks[][] | .hooks[] | select(.timeout | type == "number")] | length' "$R/plugins/$hp/hooks/hooks.json")
  [ "$n_hooks" = "$n_to" ] && [ "$n_hooks" != "0" ]; check "plugin $hp: all $n_hooks hook entries carry numeric timeout" $?
done

# R16 — every agent declares an explicit tools allowlist
bad=0
for a in "$R"/plugins/*/agents/*.md; do
  grep -q "^tools:" "$a" || { echo "         no tools allowlist: $a"; bad=1; }
done
check "every agent declares tools: (least privilege)" $bad

# R9/R10 — manifest enrichment + dependency declaration
for pj in "$R"/plugins/*/.claude-plugin/plugin.json; do
  jq -e '.["$schema"] and .repository and .keywords' "$pj" >/dev/null 2>&1 || { echo "         missing \$schema/repository/keywords: $pj"; bad2=1; }
done
[ -z "${bad2:-}" ]; check "all plugin manifests carry \$schema + repository + keywords" $?
jq -e '[.plugins[] | select(.category and .keywords)] | length == 5' "$MP" >/dev/null 2>&1; check "marketplace entries carry category + keywords" $?
for dep in orchestrator formatting ci workbench; do
  jq -e '.dependencies[0].name == "core"' "$R/plugins/$dep/.claude-plugin/plugin.json" >/dev/null 2>&1 || depmiss=1
done
[ -z "${depmiss:-}" ]; check "dependent plugins declare dependencies on core" $?

# R14 — skill descriptions fit the listing budget; args are hinted
bad3=0
for sk in "$R"/plugins/*/skills/*/SKILL.md; do
  len=$(grep -m1 "^description:" "$sk" | wc -c | tr -d " ")
  [ "$len" -le 205 ] || { echo "         description ${len}c > 200: $sk"; bad3=1; }
done
check "every skill description ≤200 chars (listing budget)" $bad3
grep -q "^argument-hint:" "$R/plugins/orchestrator/skills/run/SKILL.md"; check "run declares argument-hint" $?
grep -q "^argument-hint:" "$R/plugins/core/skills/spec/SKILL.md"; check "spec declares argument-hint" $?

# R15 — read-only skills mechanically read-only + off-context
grep -q "^context: fork" "$R/plugins/core/skills/doc-health/SKILL.md" && grep -q "^agent: Explore" "$R/plugins/core/skills/doc-health/SKILL.md"
check "doc-health runs forked in the read-only Explore agent" $?
grep -q "^context: fork" "$R/plugins/core/skills/codemap/SKILL.md"; check "codemap runs forked (general-purpose keeps Write)" $?

# R19 — duplicated policy-lib must stay byte-identical
cmp -s "$R/plugins/core/hooks/policy-lib.sh" "$R/plugins/formatting/hooks/policy-lib.sh"
check "policy-lib.sh core↔formatting byte-identical (sync test)" $?

# side-effectful skills must not be model-invocable (audit P1-4)
miss=0
for sk in core/skills/new-project core/skills/board-setup core/skills/triage-suggestions \
          orchestrator/skills/enable-orchestrator orchestrator/skills/disable-orchestrator \
          orchestrator/skills/kickoff orchestrator/skills/run ci/skills/setup workbench/skills/db-migration; do
  grep -q "^disable-model-invocation: true" "$R/plugins/$sk/SKILL.md" || { echo "         model-invocable side-effectful skill: $sk"; miss=1; }
done
check "all 9 side-effectful skills carry disable-model-invocation: true" $miss

# re-init must be defined, never clobbering (audit P1-5)
grep -qi "upgrade mode\|adopt/upgrade" "$R/plugins/core/skills/new-project/SKILL.md"; check "new-project defines an upgrade mode for existing scaffolds" $?
grep -qi "never overwrite" "$R/plugins/core/skills/new-project/SKILL.md"; check "upgrade mode never overwrites personalized files" $?

# instruction hygiene (lecture 04): rule metadata convention + audit check
grep -q "expires:" "$R/plugins/core/templates/rules/code-standards.md"; check "rules template documents the since/expires metadata convention" $?
grep -qi "instruction audit" "$R/plugins/core/skills/doc-health/SKILL.md"; check "doc-health runs an instruction audit (stale/contradictory/expired rules)" $?

# observability: OTel documented (names only), never shipped as infra
grep -q "OTEL" "$R/plugins/core/templates/docs/SCHEDULED-AGENTS.md"; check "SCHEDULED-AGENTS documents the OTel env vars (names only)" $?
grep -q "OTEL" "$R/plugins/orchestrator/templates/orchestrator/runtime/github-actions.yml"; check "runtime template points at OTel export (optional)" $?

# Wave-3 safe sub-tasks + R11
grep -q "prompt-interpreted" "$R/plugins/orchestrator/README.md"; check "orchestrator README states workflows are prompt-interpreted specs (D3)" $?
grep -qi "same family\|cross-family" "$R/docs/adr/0016-decorrelated-judge-panel.md"; check "ADR-0016 wording corrected (D2)" $?
grep -qi "@AGENTS.md import bridge\|AGENTS.md fallback" "$R/docs/adr/0022-claude-code-native.md"; check "ADR-0022 carries sharpened revisit triggers (D5)" $?
jq -e . "$R/plugins/orchestrator/templates/orchestrator/models.config.json" >/dev/null 2>&1; check "model ladder externalized to models.config.json (D4)" $?
grep -q "args?.models" "$R/plugins/orchestrator/workflows/nightly-orchestrator.js"; check "nightly reads the model ladder from args (D4)" $?
jq -e '.userConfig.board_token.sensitive == true' "$R/plugins/orchestrator/.claude-plugin/plugin.json" >/dev/null 2>&1; check "userConfig: sensitive board_token (keychain) declared (R11)" $?
grep -q "CLAUDE_PLUGIN_OPTION_BOARD_TOKEN" "$R/plugins/core/skills/board-setup/SKILL.md"; check "board-setup reads the keychain-backed option first (R11)" $?

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
