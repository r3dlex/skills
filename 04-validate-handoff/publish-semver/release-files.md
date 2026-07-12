# Release Files

## Table of Contents
1. [Files Per Ecosystem](#files-per-ecosystem)
2. [Commit Message Convention](#commit-message-convention)
3. [Automated Release Commit](#automated-release-commit)
4. [CHANGELOG.md Format](#changelogmd-format)
5. [Reading Version at Runtime](#reading-version-at-runtime)

---

Files that must stay in sync with every release. Both Release-Please and semantic-release update these automatically when configured correctly. Do not hand-edit them.

---

## Files Per Ecosystem

| Ecosystem | Version file | Updated by |
|---|---|---|
| JS/TS | `package.json` | Release-Please (node) / semantic-release |
| Python | `pyproject.toml` | Release-Please (python) / python-semantic-release |
| Elixir | `mix.exs` | Release-Please (simple) / `@semantic-release/exec` |
| Rust | `Cargo.toml`, `Cargo.lock` | Release-Please (rust) / `@semantic-release/exec` |
| C# | `*.csproj` | Release-Please (simple, xml) / `@semantic-release/exec` |
| Dart | `pubspec.yaml` | Release-Please (simple) / `@semantic-release/exec` |
| Java | `pom.xml` | Release-Please (maven) / `@semantic-release/exec` |
| Kotlin | `gradle.properties` | Release-Please (simple) / `@semantic-release/exec` |
| Erlang | `src/*.app.src` | Release-Please (simple) / `@semantic-release/exec` |

All ecosystems also update `CHANGELOG.md`.

---

## Commit Message Convention

| Prefix | Stable bump | Example |
|---|---|---|
| `fix:` | patch | `fix: resolve null pointer in auth` |
| `feat:` | minor | `feat: add dark mode toggle` |
| `feat!:` or `BREAKING CHANGE:` | major | `feat!: remove legacy API endpoint` |
| `chore:`, `docs:`, `test:` | none | `docs: update README` |

Commits with no matching prefix still increment the pre-release counter but do not change the pending stable bump.

---

## Automated Release Commit

Both tools commit updated files back to `main` with a skip-CI marker:

```
chore(release): 0.1.3 [skip ci]
```

Do not use `[skip ci]` in your own commits. It is reserved for release tooling.

---

## CHANGELOG.md Format

Both tools produce Keep a Changelog format:

```md
## [0.1.3] - 2024-11-15

### Features
- add login page (#42)

### Bug Fixes
- fix header alignment (#41)
```

---

## Reading Version at Runtime

Source version from the file the tool owns. Do not duplicate it.

**Elixir**
```elixir
Mix.Project.config()[:version]
```

**JS/TS**
```js
import { version } from './package.json' assert { type: 'json' }
```

**Python**
```python
from importlib.metadata import version
__version__ = version("your-package")
```

**Rust**
```rust
const VERSION: &str = env!("CARGO_PKG_VERSION");
```

**Kotlin / Java**
```kotlin
val version = javaClass.`package`.implementationVersion
```
