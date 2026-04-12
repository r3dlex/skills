# Ecosystem: Rust + crates.io

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [Cargo.toml Setup](#cargotoml-setup)
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
| `CARGO_REGISTRY_TOKEN` | crates.io → Account Settings → API Tokens |

---

## Cargo.toml Setup

```toml
[package]
name = "your-crate"
version = "0.0.0"
edition = "2021"
description = "Your crate description"
license = "Apache-2.0"
repository = "https://github.com/your-org/your-crate"
```

---

## Version Bump Commands

Requires `cargo-edit`: `cargo install cargo-edit`

```bash
CURRENT=$(cargo metadata --no-deps --format-version 1 | jq -r '.packages[0].version')

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

cargo set-version "$NEXT"
```

---

## Publish Commands

**Public registry (crates.io)**
```bash
CARGO_REGISTRY_TOKEN=$CARGO_REGISTRY_TOKEN cargo publish --allow-dirty
```

Neither GitHub Packages nor Azure Artifacts supports a Cargo-compatible registry.
For private repos, see [Private Repo Alternative](#private-repo-alternative).

---

## Release-Please Config

`release-type: rust` — native support, updates `Cargo.toml` and `Cargo.lock`.

---

## semantic-release Config

Install: `npm install --save-dev @semantic-release/exec @semantic-release/changelog @semantic-release/git`

`prepareCmd`:
```bash
cargo install cargo-edit && cargo set-version ${nextRelease.version}
```

`publishCmd`:
```bash
cargo publish --allow-dirty
```

Version files for assets: `Cargo.toml`, `Cargo.lock`

---

## Private Repo Alternative

Neither host supports a Cargo registry. Build the binary and attach it to the release instead:

```bash
cargo build --release

# GitHub
gh release upload "$TAG" target/release/your-binary

# Azure DevOps
az artifacts universal publish \
  --organization $(ADO_ORG_URL) \
  --feed $(ADO_FEED_NAME) \
  --name your-crate \
  --version "$VERSION" \
  --path target/release/
```
