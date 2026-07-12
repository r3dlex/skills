# Ecosystem: Python + PyPI

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [pyproject.toml Setup](#pyprojecttoml-setup)
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
| `PYPI_API_TOKEN` | pypi.org → Account Settings → API Tokens |

Recommended alternative for GitHub: PyPI Trusted Publishing (OIDC) — no token needed. See [PyPI docs](https://docs.pypi.org/trusted-publishers/).

---

## pyproject.toml Setup

```toml
[project]
name = "your-package"
version = "0.0.0"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

---

## Version Bump Commands

```bash
pip install hatch --quiet

CURRENT=$(hatch version)

if echo "$CURRENT" | grep -q '\.pre'; then
  BASE=$(echo "$CURRENT" | grep -oP '^\d+\.\d+\.\d+')
  COUNT=$(echo "$CURRENT" | grep -oP '(?<=pre)\d+')
  NEXT="${BASE}.pre$((COUNT + 1))"
else
  PATCH=$(echo "$CURRENT" | cut -d'.' -f3)
  MAJOR=$(echo "$CURRENT" | cut -d'.' -f1)
  MINOR=$(echo "$CURRENT" | cut -d'.' -f2)
  NEXT="${MAJOR}.${MINOR}.$((PATCH + 1)).pre1"
fi

hatch version "$NEXT"
hatch build
```

PEP 440 pre-release format: `0.1.3.pre1` not `0.1.3-pre.1`. `python-semantic-release` handles this mapping automatically.

---

## Publish Commands

**Public registry (PyPI)**
```bash
pip install twine --quiet
twine upload dist/* -u __token__ -p $PYPI_API_TOKEN --skip-existing
```

**GitHub Packages**
```bash
twine upload \
  --repository-url https://upload.pypi.org/legacy/ \
  --skip-existing dist/* \
  -u __token__ -p $GITHUB_TOKEN
```

**Azure Artifacts**
```bash
# Auth via TwineAuthenticate task — see host-ado.md
twine upload -r YOUR_FEED_NAME dist/* --skip-existing
```

---

## Release-Please Config

`release-type: python` — native support, no extra config file needed.

---

## semantic-release Config

Install: `pip install python-semantic-release`

`pyproject.toml` additions:
```toml
[tool.semantic_release]
version_toml = ["pyproject.toml:project.version"]
branch = "main"
pre_release_tag = "pre"
build_command = "hatch build"
upload_to_pypi = true

[tool.semantic_release.branches.main]
match = "main"
prerelease = true
prerelease_token = "pre"
```

Run with: `semantic-release publish`
Version file for assets: `pyproject.toml`
