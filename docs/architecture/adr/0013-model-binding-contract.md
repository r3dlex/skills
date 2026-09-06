# ADR 0013: Model binding contract — native aliases vs auditable pins

## Status
Accepted.

## Context
ADR-0003 introduced the portable tier policy (`frontier/mid/cheap`) with host_aliases as illustrative bindings. Real deployments drifted three ways: the template carried codex `o3`-generation bindings while fixtures carried `gpt-5-codex`-generation; the ollama lane (`glm-5.3:cloud`) existed only in the template; and non-tier `fallback_*` keys sat inside `host_aliases.ollama`, invisible to `tests/model_routing_test.sh` because the validator covered fixtures but never the template. Meanwhile the "latest on the fly" property users expect is real only for some hosts: Claude Code's `opus`/`sonnet`/`haiku` are native aliases the host resolves to the current model at runtime, while codex and ollama-cloud model names are concrete IDs that rot the day a provider ships.

## Decision
The model-routing policy carries a two-mechanism binding contract (schema_version 1.1):

1. `host_aliases` keys are strictly tiers (`frontier`/`mid`/`cheap`). Fallback chains live in a top-level `fallbacks` namespace keyed by host — never inside `host_aliases`.
2. Every host declares which mechanism it uses:
   - `alias_supported: true` — the host's model names are native aliases; the runtime resolves the latest available version on the fly (claude: opus/sonnet/haiku). No pin is recorded because there is nothing to go stale.
   - `alias_supported: false` — the host's model names are concrete IDs; the binding carries `pinned_at` (ISO date) so staleness is auditable, plus a `fallbacks` chain where the deployment defines one (ollama: glm-5.3:cloud with free-tier fallbacks).
3. The template is the single source of truth. Fixtures and deployed `.ai/policies/model-routing.json` copies reconcile from it; `tests/model_routing_test.sh` validates the template itself (closing the exemption) and asserts template/fixture contract-shape parity.

## Alternatives
- **Pin concrete IDs everywhere** — rejected: rots immediately and abandons the portability ADR-0003 established.
- **Alias-only, no fallback** — rejected: hosts without native aliasing would silently run stale IDs with no recorded date and no fallback chain.
- **Keep `fallback_*` pseudo-tier keys inside host_aliases** — rejected: they violate the tier-key contract and were invisible precisely because the validator never checked the template.
- **Do nothing (drift is intentional local tuning)** — rejected with evidence: the three-way codex drift straddles two model generations with no recorded rationale; that is rot, not tuning.

## Consequences
- Staleness becomes auditable: any concrete binding must carry `pinned_at`, and refreshing it is a visible, testable diff.
- Downstream copies (ai-catapult vendor lock + dist regen, ai-factory, umbrella root) reconcile from this template; the umbrella gains a comparison drift test.
- Validators elsewhere (ai-catapult init fixtures, umbrella drift test) must track the same contract shape; the shape, not the IDs, is the portable part.