# Language Packs Module

Read when selecting local and CI checks for a repo. Packs are modular: detect manifests first, then ask or require explicit opt-in before assuming missing tools/dependencies. Each pack is opt-in and never adds dependencies on its own.

## Selection rules

1. Detect manifests and lockfiles.
2. Prefer existing package manager commands over inventing new ones.
3. Add CI steps only for tools already present or explicitly selected.
4. In polyglot repos, run each detected pack independently and keep failures attributable to the pack.
5. Do not add dependencies as part of `ai-catapult-init` unless the user explicitly asks.

## Pack matrix

| Pack | Detection signals | Local checks | CI notes |
| --- | --- | --- | --- |
| TypeScript/Node | `package.json`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `tsconfig.json` | package-manager test/lint/typecheck scripts when present | Use detected package manager; do not assume npm if pnpm/yarn lock exists. |
| Python | `pyproject.toml`, `requirements.txt`, `uv.lock`, `poetry.lock`, `setup.py` | existing pytest/ruff/mypy scripts or documented commands | Prefer uv/poetry when lockfile exists; do not install tools implicitly. |
| Rust | `Cargo.toml`, `Cargo.lock` | `cargo test`, `cargo clippy`, `cargo fmt --check` when configured | Use stable toolchain unless repo pins another toolchain. |
| Go | `go.mod`, `go.sum` | `go test ./...`, `go vet ./...`, configured linters | Respect module/workspace layout and existing Make targets. |
| JVM | `pom.xml`, `build.gradle`, `settings.gradle`, `gradlew`, `mvnw` | Maven/Gradle wrapper test/check tasks | Prefer checked-in wrapper over system Maven/Gradle. |
| .NET Core / EF Core | `*.csproj` with `TargetFramework` `net6.0`+ or `netstandard2.1`+; `*.sln`; `global.json`; `appsettings*.json`; `Program.cs` using `Host.CreateDefaultBuilder` or `WebApplication.CreateBuilder`; `*.DbContext` and `*ModelBuilder*.cs` for EF Core | `dotnet test`, `dotnet build`, `dotnet format --verify-no-changes`, `dotnet ef migrations script` (when EF Core present) | Respect SDK pinned by `global.json`. CI must use the same SDK; do not run `dotnet --list-sdks` from a system install. |
| Legacy .NET / EF (Framework) | `*.csproj` with `TargetFrameworkVersion` v4.x; `packages.config`; `App.config` / `Web.config`; `*.edmx` under `Models\\` or `DAL\\`; presence of `EntityFramework` 6.x package reference | `msbuild /t:Build` (when present) plus `nuget restore`; legacy `EF` migrations via `migrate.exe` only if configured | Do not assume the host has .NET Framework SDK installed; run on a Windows agent or in a self-hosted runner with the legacy toolchain. Surface legacy checks as opt-in until the toolchain is verified. |
| Polyglot | Multiple pack signals | Run each pack's existing commands separately | Name CI jobs per pack to keep required checks unambiguous. |

## .NET Core / EF Core specifics

- Detection: parse `*.csproj` for `<TargetFramework>net6.0</TargetFramework>` or newer, or for `<PackageReference Include="Microsoft.EntityFrameworkCore" ...>`. EF Core is implied by `Microsoft.EntityFrameworkCore.*` package references.
- Toolchain pin: respect `global.json`. If `global.json` is missing, record a `toolchain-not-pinned` note in the scaffold output; do not assume a default SDK.
- Local checks: `dotnet restore` (when lockfile missing), `dotnet build -c Release`, `dotnet test`, `dotnet format --verify-no-changes`, and `dotnet ef migrations script --idempotent` only when EF Core is present.
- CI matrix: run on `ubuntu-latest` and `windows-latest` only when the repo contains Windows-only code paths. Do not silently add a Windows job to a Linux-only repo.
- Analyzers: when `Microsoft.CodeAnalysis.NetAnalyzers` is referenced, add `<EnableNETAnalyzers>true</EnableNETAnalyzers>` and `<AnalysisLevel>latest</AnalysisLevel>` checks; surface them as opt-in when not present.
- Migrations: `dotnet ef migrations script` is a build-time artifact, not a runtime test. The pack does not run migrations against a live database in CI.

## Legacy .NET / EF specifics

- Detection: parse `*.csproj` for `<TargetFrameworkVersion>v4.</TargetFrameworkVersion>` (4.x) or for `packages.config` alongside `App.config` / `Web.config`. EF 6.x is implied by `<package id="EntityFramework" version="6.x" />` in `packages.config`.
- Toolchain pin: legacy projects pin the .NET Framework target version in the project file. The pack must not assume the agent has the matching reference assemblies. Surface a `legacy-toolchain-required` note and require explicit opt-in.
- Local checks: prefer `msbuild` from a self-hosted runner or a Windows agent. Do not run `dotnet test` against a legacy project; it is not supported.
- Migrations: EF 6.x migrations are produced via `migrate.exe` and may require a startup project. The pack documents the path but does not run migrations in CI by default.
- Supersession: when a legacy project is migrating to .NET Core / EF Core, the pack records both states in `language-packs-snapshot.json` and tracks the migration in `docs/architecture/adr/`. See `modules/migration.md` for the full migration classification rules.

## Scaffold output

When a pack is selected, record:

- detection evidence (which file matched and which line was the signal)
- selected commands and their rationale
- commands intentionally skipped and why (e.g., `dotnet ef migrations script` skipped because EF Core is not present)
- CI job/check names per pack
- required environment variables or services
- owner for maintaining the pack
- toolchain pin (or `toolchain-not-pinned` note)

## Golden fixture expectations

At minimum, fixture coverage should demonstrate:

- one TypeScript/Node repo with `pnpm-lock.yaml` resolved to pnpm, not npm
- one Python repo with `uv.lock` resolved to uv
- one .NET Core / EF Core repo with `global.json` and EF Core migrations
- one legacy .NET / EF Framework repo marked as opt-in and surfaced via the legacy supersession rules
- one polyglot repo where each pack's checks run independently
