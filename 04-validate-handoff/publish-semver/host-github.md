# Host: GitHub Actions

## Table of Contents
1. [Required Secrets](#required-secrets)
2. [Visibility Check](#visibility-check)
3. [Release-Please Scaffold](#release-please-scaffold)
4. [semantic-release Scaffold](#semantic-release-scaffold)
5. [Floating Tags Step](#floating-tags-step)
6. [Registry Auth Patterns](#registry-auth-patterns)

---

All CI runs on GitHub Actions. The private registry is GitHub Packages.
Public registry publishing is gated automatically on repo visibility.

---

## Required Secrets

| Secret | Source |
|---|---|
| `GITHUB_TOKEN` | Injected automatically by GitHub Actions |
| Ecosystem tokens | See your ecosystem file |

---

## Visibility Check

Insert this fragment wherever you need to gate public registry publishing:

```bash
PRIVATE=$(gh repo view --json isPrivate -q '.isPrivate')
if [ "$PRIVATE" = "false" ]; then
  # PUBLISH TO PUBLIC REGISTRY
fi
# always publish to GitHub Packages below
```

Requires `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` in the step `env` block.

---

## Release-Please Scaffold

```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write
  packages: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    outputs:
      release_created: ${{ steps.release.outputs.release_created }}
      tag_name: ${{ steps.release.outputs.tag_name }}
    steps:
      - uses: googleapis/release-please-action@v4
        id: release
        with:
          release-type: REPLACE_WITH_ECOSYSTEM_TYPE
          token: ${{ secrets.GITHUB_TOKEN }}

  pre-release:
    needs: release-please
    if: needs.release-please.outputs.release_created != 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # ECOSYSTEM SETUP STEPS
      - name: Bump pre-release version
        run: |
          # ECOSYSTEM VERSION BUMP COMMANDS
      - name: Publish pre-release
        run: |
          PRIVATE=$(gh repo view --json isPrivate -q '.isPrivate')
          if [ "$PRIVATE" = "false" ]; then
            # ECOSYSTEM PUBLIC REGISTRY PUBLISH
          fi
          # ECOSYSTEM GITHUB PACKAGES PUBLISH
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # ECOSYSTEM SECRETS

  stable-publish:
    needs: release-please
    if: needs.release-please.outputs.release_created == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # ECOSYSTEM SETUP STEPS
      - name: Publish stable
        run: |
          PRIVATE=$(gh repo view --json isPrivate -q '.isPrivate')
          if [ "$PRIVATE" = "false" ]; then
            # ECOSYSTEM PUBLIC REGISTRY PUBLISH
          fi
          # ECOSYSTEM GITHUB PACKAGES PUBLISH
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # ECOSYSTEM SECRETS
      - name: Update floating tags
        run: |
          TAG=${{ needs.release-please.outputs.tag_name }}
          MAJOR=$(echo $TAG | cut -d. -f1 | tr -d v)
          git tag -f "v$MAJOR" "$TAG"
          git push origin "v$MAJOR" --force
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

`release-type` values per ecosystem:

| Ecosystem | release-type |
|---|---|
| JS/TS | `node` |
| Python | `python` |
| Java | `maven` |
| Rust | `rust` |
| Elixir, Kotlin, Dart, Erlang, C# | `simple` |

---

## semantic-release Scaffold

```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: write
  packages: write
  id-token: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      # ECOSYSTEM SETUP STEPS
      - name: Run semantic-release
        run: npx semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # ECOSYSTEM SECRETS
```

`.releaserc.json` base:

```json
{
  "branches": [
    "main",
    { "name": "main", "prerelease": "pre" }
  ],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    ["@semantic-release/exec", {
      "prepareCmd": "ECOSYSTEM_VERSION_BUMP_COMMAND",
      "publishCmd": "ECOSYSTEM_PUBLISH_COMMAND"
    }],
    ["@semantic-release/git", {
      "assets": ["CHANGELOG.md", "ECOSYSTEM_VERSION_FILE"],
      "message": "chore(release): ${nextRelease.version} [skip ci]"
    }]
  ]
}
```

---

## Floating Tags Step

Full details: [floating-tags.md](floating-tags.md)

Quick reference — add to `stable-publish` after publishing:

```bash
TAG=v1.2.3
MAJOR=$(echo $TAG | cut -d. -f1 | tr -d v)
git tag -f "v$MAJOR" "$TAG"
git push origin "v$MAJOR" --force
```

---

## Registry Auth Patterns

**GitHub Packages — npm**
```bash
npm config set @YOUR_ORG:registry https://npm.pkg.github.com
npm config set //npm.pkg.github.com/:_authToken $GITHUB_TOKEN
```

**GitHub Packages — Maven / Gradle**
```
Repository URL: https://maven.pkg.github.com/YOUR_ORG/YOUR_REPO
Username: $GITHUB_ACTOR
Password: $GITHUB_TOKEN
```

**GitHub Packages — NuGet**
```bash
dotnet nuget add source \
  "https://nuget.pkg.github.com/YOUR_ORG/index.json" \
  --name github \
  --username $GITHUB_ACTOR \
  --password $GITHUB_TOKEN
```
