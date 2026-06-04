# Language Packs Module

Read when selecting local and CI checks for a repo. Packs are modular: detect manifests first, then ask or require explicit opt-in before assuming missing tools/dependencies.

## Selection rules

1. Detect manifests and lockfiles.
2. Prefer existing package manager commands over inventing new ones.
3. Add CI steps only for tools already present or explicitly selected.
4. In polyglot repos, run each detected pack independently and keep failures attributable to the pack.
5. Do not add dependencies as part of `ai-sdlc-init` unless the user explicitly asks.

## Pack matrix

| Pack | Detection signals | Local checks | CI notes |
| --- | --- | --- | --- |
| TypeScript/Node | `package.json`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `tsconfig.json` | package-manager test/lint/typecheck scripts when present | Use detected package manager; do not assume npm if pnpm/yarn lock exists. |
| Python | `pyproject.toml`, `requirements.txt`, `uv.lock`, `poetry.lock`, `setup.py` | existing pytest/ruff/mypy scripts or documented commands | Prefer uv/poetry when lockfile exists; do not install tools implicitly. |
| Rust | `Cargo.toml`, `Cargo.lock` | `cargo test`, `cargo clippy`, `cargo fmt --check` when configured | Use stable toolchain unless repo pins another toolchain. |
| Go | `go.mod`, `go.sum` | `go test ./...`, `go vet ./...`, configured linters | Respect module/workspace layout and existing Make targets. |
| JVM | `pom.xml`, `build.gradle`, `settings.gradle`, `gradlew`, `mvnw` | Maven/Gradle wrapper test/check tasks | Prefer checked-in wrapper over system Maven/Gradle. |
| .NET | `*.sln`, `*.csproj`, `global.json` | `dotnet test`, `dotnet format --verify-no-changes` when configured | Respect SDK pinned by `global.json`. |
| Polyglot | Multiple pack signals | Run each pack's existing commands separately | Name CI jobs per pack to keep required checks unambiguous. |

## Scaffold output

When a pack is selected, record:

- detection evidence
- selected commands
- commands intentionally skipped and why
- CI job/check names
- required environment variables or services
- owner for maintaining the pack

## Golden fixture expectations

At minimum, fixture coverage should demonstrate one single-language repo and one polyglot repo. Fixtures should show selected commands and skipped commands without installing new dependencies.
