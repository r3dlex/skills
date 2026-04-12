# Ecosystem: Elixir + Burrito Binaries

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [mix.exs Burrito Setup](#mixexs-burrito-setup)
3. [Version Bump Commands](#version-bump-commands)
4. [Build and Attach Commands](#build-and-attach-commands)
5. [Supported Targets](#supported-targets)
6. [Release-Please Config](#release-please-config)

---

Burrito produces self-contained platform binaries. There is no registry.
Publishing means attaching binaries to a release as assets.
For CI scaffold and secrets store → read your host file first.

---

## Secrets Needed

| Secret | Source |
|---|---|
| `GITHUB_TOKEN` | GitHub Actions: injected automatically |
| `SYSTEM_ACCESSTOKEN` | Azure Pipelines: injected automatically |

No external registry token needed.

---

## mix.exs Burrito Setup

```elixir
def releases do
  [
    your_app: [
      steps: [:assemble, &Burrito.wrap/1],
      burrito: [
        targets: [
          macos_arm:   [os: :darwin,  cpu: :aarch64],
          macos_intel: [os: :darwin,  cpu: :x86_64],
          linux_x86:   [os: :linux,   cpu: :x86_64],
          windows_x86: [os: :windows, cpu: :x86_64]
        ]
      ]
    ]
  ]
end
```

Add to deps: `{:burrito, github: "burrito-elixir/burrito"}`

---

## Version Bump Commands

Same as Elixir + Hex. See [elixir-hex.md](elixir-hex.md#version-bump-commands).

---

## Build and Attach Commands

Build binary for the current target:
```bash
MIX_ENV=prod BURRITO_TARGET=linux_x86 mix release
```

Binaries land in `burrito_out/`.

**GitHub — attach to release**
```bash
# Pre-release: create a new pre-release entry and upload
gh release create "pre-$VERSION" --prerelease --title "Pre-release $VERSION" burrito_out/*

# Stable: upload to the release created by Release-Please
gh release upload "$TAG" burrito_out/* --repo YOUR_ORG/YOUR_REPO
```

**Azure DevOps — publish as universal package**
```bash
az artifacts universal publish \
  --organization $(ADO_ORG_URL) \
  --feed $(ADO_FEED_NAME) \
  --name your-app \
  --version "$VERSION" \
  --path burrito_out/
```

---

## Supported Targets

| Target key | OS | CPU | Runner |
|---|---|---|---|
| `macos_arm` | macOS | Apple Silicon | `macos-latest` |
| `macos_intel` | macOS | Intel x86_64 | `macos-13` |
| `linux_x86` | Linux | x86_64 | `ubuntu-latest` |
| `windows_x86` | Windows | x86_64 | `windows-latest` |
| `linux_arm` | Linux | aarch64 | `ubuntu-latest` + QEMU |

Use a matrix strategy — one job per target, each runner builds only its own binary.

---

## Release-Please Config

Same as Elixir + Hex. See [elixir-hex.md](elixir-hex.md#release-please-config).
