# Ecosystem: JS/TS + npm

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [package.json Setup](#packagejson-setup)
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
| `NPM_TOKEN` | npmjs.com → Access Tokens → Automation token |

---

## package.json Setup

```json
{
  "name": "@your-org/your-package",
  "version": "0.0.0",
  "publishConfig": {
    "access": "public"
  }
}
```

Package name must use the scoped `@your-org/` format for GitHub Packages and Azure Artifacts.

---

## Version Bump Commands

```bash
CURRENT=$(node -p "require('./package.json').version")

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

npm version "$NEXT" --no-git-tag-version
```

---

## Publish Commands

**Public registry (npm)**
```bash
NODE_AUTH_TOKEN=$NPM_TOKEN npm publish --tag pre      # pre-release
NODE_AUTH_TOKEN=$NPM_TOKEN npm publish --tag latest   # stable
```

**GitHub Packages**
```bash
npm config set @YOUR_ORG:registry https://npm.pkg.github.com
npm config set //npm.pkg.github.com/:_authToken $GITHUB_TOKEN
npm publish --tag pre      # pre-release
npm publish --tag latest   # stable
```

**Azure Artifacts**
```bash
# Auth via npmAuthenticate task — see host-ado.md
npm publish --tag pre      # pre-release
npm publish --tag latest   # stable
```

---

## Release-Please Config

`release-type: node` — native support, no extra config file needed.

---

## semantic-release Config

`prepareCmd`:
```bash
npm version ${nextRelease.version} --no-git-tag-version
```

`publishCmd`:
```bash
npm publish --tag $(node -e "process.stdout.write('${nextRelease.version}'.includes('pre') ? 'pre' : 'latest')")
```

Version file for `@semantic-release/git` assets: `package.json`
