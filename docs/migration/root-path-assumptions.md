# Root-path assumption inventory

Checked before Slice B. Entries are catalog-migrated discovery or explicit single-skill/fixture references for Slice C.

| File | Line | Pre-migration assumption |
|---|---:|---|
| `scripts/install-auggie.sh` | 7 | `while IFS=$'\t' read -r name source; do [[ -n "$name" ]] \|\| continue; { printf '%s\n' '---' "name: $name" 'platform: auggie' '---' ''; sed -n '/^---$/,/^---$/d;p' "$SKILLS_DIR/$source/SKILL.md"; } > "$DEST/$name.md"; echo "  ✓ $name"; done <<< "$rows"` |
| `scripts/install-copilot.sh` | 8 | `consolidated() { local out="$target/.github/copilot-instructions.md"; printf '# Copilot Instructions\n\n' > "$out"; while IFS=$'\t' read -r name source; do [[ -n "$name" ]] \|\| continue; printf '## %s\n\n' "$name" >> "$out"; sed -n '/^---$/,/^---$/d;p' "$SKILLS_DIR/$source/SKILL.md" >> "$out"; printf '\n' >> "$out"; done <<< "$rows"; }` |
| `scripts/install-copilot.sh` | 9 | `per_skill() { local out="$target/.github/copilot-instructions"; mkdir -p "$out"; while IFS=$'\t' read -r name source; do [[ -n "$name" ]] \|\| continue; sed -n '/^---$/,/^---$/d;p' "$SKILLS_DIR/$source/SKILL.md" > "$out/$name.md"; done <<< "$rows"; }` |
| `scripts/generate-skill-docs.py` | 21 | `for e in sorted(c['skills'],key=lambda x:x['name']): rows.append(f"\| [`{e['name']}`]({e['source_path']}/SKILL.md) \| `{e['lifecycle']}` \| `{e['owner_phase']}` \|")` |
| `scripts/generate-skill-docs.py` | 25 | `for e in sorted((x for x in c['skills'] if x['owner_phase']==phase),key=lambda x:x['name']): lines.append(f"\| [`{e['name']}`](../{e['source_path']}/SKILL.md) \| {', '.join(e['applies_to_phases'])} \|")` |
| `scripts/install-gemini.sh` | 7 | `while IFS=$'\t' read -r name source; do [[ -n "$name" ]] \|\| continue; { echo "# $name"; echo; sed -n '/^---$/,/^---$/d;p' "$SKILLS_DIR/$source/SKILL.md"; } > "$DEST/$name.md"; echo "  ✓ $name"; done <<< "$rows"` |
| `scripts/validate-cascade-fixtures.py` | 155 | `setup_skill = (ROOT / "setup-skills/SKILL.md").read_text()` |
| `tests/eval_a_skill_test.sh` | 19 | `#   1. eval-a-skill/SKILL.md exists with valid frontmatter (name + description).` |
| `tests/eval_a_skill_test.sh` | 38 | `SKILL_MD="$SKILL_DIR/SKILL.md"` |
| `tests/eval_a_skill_test.sh` | 81 | `ok "eval-a-skill/SKILL.md exists"` |
| `tests/eval_a_skill_test.sh` | 83 | `bad "eval-a-skill/SKILL.md must exist ($SKILL_MD)"` |
| `tests/install_claude_code_test.sh` | 40 | `[[ -f "$d/SKILL.md" ]] && expected=$((expected + 1))` |
| `tests/install_claude_code_test.sh` | 77 | `# Spot-check representative skills resolve to <skill>/SKILL.md.` |
| `tests/install_claude_code_test.sh` | 80 | `[[ -f "$dest/$s/SKILL.md" ]] \|\| { bad "$s/SKILL.md present after install"; miss=$((miss + 1)); }` |
| `tests/install_claude_code_test.sh` | 82 | `[[ "$miss" -eq 0 ]] && ok "representative skills resolve to <skill>/SKILL.md"` |
| `tests/northstar_docs_test.sh` | 9 | `#      (The existing codex_parity_test.sh globs */SKILL.md only and does NOT` |
| `tests/northstar_docs_test.sh` | 25 | `SKILL="northstar/SKILL.md"` |
| `tests/install_cross_host_parity_test.sh` | 23 | `skills = sorted(p.parent.name for p in repo.glob('*/SKILL.md'))` |
| `tests/graph-automation-templates_test.sh` | 426 | `SKILL_MD="$REPO_ROOT/ai-catapult-init/SKILL.md"` |
| `tests/skill-catalog_test.sh` | 16 | `# catalog and is DATA-DRIVEN (derived from the count of top-level */SKILL.md),` |
| `tests/skill-catalog_test.sh` | 20 | `Path('.'): len(glob('*/SKILL.md')),` |
| `tests/ai-catapult-init_rename_test.sh` | 6 | `# (b) init-ai-repo is a deprecated alias pointing to ../ai-catapult-init/SKILL.md` |
| `tests/ai-catapult-init_rename_test.sh` | 7 | `# (c) ai-sdlc-init is a deprecated alias pointing to ../ai-catapult-init/SKILL.md` |
| `tests/ai-catapult-init_rename_test.sh` | 31 | `assert_file_exists  "ai-catapult-init/SKILL.md"              "ai-catapult-init/SKILL.md exists"` |
| `tests/ai-catapult-init_rename_test.sh` | 32 | `assert_file_contains "ai-catapult-init/SKILL.md" "name: ai-catapult-init" "ai-catapult-init canonical frontmatter name"` |
| `tests/ai-catapult-init_rename_test.sh` | 35 | `assert_file_contains "ai-catapult-init/SKILL.md" "init-ai-repo"   "ai-catapult-init description mentions init-ai-repo alias"` |
| `tests/ai-catapult-init_rename_test.sh` | 36 | `assert_file_contains "ai-catapult-init/SKILL.md" "ai-sdlc-init"   "ai-catapult-init description mentions ai-sdlc-init alias"` |
| `tests/ai-catapult-init_rename_test.sh` | 39 | `assert_file_exists  "init-ai-repo/SKILL.md"                   "init-ai-repo/SKILL.md exists (alias)"` |
| `tests/ai-catapult-init_rename_test.sh` | 40 | `assert_file_contains "init-ai-repo/SKILL.md" "name: init-ai-repo" "init-ai-repo alias frontmatter name preserved"` |
| `tests/ai-catapult-init_rename_test.sh` | 41 | `assert_file_contains "init-ai-repo/SKILL.md" "../ai-catapult-init/SKILL.md" "init-ai-repo alias points to ai-catapult-init"` |
| `tests/ai-catapult-init_rename_test.sh` | 42 | `assert_file_contains "init-ai-repo/README.md" "../ai-catapult-init/SKILL.md" "init-ai-repo README points to ai-catapult-init"` |
| `tests/ai-catapult-init_rename_test.sh` | 45 | `assert_file_exists  "ai-sdlc-init/SKILL.md"                   "ai-sdlc-init/SKILL.md exists (alias)"` |
| `tests/ai-catapult-init_rename_test.sh` | 46 | `assert_file_contains "ai-sdlc-init/SKILL.md" "name: ai-sdlc-init" "ai-sdlc-init alias frontmatter name preserved"` |
| `tests/ai-catapult-init_rename_test.sh` | 47 | `assert_file_contains "ai-sdlc-init/SKILL.md" "../ai-catapult-init/SKILL.md" "ai-sdlc-init alias points to ai-catapult-init"` |
| `tests/ai-catapult-init_rename_test.sh` | 48 | `assert_file_contains "ai-sdlc-init/README.md" "../ai-catapult-init/SKILL.md" "ai-sdlc-init README points to ai-catapult-init"` |
| `tests/ai-catapult-init_rename_test.sh` | 51 | `if grep -Fq "name: init-ai-repo" "ai-catapult-init/SKILL.md" 2>/dev/null; then` |
| `tests/ai-catapult-init_rename_test.sh` | 52 | `bad "ai-catapult-init/SKILL.md must not have name: init-ai-repo (it is the new canonical)"` |
| `tests/ai-catapult-init_rename_test.sh` | 54 | `ok "ai-catapult-init/SKILL.md does not have stale name: init-ai-repo"` |
| `tests/agents_index_test.sh` | 6 | `# */SKILL.md) is present in the AGENTS.md `## Skills` table, so the table is a` |
| `tests/agents_index_test.sh` | 41 | `# Full catalog: every top-level */SKILL.md, discovered dynamically so this` |
| `tests/agents_index_test.sh` | 44 | `for body in */SKILL.md; do` |
| `tests/agents_index_test.sh` | 46 | `catalog+=("${body%/SKILL.md}")` |
| `tests/agents_index_test.sh` | 50 | `bad "catalog has at least one skill (*/SKILL.md)"` |
| `tests/agents_index_test.sh` | 65 | `# */SKILL.md dir, so a stale row for a deleted/renamed skill is caught (no orphans).` |
| `tests/agents_index_test.sh` | 69 | `if [[ -f "$name/SKILL.md" ]]; then` |
| `tests/adr_path_test.sh` | 78 | `grill-with-docs/SKILL.md) return 0 ;;` |
| `tests/adr_path_test.sh` | 79 | `setup-skills/SKILL.md) return 0 ;;` |
| `tests/codex_parity_test.sh` | 6 | `#   - EVERY catalog skill (every top-level */SKILL.md) PASSES` |
| `tests/codex_parity_test.sh` | 30 | `#     The catalog is every top-level */SKILL.md — discovered dynamically so` |
| `tests/codex_parity_test.sh` | 34 | `for body in */SKILL.md; do` |
| `tests/codex_parity_test.sh` | 36 | `catalog+=("${body%/SKILL.md}")` |
| `tests/codex_parity_test.sh` | 40 | `bad "catalog has at least one skill (*/SKILL.md)"` |
| `tests/codex_parity_test.sh` | 46 | `body="$skill/SKILL.md"` |
| `tests/codex_parity_test.sh` | 60 | `if grep -Fq "AskUserQuestion" write-a-skill/SKILL.md \` |
| `tests/codex_parity_test.sh` | 61 | `&& grep -Fq "codex:optional" write-a-skill/SKILL.md; then` |
| `tests/codex_parity_test.sh` | 66 | `if bash "$CHECK" write-a-skill/SKILL.md >/dev/null 2>&1; then` |
| `tests/northstar_autobahn_evals_test.sh` | 124 | `validate_triplet "northstar" "$(eval_key northstar/SKILL.md)"` |
| `tests/northstar_autobahn_evals_test.sh` | 125 | `validate_triplet "autobahn"  "$(eval_key autobahn/SKILL.md)"` |
| `tests/mcp_a2a_test.sh` | 91 | `assert_file_contains "ai-catapult-init/SKILL.md" "modules/mcp-a2a.md" \` |
| `tests/workflow-fixtures_test.sh` | 106 | `skill = Path("ai-catapult-init/SKILL.md").read_text()` |
| `tests/autobahn_docs_test.sh` | 9 | `#      (The existing codex_parity_test.sh globs */SKILL.md only and does NOT` |
| `tests/autobahn_docs_test.sh` | 26 | `SKILL="autobahn/SKILL.md"` |
| `tests/test-skills-validator_test.sh` | 24 | `} > "$dir/SKILL.md"` |
| `tests/test-skills-validator_test.sh` | 71 | `printf '# No frontmatter\n' > "$missing_fm/no-frontmatter/SKILL.md"` |
| `tests/test-skills-validator_test.sh` | 123 | `} > "$catalog_root/too-long/SKILL.md"` |
| `tests/test-skills-validator_test.sh` | 147 | `} > "$catalog_warn/warn-skill/SKILL.md"` |
| `tests/init-ai-repo_docs_test.sh` | 41 | `assert_file_contains ai-catapult-init/SKILL.md "name: ai-catapult-init" "canonical skill frontmatter name"` |
| `tests/init-ai-repo_docs_test.sh` | 44 | `assert_file_contains ai-catapult-init/SKILL.md "init-ai-repo" "canonical skill description mentions init-ai-repo alias"` |
| `tests/init-ai-repo_docs_test.sh` | 45 | `assert_file_contains ai-catapult-init/SKILL.md "ai-sdlc-init" "canonical skill description mentions ai-sdlc-init alias"` |
| `tests/init-ai-repo_docs_test.sh` | 48 | `assert_file_contains ai-sdlc-init/SKILL.md "name: ai-sdlc-init" "legacy shim frontmatter name"` |
| `tests/init-ai-repo_docs_test.sh` | 49 | `assert_file_contains ai-sdlc-init/SKILL.md "../ai-catapult-init/SKILL.md" "legacy shim points to canonical skill"` |
| `tests/init-ai-repo_docs_test.sh` | 50 | `assert_file_contains ai-sdlc-init/README.md "../ai-catapult-init/SKILL.md" "legacy shim README points to canonical skill"` |
| `tests/init-ai-repo_docs_test.sh` | 53 | `assert_file_contains init-ai-repo/SKILL.md "name: init-ai-repo" "init-ai-repo shim frontmatter name"` |
| `tests/init-ai-repo_docs_test.sh` | 54 | `assert_file_contains init-ai-repo/SKILL.md "../ai-catapult-init/SKILL.md" "init-ai-repo shim points to canonical skill"` |
| `tests/init-ai-repo_docs_test.sh` | 55 | `assert_file_contains init-ai-repo/README.md "../ai-catapult-init/SKILL.md" "init-ai-repo shim README points to canonical skill"` |
| `tests/init-ai-repo_docs_test.sh` | 58 | `assert_file_contains README.md "[\`ai-catapult-init\`](ai-catapult-init/SKILL.md)" "README exposes canonical skill name"` |
| `tests/init-ai-repo_docs_test.sh` | 66 | `assert_file_contains ai-catapult-init/SKILL.md "protected \`main\` and PR-only delivery" "skill requires protected main and PR-only delivery"` |
| `tests/init-ai-repo_docs_test.sh` | 67 | `assert_file_contains ai-catapult-init/SKILL.md "provider-specific branch-policy checklist/config artifacts" "skill emits branch-policy checklist/config by default"` |
| `tests/init-ai-repo_docs_test.sh` | 68 | `assert_file_contains ai-catapult-init/SKILL.md "host policy permits it" "skill documents admin self-approval boundary"` |
| `tests/init-ai-repo_docs_test.sh` | 69 | `assert_file_contains ai-catapult-init/SKILL.md "admin approve/admin bypass" "skill documents admin approval lane"` |
| `tests/init-ai-repo_docs_test.sh` | 70 | `assert_file_contains ai-catapult-init/SKILL.md "architect, reviewer, and executor" "skill documents architect/reviewer/executor review loop"` |
| `tests/init-ai-repo_docs_test.sh` | 71 | `assert_file_contains ai-catapult-init/SKILL.md "local CI plus host SCM CI" "skill requires local and host CI green"` |
| `tests/init-ai-repo_docs_test.sh` | 72 | `assert_file_contains ai-catapult-init/SKILL.md "do not merge or auto-merge" "skill gates merge and auto-merge"` |
| `tests/init-ai-repo_docs_test.sh` | 90 | `assert_file_contains ai-catapult-init/SKILL.md "### Phase 1 — Discover & Decide" "skill exposes phase 1"` |
| `tests/init-ai-repo_docs_test.sh` | 91 | `assert_file_contains ai-catapult-init/SKILL.md "### Phase 2 — Govern & Plan" "skill exposes phase 2"` |
| `tests/init-ai-repo_docs_test.sh` | 92 | `assert_file_contains ai-catapult-init/SKILL.md "### Phase 3 — Configure & Generate" "skill exposes phase 3"` |
| `tests/init-ai-repo_docs_test.sh` | 93 | `assert_file_contains ai-catapult-init/SKILL.md "### Phase 4 — Validate & Handoff" "skill exposes phase 4"` |
| `tests/init-ai-repo_docs_test.sh` | 94 | `assert_file_contains ai-catapult-init/SKILL.md "### Internal checkpoints" "skill preserves internal checkpoints"` |
| `tests/init-ai-repo_docs_test.sh` | 95 | `assert_file_contains ai-catapult-init/SKILL.md "1. Detect repo state" "skill preserves checkpoint 1"` |
| `tests/init-ai-repo_docs_test.sh` | 101 | `assert_file_contains ai-catapult-init/SKILL.md '`modules/cascade.md` — read when generating multi-repo cascade plans' 'skill module map names active cascade module after PR 6D'` |
| `tests/init-ai-repo_docs_test.sh` | 119 | `if grep -F "only supported" ai-catapult-init/SKILL.md README.md ai-catapult-init/modules/README.md ai-sdlc-init/SKILL.md ai-sdlc-init/README.md init-ai-repo/SKILL.md init-ai-repo/README.md >/dev/null; then` |
| `tests/init-ai-repo_docs_test.sh` | 125 | `if grep -F "repository path remains" README.md AGENTS.md ai-catapult-init/SKILL.md ai-catapult-init/modules/README.md >/dev/null; then` |
| `tests/tdd_legacy_safety_docs_test.sh` | 18 | `require_in tdd/SKILL.md "legacy-safe"` |
| `tests/tdd_legacy_safety_docs_test.sh` | 19 | `require_in tdd/SKILL.md "under 30%"` |
| `tests/tdd_legacy_safety_docs_test.sh` | 20 | `require_in tdd/SKILL.md "any coverage level"` |
| `tests/traceability-fixtures_test.sh` | 66 | `skill = Path("ai-catapult-init/SKILL.md").read_text()` |
| `README.md` | 5 | `Each skill is a self-contained directory with a `SKILL.md` that tells the agent what to do and when to trigger. Skills follow [progressive disclosure](write-agent-docs/SKILL.md) — lean core instructions, with detail in reference files loaded on demand.` |
| `README.md` | 11 | `\| [`design-an-api-or-interface`](design-an-api-or-interface/SKILL.md) \| Generate 3+ radically different interface designs in parallel, then compare and synthesize — based on Ousterhout's "Design It Twice" \|` |
| `README.md` | 12 | `\| [`improve-codebase-architecture`](improve-codebase-architecture/SKILL.md) \| Explore a codebase for shallow modules, present refactoring candidates, design deep replacements, and file a GitHub RFC \|` |
| `README.md` | 13 | `\| [`tdd`](tdd/SKILL.md) \| Red-green-refactor loop with tracer bullets — one test, one implementation, repeat \|` |
| `README.md` | 14 | `\| [`publish-semver`](publish-semver/SKILL.md) \| Automated semver publishing for 10 ecosystems (npm, PyPI, crates.io, NuGet, Hex, pub.dev, Maven, Gradle, Burrito) via GitHub Actions or Azure DevOps \|` |
| `README.md` | 15 | `\| [`using-git-worktrees`](using-git-worktrees/SKILL.md) \| Create isolated git worktrees with auto-setup, safety verification, and test baseline \|` |
| `README.md` | 16 | `\| [`ubiquitous-language`](ubiquitous-language/SKILL.md) \| Extract a DDD-style glossary from a conversation, flag ambiguities, and save to `UBIQUITOUS_LANGUAGE.md` \|` |
| `README.md` | 17 | `\| [`edit-article`](edit-article/SKILL.md) \| Restructure and tighten prose section by section, max 240 chars per paragraph \|` |
| `README.md` | 18 | `\| [`write-a-skill`](write-a-skill/SKILL.md) \| Create new skills with proper structure and progressive disclosure \|` |
| `README.md` | 19 | `\| [`write-agent-docs`](write-agent-docs/SKILL.md) \| Write and audit agent-facing Markdown using progressive disclosure principles \|` |
| `README.md` | 20 | `\| [`ai-catapult-init`](ai-catapult-init/SKILL.md) \| Canonical AI-ready repo initialization skill; `init-ai-repo` and `ai-sdlc-init` remain deprecated compatibility aliases \|` |
| `README.md` | 77 | `\| [`ai-catapult-init`](ai-catapult-init/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `README.md` | 78 | `\| [`ai-sdlc-init`](ai-sdlc-init/SKILL.md) \| `compatibility` \| `03-configure-generate` \|` |
| `README.md` | 79 | `\| [`autobahn`](autobahn/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `README.md` | 80 | `\| [`design-an-api-or-interface`](design-an-api-or-interface/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `README.md` | 81 | `\| [`diagnose`](diagnose/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `README.md` | 82 | `\| [`edit-article`](edit-article/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `README.md` | 83 | `\| [`eval-a-skill`](eval-a-skill/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `README.md` | 84 | `\| [`grill-me`](grill-me/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `README.md` | 85 | `\| [`grill-with-docs`](grill-with-docs/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `README.md` | 86 | `\| [`handoff`](handoff/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `README.md` | 87 | `\| [`improve-codebase-architecture`](improve-codebase-architecture/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `README.md` | 88 | `\| [`init-ai-repo`](init-ai-repo/SKILL.md) \| `compatibility` \| `03-configure-generate` \|` |
| `README.md` | 89 | `\| [`northstar`](northstar/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `README.md` | 90 | `\| [`prototype`](prototype/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `README.md` | 91 | `\| [`publish-semver`](publish-semver/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `README.md` | 92 | `\| [`setup-skills`](setup-skills/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `README.md` | 93 | `\| [`tdd`](tdd/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `README.md` | 94 | `\| [`to-issues`](to-issues/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `README.md` | 95 | `\| [`to-prd`](to-prd/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `README.md` | 96 | `\| [`triage`](triage/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `README.md` | 97 | `\| [`ubiquitous-language`](ubiquitous-language/SKILL.md) \| `stable` \| `01-discover-decide` \|` |
| `README.md` | 98 | `\| [`using-git-worktrees`](using-git-worktrees/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `README.md` | 99 | `\| [`write-a-skill`](write-a-skill/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `README.md` | 100 | `\| [`write-agent-docs`](write-agent-docs/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `README.md` | 101 | `\| [`zoom-out`](zoom-out/SKILL.md) \| `stable` \| `01-discover-decide` \|` |
| `AGENTS.md` | 68 | `Skill bodies must be tool-agnostic across Claude Code and Codex. Do not hard-depend on Claude/OMC-only invocations (`AskUserQuestion`, `Task(subagent_type=...)`, `Skill(...)`, `subagent_type:`, `TodoWrite`, `mcp__*`); use plain-markdown prose instead. `scripts/check-codex-parity.sh` enforces this and scans real invocations only (mentions inside backticks or fenced code blocks are ignored). When a Claude-only construct is unavoidable, annotate it with the `<!-- codex:optional -->` marker on the construct line (or the line directly above it, with no blank line between) and describe a plain-markdown fallback adjacent to it. See `write-a-skill/SKILL.md` for the convention. The mechanical check is the P0/P1 bar; the P2 **verified** bar — representative skills actually run under Codex — is recorded out-of-band per `docs/learning/codex-verification.md` (never a live Codex run in CI).` |
| `AGENTS.md` | 82 | `See [write-agent-docs/SKILL.md](write-agent-docs/SKILL.md) for full audit and refactor workflow.` |
| `AGENTS.md` | 109 | `[`.agents/skills/karpathy-guidelines/SKILL.md`](.agents/skills/karpathy-guidelines/SKILL.md)` |
| `AGENTS.md` | 145 | `\| [`ai-catapult-init`](ai-catapult-init/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `AGENTS.md` | 146 | `\| [`ai-sdlc-init`](ai-sdlc-init/SKILL.md) \| `compatibility` \| `03-configure-generate` \|` |
| `AGENTS.md` | 147 | `\| [`autobahn`](autobahn/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `AGENTS.md` | 148 | `\| [`design-an-api-or-interface`](design-an-api-or-interface/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `AGENTS.md` | 149 | `\| [`diagnose`](diagnose/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `AGENTS.md` | 150 | `\| [`edit-article`](edit-article/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `AGENTS.md` | 151 | `\| [`eval-a-skill`](eval-a-skill/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `AGENTS.md` | 152 | `\| [`grill-me`](grill-me/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `AGENTS.md` | 153 | `\| [`grill-with-docs`](grill-with-docs/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `AGENTS.md` | 154 | `\| [`handoff`](handoff/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `AGENTS.md` | 155 | `\| [`improve-codebase-architecture`](improve-codebase-architecture/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `AGENTS.md` | 156 | `\| [`init-ai-repo`](init-ai-repo/SKILL.md) \| `compatibility` \| `03-configure-generate` \|` |
| `AGENTS.md` | 157 | `\| [`northstar`](northstar/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `AGENTS.md` | 158 | `\| [`prototype`](prototype/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `AGENTS.md` | 159 | `\| [`publish-semver`](publish-semver/SKILL.md) \| `stable` \| `04-validate-handoff` \|` |
| `AGENTS.md` | 160 | `\| [`setup-skills`](setup-skills/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `AGENTS.md` | 161 | `\| [`tdd`](tdd/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `AGENTS.md` | 162 | `\| [`to-issues`](to-issues/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `AGENTS.md` | 163 | `\| [`to-prd`](to-prd/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `AGENTS.md` | 164 | `\| [`triage`](triage/SKILL.md) \| `stable` \| `02-govern-plan` \|` |
| `AGENTS.md` | 165 | `\| [`ubiquitous-language`](ubiquitous-language/SKILL.md) \| `stable` \| `01-discover-decide` \|` |
| `AGENTS.md` | 166 | `\| [`using-git-worktrees`](using-git-worktrees/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `AGENTS.md` | 167 | `\| [`write-a-skill`](write-a-skill/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `AGENTS.md` | 168 | `\| [`write-agent-docs`](write-agent-docs/SKILL.md) \| `stable` \| `03-configure-generate` \|` |
| `AGENTS.md` | 169 | `\| [`zoom-out`](zoom-out/SKILL.md) \| `stable` \| `01-discover-decide` \|` |
| `docs/specifications/ACTIVE/init-ai-repo-agentic-engineering-end-state.md` | 55 | `- CI **eval-coverage gate**: a shippable capability requires an eval with an explicit rubric, paralleling test-coverage gating. Wired into the PR merge gate in `init-ai-repo/SKILL.md`.` |
