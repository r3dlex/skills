---
name: publish-semver
description: "Set up semantic or calendar versioning and package publishing across supported ecosystems. Use when configuring release automation or changelogs."
---

# publish-semver

## Version Model

Every push to `main` creates a pre-release. A Release-Please PR merge or semantic-release stable tag promotes it to stable.

```
0.1.3-pre.1   ← push to main
0.1.3-pre.2   ← push to main
0.1.3         ← stable release
```

Commit type controls the next stable bump:
- `fix:` → patch (0.1.2 → 0.1.3)
- `feat:` → minor (0.1.2 → 0.2.0)
- `feat!:` / `BREAKING CHANGE:` → major (0.1.2 → 1.0.0)

## Step 1: Pick Your Host

| Host | CI system | Private registry |
|---|---|---|
| **GitHub** | GitHub Actions | GitHub Packages |
| **Azure DevOps** | Azure Pipelines | Azure Artifacts |

Read the host file first. It contains the full CI job scaffold, auth patterns, visibility checks, and floating tag steps.

- GitHub → [host-github.md](host-github.md)
- Azure DevOps → [host-ado.md](host-ado.md)

## Step 2: Pick Your Strategy

| Strategy | How it works | Best for |
|---|---|---|
| **Release-Please** | Accumulates commits into a release PR. Stable publish on PR merge. | Teams that want a review gate. |
| **semantic-release** | Tags and publishes on every qualifying push to `main`. | Fully automated pipelines. |

Both produce pre-releases on every push to `main`.

## Step 3: Pick Your Ecosystem

| Ecosystem | File |
|---|---|
| JS/TS + npm | [js-npm.md](js-npm.md) |
| Python + PyPI | [python-pypi.md](python-pypi.md) |
| Elixir + Hex | [elixir-hex.md](elixir-hex.md) |
| Elixir + Burrito binaries | [elixir-burrito.md](elixir-burrito.md) |
| Rust + crates.io | [rust-crates.md](rust-crates.md) |
| C# + NuGet | [csharp-nuget.md](csharp-nuget.md) |
| Dart / Flutter + pub.dev | [dart-pub.md](dart-pub.md) |
| Java + Maven Central | [java-maven.md](java-maven.md) |
| Kotlin + Gradle + Maven Central | [kotlin-gradle.md](kotlin-gradle.md) |
| Erlang + Hex | [erlang-hex.md](erlang-hex.md) |

## Step 4: Compose the Workflow

Ecosystem files provide publish commands and version bump logic only.
The host file provides the full CI job scaffold. Combine them:

1. Copy the job scaffold from the host file.
2. Replace the `# ECOSYSTEM PUBLISH STEPS` placeholder with commands from the ecosystem file.
3. Add required secrets from the ecosystem file to your CI secret store.

## Supporting References

| Need | File |
|---|---|
| Floating major version tags | [floating-tags.md](floating-tags.md) |
| CHANGELOG and release file conventions | [release-files.md](release-files.md) |
