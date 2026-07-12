# Ecosystem: Elixir + Hex

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [mix.exs Setup](#mixexs-setup)
3. [Version Bump Commands](#version-bump-commands)
4. [Publish Commands](#publish-commands)
5. [Release-Please Config](#release-please-config)
6. [semantic-release Config](#semantic-release-config)

---

Publish commands and version bump logic only.
For CI scaffold, secrets store, and registry auth → read your host file first.

---

## Secrets Needed

| Secret | Where to get it |
|---|---|
| `HEX_API_KEY` | hex.pm → Account Settings → API Keys |

---

## mix.exs Setup

```elixir
defmodule YourPackage.MixProject do
  use Mix.Project

  def project do
    [
      app: :your_package,
      version: "0.0.0",
      description: "Your package description",
      package: package()
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/your-org/your-package"}
    ]
  end
end
```

Keep `version:` as a plain string literal on its own line. Both Release-Please and `sed` require this.

---

## Version Bump Commands

```bash
CURRENT=$(grep 'version:' mix.exs | sed 's/.*version: "\(.*\)".*/\1/')

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

sed -i "s/version: \"$CURRENT\"/version: \"$NEXT\"/" mix.exs
```

---

## Publish Commands

**Public registry (hex.pm)**
```bash
HEX_API_KEY=$HEX_API_KEY mix hex.publish --yes
```

**Private Hex org**
```bash
HEX_API_KEY=$HEX_API_KEY mix hex.publish --organization YOUR_ORG --yes
```

GitHub Packages and Azure Artifacts do not support Hex-compatible feeds. For private packages on either host, use a private Hex org or Git dependencies.

---

## Release-Please Config

No native Elixir type. Use `simple`:

```json
{
  "release-type": "simple",
  "extra-files": [
    {
      "type": "generic",
      "path": "mix.exs",
      "search-for": "version: \"",
      "replace-with": "version: \""
    }
  ]
}
```

---

## semantic-release Config

Install: `npm install --save-dev @semantic-release/exec @semantic-release/changelog @semantic-release/git`

`prepareCmd`:
```bash
sed -i 's/version: \".*\"/version: \"${nextRelease.version}\"/' mix.exs
```

`publishCmd`:
```bash
mix hex.publish --yes
```

Version file for assets: `mix.exs`
