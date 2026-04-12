# Ecosystem: Dart / Flutter + pub.dev

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [pubspec.yaml Setup](#pubspecyaml-setup)
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
| `PUB_CREDENTIALS` | Run `dart pub login` locally, copy `~/.pub-cache/credentials.json` as a single secret |

---

## pubspec.yaml Setup

```yaml
name: your_package
version: 0.0.0
description: Your package description.
repository: https://github.com/your-org/your-package

environment:
  sdk: ">=3.0.0 <4.0.0"
```

---

## Version Bump Commands

```bash
CURRENT=$(grep '^version:' pubspec.yaml | sed 's/version: //')

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

sed -i "s/^version: $CURRENT/version: $NEXT/" pubspec.yaml
```

---

## Publish Commands

**Public registry (pub.dev)**
```bash
mkdir -p ~/.pub-cache
echo "$PUB_CREDENTIALS" > ~/.pub-cache/credentials.json
dart pub publish --force
```

Use `--force` in CI to bypass the interactive confirmation prompt.

Neither GitHub Packages nor Azure Artifacts supports a pub-compatible feed.
For private packages, see [Private Repo Alternative](#private-repo-alternative).

---

## Release-Please Config

No native Dart type. Use `simple`:

```json
{
  "release-type": "simple",
  "extra-files": [
    {
      "type": "generic",
      "path": "pubspec.yaml",
      "search-for": "version: ",
      "replace-with": "version: "
    }
  ]
}
```

---

## semantic-release Config

Install: `npm install --save-dev @semantic-release/exec @semantic-release/changelog @semantic-release/git`

`prepareCmd`:
```bash
sed -i 's/^version: .*/version: ${nextRelease.version}/' pubspec.yaml
```

`publishCmd`:
```bash
mkdir -p ~/.pub-cache && echo $PUB_CREDENTIALS > ~/.pub-cache/credentials.json && dart pub publish --force
```

Version file for assets: `pubspec.yaml`

---

## Private Repo Alternative

No pub-compatible private feed exists on either host. Options:

**Self-hosted pub server**: [unpub](https://github.com/bytedance/unpub)

**Git dependency in pubspec.yaml**:
```yaml
dependencies:
  your_package:
    git:
      url: https://github.com/your-org/your-package.git
      ref: v1.2.3
```

Private repos skip `dart pub publish` entirely.
