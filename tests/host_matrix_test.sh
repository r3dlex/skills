#!/usr/bin/env bash
# tswc-sk-e5-h1 host matrix test (plain bash, no embedded interpreter program).
# Asserts the committed host-matrix.json keys and invariants, alias resolution in
# catalog-query (omc -> claude-code, omx -> codex, byte-identical rows and
# projections), the unknown-host refusal for omo-ai, oh-my-openagent and nope, an
# absent matrix (payload hosts unchanged, aliases unknown), the validator's refusal
# of an alias in supported_hosts, and negative matrix fixtures in cleanup-bound
# temporary roots, each refused with a host_matrix_invalid diagnostic.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
PASS=0
FAIL=0
ok() {
	echo "  PASS: $1"
	PASS=$((PASS + 1))
}
bad() {
	echo "  FAIL: $1"
	FAIL=$((FAIL + 1))
}
expect() {
	local label="$1"
	shift
	if "$@"; then
		ok "$label"
	else
		bad "$label"
	fi
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MATRIX="$REPO_ROOT/host-matrix.json"
QUERY=(python3 scripts/catalog-query.py)
PAYLOAD_HOSTS=(auggie claude-code codex copilot gemini opencode)
SKILL_SOURCE="01-discover-decide/research"

# --- committed matrix: keys ---------------------------------------------------
tracked() { git ls-files --error-unmatch host-matrix.json >/dev/null 2>&1; }
expect "host-matrix.json is tracked at the repository root" tracked
compact="$({ tr -d ' \n\t' <"$MATRIX"; } 2>/dev/null || true)"
has() { [[ "$compact" == *"$1"* ]]; }
mentions() { grep -q "$1" "$MATRIX" 2>/dev/null; }
count() { grep -o "$1" "$MATRIX" 2>/dev/null | wc -l | tr -d ' '; }
expect "schema is host-matrix/1" has '"schema":"host-matrix/1"'
expect "exactly five top-level keys (schema, payload_hosts, aliases, consumers, excluded)" test "$(grep -c '^  "[a-z_]*": ' "$MATRIX" 2>/dev/null)" = 5
expect "payload_hosts equal the catalog model HOSTS" has '"payload_hosts":["auggie","claude-code","codex","copilot","gemini","opencode"]'
expect "aliases map omc to claude-code and omx to codex, nothing else" has '"aliases":{"omc":"claude-code","omx":"codex"}'
expect "claude-code consumer names its installer and also omc" has '"claude-code":{"installer":"scripts/install-claude-code.sh","also":["omc"]}'
expect "codex consumer names its installer and also omx" has '"codex":{"installer":"scripts/install-codex.sh","also":["omx"]}'
expect "opencode consumer has installer null and a delivery note" has '"opencode":{"installer":null,"delivery":"'
expect "opencode delivery note names the ai-catapult payload merge" mentions 'ai-catapult payload merge into the OpenCode config root'
expect "opencode delivery note refuses the OpenCode v2 plugin array" mentions 'never the OpenCode v2 plugin array'
for host in auggie copilot gemini; do
	expect "$host consumer names scripts/install-$host.sh" has "\"$host\":{\"installer\":\"scripts/install-$host.sh\"}"
done
expect "excluded names omo-ai" has '"excluded":{"omo-ai":"'
expect "excluded names oh-my-openagent" has '"oh-my-openagent":"'
expect "omo-ai appears only under excluded" test "$(count '"omo-ai"')" = 1
expect "oh-my-openagent appears only under excluded" test "$(count '"oh-my-openagent"')" = 1
no_skill_collision() {
	local name
	for name in "${PAYLOAD_HOSTS[@]}" omc omx omo-ai oh-my-openagent; do
		if grep -q "\"name\": \"$name\"" catalog.json; then
			echo "  catalog skill named $name" >&2
			return 1
		fi
	done
}
expect "no payload host, alias or excluded name equals a catalog skill name" no_skill_collision

# --- alias resolution at the repository root -----------------------------------
# same_output pins the exit status both invocations must produce (0 for a view,
# 2 for a refused --skill) before comparing bytes: equal statuses and equal
# bytes alone would accept a shared runtime failure such as node_unavailable
# 127. A non-empty want_err is the exact stderr the invocation must print.
same_output() {
	local label="$1" alias="$2" host="$3" want="$4" want_err="$5" arc hrc
	shift 5
	"${QUERY[@]}" --host "$alias" "$@" >"$TMP/a.out" 2>"$TMP/a.err"
	arc=$?
	"${QUERY[@]}" --host "$host" "$@" >"$TMP/h.out" 2>"$TMP/h.err"
	hrc=$?
	if [[ "$arc" -ne "$want" || "$hrc" -ne "$want" ]]; then
		bad "$label (exit $arc vs $hrc, wanted $want): $(head -n 1 "$TMP/a.err")"
	elif ! cmp -s "$TMP/a.out" "$TMP/h.out" || ! cmp -s "$TMP/a.err" "$TMP/h.err"; then
		bad "$label (alias and $host output differ at exit $want)"
	elif [[ -n "$want_err" && "$(cat "$TMP/a.err")" != "$want_err" ]]; then
		bad "$label (exit $want, stderr $(head -n 1 "$TMP/a.err"))"
	else
		ok "$label (exit $arc)"
	fi
}
same_projection() {
	local label="$1" alias="$2" host="$3" arc hrc
	shift 3
	rm -f "$TMP/a.json" "$TMP/h.json"
	"${QUERY[@]}" --host "$alias" "$@" --projection "$TMP/a.json" >"$TMP/a.out" 2>"$TMP/a.err"
	arc=$?
	"${QUERY[@]}" --host "$host" "$@" --projection "$TMP/h.json" >"$TMP/h.out" 2>"$TMP/h.err"
	hrc=$?
	if [[ "$arc" -eq 0 && "$hrc" -eq 0 && -s "$TMP/a.json" ]] && cmp -s "$TMP/a.json" "$TMP/h.json" && cmp -s "$TMP/a.out" "$TMP/h.out"; then
		ok "$label"
	else
		bad "$label (exit $arc vs $hrc)"
	fi
}
for pair in "omc claude-code" "omx codex"; do
	read -r alias host <<<"$pair"
	same_output "$alias rows equal $host rows (default view)" "$alias" "$host" 0 ""
	same_output "$alias rows equal $host rows (experimental)" "$alias" "$host" 0 "" --include-lifecycle experimental
	same_output "$alias rows equal $host rows (deprecated)" "$alias" "$host" 0 "" --include-lifecycle deprecated
	same_output "$alias rows equal $host rows (experimental and deprecated)" "$alias" "$host" 0 "" --include-lifecycle experimental --include-lifecycle deprecated
	same_output "$alias --skill research equals $host" "$alias" "$host" 0 "" --skill research
	same_output "$alias --skill nope refuses like $host" "$alias" "$host" 2 "unknown skill for $host: nope" --skill nope
	same_projection "$alias projection bytes equal $host (default view)" "$alias" "$host"
	same_projection "$alias projection bytes equal $host (every lifecycle)" "$alias" "$host" --include-lifecycle experimental --include-lifecycle deprecated
done
alias_rows() {
	"${QUERY[@]}" --host omc >"$TMP/rows.out" 2>/dev/null && [[ -s "$TMP/rows.out" ]]
}
expect "omc default view is non-empty" alias_rows

# --- unknown hosts refuse with the select() diagnostic -------------------------
unknown_host() {
	local name="$1" rc
	"${QUERY[@]}" --host "$name" >"$TMP/u.out" 2>"$TMP/u.err"
	rc=$?
	if [[ "$rc" -eq 2 && ! -s "$TMP/u.out" && "$(cat "$TMP/u.err")" == "unknown host: $name" ]]; then
		ok "--host $name exits 2 with 'unknown host: $name'"
	else
		bad "--host $name exits 2 with 'unknown host: $name' (exit $rc: $(head -n 1 "$TMP/u.err"))"
	fi
}
for name in omo-ai oh-my-openagent nope; do
	unknown_host "$name"
done

# --- temporary catalog roots -----------------------------------------------------
make_root() {
	mkdir -p "$1/$SKILL_SOURCE"
	cp "$REPO_ROOT/$SKILL_SOURCE/SKILL.md" "$1/$SKILL_SOURCE/SKILL.md"
	cat >"$1/catalog.json" <<JSON
{
  "schema_version": "1.0",
  "phases": ["01-discover-decide", "02-govern-plan"],
  "skills": [
    {
      "name": "research",
      "source_path": "$SKILL_SOURCE",
      "owner_phase": "01-discover-decide",
      "applies_to_phases": ["01-discover-decide", "02-govern-plan"],
      "lifecycle": "stable",
      "supported_hosts": [$2]
    }
  ]
}
JSON
}
query_root() {
	local root="$1" host="$2"
	"${QUERY[@]}" --root "$root" --host "$host" >"$TMP/r.out" 2>"$TMP/r.err"
}
ALL_HOSTS='"auggie", "claude-code", "codex", "copilot", "gemini", "opencode"'
ABSENT="$TMP/absent"
make_root "$ABSENT" "$ALL_HOSTS"
absent_payload_host() {
	query_root "$ABSENT" codex && [[ "$(cat "$TMP/r.out")" == "$(printf 'research\t%s' "$SKILL_SOURCE")" ]]
}
absent_alias() {
	query_root "$ABSENT" omc
	[[ $? -eq 2 && "$(cat "$TMP/r.err")" == "unknown host: omc" ]]
}
expect "absent matrix: payload host codex still lists the catalog" absent_payload_host
expect "absent matrix: alias omc is an unknown host" absent_alias

VALID="$TMP/valid"
make_root "$VALID" "$ALL_HOSTS"
copied_alias() {
	cp "$MATRIX" "$VALID/host-matrix.json" 2>/dev/null || return 1
	query_root "$VALID" omc || return 1
	cp "$TMP/r.out" "$TMP/alias.out"
	query_root "$VALID" claude-code && cmp -s "$TMP/alias.out" "$TMP/r.out"
}
expect "copied matrix: omc resolves to claude-code in a temporary root" copied_alias

# --- prototype-key JSON keys (`__proto__`) -------------------------------------
# A `__proto__` key in host-matrix.json is an ordinary JSON key and must survive as
# an own property of the loaded dictionaries: the alias must resolve (plain Node
# would otherwise drop it into the prototype), the skill-name collision check must
# fire on it, and the production shim's `node --disable-proto=throw` must not turn
# any of it into `catalog query failed`.
PROTO="$TMP/proto"
make_root "$PROTO" "$ALL_HOSTS"
proto_alias() {
	sed -e 's/"omx": "codex"/"omx": "codex", "__proto__": "codex"/' "$MATRIX" >"$PROTO/host-matrix.json"
	! cmp -s "$MATRIX" "$PROTO/host-matrix.json" || return 1
	query_root "$PROTO" __proto__ || return 1
	cp "$TMP/r.out" "$TMP/proto.out"
	query_root "$PROTO" codex && cmp -s "$TMP/proto.out" "$TMP/r.out"
}
expect "__proto__ alias is preserved and resolves to codex rows" proto_alias

proto_excluded() {
	sed -e 's/"omo-ai": "/"__proto__": "probe", "omo-ai": "/' "$MATRIX" >"$PROTO/host-matrix.json"
	! cmp -s "$MATRIX" "$PROTO/host-matrix.json" || return 1
	query_root "$PROTO" codex && [[ -s "$TMP/r.out" ]]
}
expect "excluded key __proto__ is preserved and the matrix loads" proto_excluded

PROTO_SKILL="$TMP/proto-skill"
proto_collision() {
	mkdir -p "$PROTO_SKILL/$SKILL_SOURCE"
	sed 's/^name: .*/name: __proto__/' "$REPO_ROOT/$SKILL_SOURCE/SKILL.md" >"$PROTO_SKILL/$SKILL_SOURCE/SKILL.md"
	cat >"$PROTO_SKILL/catalog.json" <<JSON
{
  "schema_version": "1.0",
  "phases": ["01-discover-decide", "02-govern-plan"],
  "skills": [
    {
      "name": "__proto__",
      "source_path": "$SKILL_SOURCE",
      "owner_phase": "01-discover-decide",
      "applies_to_phases": ["01-discover-decide", "02-govern-plan"],
      "lifecycle": "stable",
      "supported_hosts": [$ALL_HOSTS]
    }
  ]
}
JSON
	sed -e 's/"omx": "codex"/"omx": "codex", "__proto__": "codex"/' "$MATRIX" >"$PROTO_SKILL/host-matrix.json"
	query_root "$PROTO_SKILL" codex
	[[ $? -eq 2 && ! -s "$TMP/r.out" && "$(cat "$TMP/r.err")" == "host_matrix_invalid: alias __proto__ is a catalog skill name" ]]
}
expect "__proto__ alias colliding with a skill name is refused host_matrix_invalid" proto_collision

ALIASED="$TMP/aliased"
make_root "$ALIASED" '"codex", "omc"'
validator_refuses() {
	python3 scripts/validate-skill-catalog.py --root "$ALIASED" >"$TMP/v.out" 2>"$TMP/v.err"
	[[ $? -eq 1 && ! -s "$TMP/v.out" ]] && grep -q 'invalid supported_hosts for research' "$TMP/v.err" && ! grep -q 'node_unavailable\|node_version_unsupported' "$TMP/v.err"
}
model_refuses() {
	query_root "$ALIASED" codex
	[[ $? -eq 2 && "$(cat "$TMP/r.err")" == "invalid supported_hosts for research" ]]
}
expect "validator refuses a supported_hosts value naming the alias omc" validator_refuses
expect "catalog model refuses a supported_hosts value naming the alias omc" model_refuses

# --- negative matrix fixtures: each refused with host_matrix_invalid ------------
NEGATIVE="$TMP/negative"
make_root "$NEGATIVE" "$ALL_HOSTS"
negative() {
	local label="$1" host="$2" rc
	shift 2
	if ! sed "$@" "$MATRIX" >"$NEGATIVE/host-matrix.json" 2>/dev/null || cmp -s "$MATRIX" "$NEGATIVE/host-matrix.json"; then
		bad "$label (fixture did not alter the committed matrix)"
		return
	fi
	query_root "$NEGATIVE" "$host"
	rc=$?
	if [[ "$rc" -eq 2 && ! -s "$TMP/r.out" ]] && grep -q '^host_matrix_invalid' "$TMP/r.err" && ! grep -q 'node_unavailable\|node_version_unsupported' "$TMP/r.err"; then
		ok "$label: $(head -n 1 "$TMP/r.err")"
	else
		bad "$label (exit $rc): $(head -n 1 "$TMP/r.err")"
	fi
}
negative "alias whose target is not a payload host" omc -e 's/"omc": "claude-code"/"omc": "nope"/'
negative "alias equal to a payload host" codex -e 's/"omx": "codex"/"omx": "codex", "codex": "claude-code"/'
negative "omo-ai listed as a payload host" codex -e 's/"payload_hosts": \[/"payload_hosts": ["omo-ai", /'
negative "omo-ai listed as an alias" omo-ai -e 's/"omx": "codex"/"omx": "codex", "omo-ai": "opencode"/'
negative "oh-my-openagent listed as an alias" codex -e 's/"omx": "codex"/"omx": "codex", "oh-my-openagent": "opencode"/'
negative "alias equal to a catalog skill name" codex -e 's/"omx": "codex"/"omx": "codex", "research": "codex"/'
negative "payload_hosts missing a HOSTS member" codex -e 's/"auggie", "claude-code"/"claude-code"/' -e '/"auggie": {/d'
negative "excluded key equal to a payload host" codex -e 's/"omo-ai": "/"codex": "x", "omo-ai": "/'
negative "also entry that is not an alias of its host" codex -e 's/"also": \["omx"\]/"also": ["omc"]/'
negative "consumer missing for a payload host" codex -e '/"gemini": {/d'
negative "schema other than host-matrix/1" codex -e 's/"host-matrix\/1"/"host-matrix\/2"/'
negative "installer outside scripts/" codex -e 's#"scripts/install-gemini.sh"#"bin/install-gemini.sh"#'
negative "installer escaping scripts/ by traversal" codex -e 's#"scripts/install-gemini.sh"#"scripts/../../outside.sh"#'

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
