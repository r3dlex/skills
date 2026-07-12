# Ecosystem: Erlang + Hex

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [rebar.config and .app.src Setup](#rebarconfig-and-appsrc-setup)
3. [Version Bump Commands](#version-bump-commands)
4. [Publish Commands](#publish-commands)
5. [Release-Please Config](#release-please-config)
6. [semantic-release Config](#semantic-release-config)
7. [Private Repo Alternative](#private-repo-alternative)

---

Publish commands and version bump logic only.
For CI scaffold, secrets store, and registry auth → read your host file first.

---

## Secrets Needed

| Secret | Where to get it |
|---|---|
| `HEX_API_KEY` | hex.pm → Account Settings → API Keys |

Erlang and Elixir share the same Hex registry and the same API key format.

---

## rebar.config and .app.src Setup

Version lives in `src/your_app.app.src`:

```erlang
{application, your_app, [
  {description, "Your application description"},
  {vsn, "0.0.0"},
  {modules, []},
  {registered, []},
  {applications, [kernel, stdlib]},
  {licenses, ["Apache-2.0"]},
  {links, [{"GitHub", "https://github.com/your-org/your-app"}]}
]}.
```

`rebar.config`:
```erlang
{hex, [{doc, ex_doc}]}.
```

---

## Version Bump Commands

```bash
APP_SRC=$(find src -name "*.app.src" | head -1)
CURRENT=$(grep '{vsn,' "$APP_SRC" | sed 's/.*{vsn, "\(.*\)"}.*/\1/')

if echo "$CURRENT" | grep -q '\-pre\.'; then
  BASE=$(echo "$CURRENT" | cut -d'-' -f1)
  COUNT=$(echo "$CURRENT" | grep -o 'pre\.[0-9]*' | cut -d'.' -f2)
  NEXT="${BASE}-pre.$((COUNT + 1))"
else
  PATCH=$(echo "$CURRENT" | cut -d'.' -f3)
  MAJOR=$(echo "$CURRENT" | cut -d'.' -f1)
  MINOR=$(echo "$CURRENT" | cut -d'.' -f2)
  NEXT="${MAJOR}.${MINOR}.$((PATCH + 1))-pre.1"
fi

sed -i "s/{vsn, \"$CURRENT\"}/{vsn, \"$NEXT\"}/" "$APP_SRC"
```

---

## Publish Commands

**Public registry (hex.pm)**
```bash
HEX_API_KEY=$HEX_API_KEY rebar3 hex publish --yes
```

**Private Hex org**
```bash
HEX_API_KEY=$HEX_API_KEY rebar3 hex publish --organization YOUR_ORG --yes
```

GitHub Packages and Azure Artifacts do not support Hex-compatible feeds.
See [Private Repo Alternative](#private-repo-alternative).

---

## Release-Please Config

No native Erlang type. Use `simple` targeting `.app.src`:

```json
{
  "release-type": "simple",
  "extra-files": [
    {
      "type": "generic",
      "path": "src/your_app.app.src",
      "search-for": "{vsn, \"",
      "replace-with": "{vsn, \""
    }
  ]
}
```

---

## semantic-release Config

Install: `npm install --save-dev @semantic-release/exec @semantic-release/changelog @semantic-release/git`

`prepareCmd`:
```bash
sed -i 's/{vsn, \".*\"}/{vsn, \"${nextRelease.version}\"}/' src/your_app.app.src
```

`publishCmd`:
```bash
rebar3 hex publish --yes
```

Version file for assets: `src/your_app.app.src`

---

## Private Repo Alternative

No Hex-compatible private feed exists on either host. Options:

**Private Hex org**:
```bash
rebar3 hex publish --organization your-org --yes
```

**Git dependency in rebar.config**:
```erlang
{deps, [
  {your_dep, {git, "https://github.com/your-org/your-dep.git", {tag, "v1.2.3"}}}
]}.
```
