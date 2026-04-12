# Floating Tags

## Table of Contents
1. [When to Use](#when-to-use)
2. [How It Works](#how-it-works)
3. [GitHub Actions Step](#github-actions-step)
4. [Azure Pipelines Step](#azure-pipelines-step)
5. [Multiple Floating Tags](#multiple-floating-tags)
6. [Pre-releases](#pre-releases)
7. [Verification](#verification)

---

A floating tag points a major version label (e.g. `v1`) to the latest stable patch (e.g. `v1.2.3`). Consumers pin to `v1` and receive bug fixes automatically without updating their config.

---

## When to Use

Use when your package is consumed as a GitHub Action, CLI tool, or any dependency where consumers pin by major version.

Do not use for library packages where consumers pin exact versions in a lockfile (npm, pip, mix, Cargo). Those ecosystems handle resolution differently.

---

## How It Works

After every stable release, force-move the major tag to the new stable commit:

```bash
git tag -f v1 v1.2.3
git push origin v1 --force
```

`v1` now resolves to the same commit as `v1.2.3`.

---

## GitHub Actions Step

Add to the `stable-publish` job after the release tag exists:

```bash
TAG=v1.2.3
MAJOR=$(echo $TAG | cut -d. -f1 | tr -d v)
git tag -f "v$MAJOR" "$TAG"
git push origin "v$MAJOR" --force
```

Env: `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`

---

## Azure Pipelines Step

Requires `persistCredentials: true` on the checkout step:

```bash
TAG=$(TAG_NAME)
MAJOR=$(echo $TAG | cut -d. -f1 | tr -d v)
git config user.email "pipeline@your-org.com"
git config user.name "Release Pipeline"
git tag -f "v$MAJOR" "$TAG"
git push origin "v$MAJOR" --force
```

---

## Multiple Floating Tags

Maintain both `vMAJOR` and `vMAJOR.MINOR` only if consumers actually pin at minor granularity:

```bash
git tag -f v1 v1.2.3
git tag -f v1.2 v1.2.3
git push origin v1 v1.2 --force
```

---

## Pre-releases

Never move a floating tag to a pre-release. Floating tags point only to stable releases.

---

## Verification

```bash
git ls-remote origin refs/tags/v1
git ls-remote origin refs/tags/v1.2.3
# Both lines must show the same SHA
```
