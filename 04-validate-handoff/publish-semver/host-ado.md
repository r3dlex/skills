# Host: Azure DevOps

## Table of Contents
1. [Required Variables and Secrets](#required-variables-and-secrets)
2. [Visibility Check](#visibility-check)
3. [Release-Please Scaffold](#release-please-scaffold)
4. [semantic-release Scaffold](#semantic-release-scaffold)
5. [Floating Tags Step](#floating-tags-step)
6. [Registry Auth Patterns](#registry-auth-patterns)

---

All CI runs on Azure Pipelines. The private registry is Azure Artifacts.
Public registry publishing is gated on the `PUBLIC_RELEASE` pipeline variable.

---

## Required Variables and Secrets

Store secrets in Azure Pipelines → Library → Variable Groups. Mark sensitive values as secret.

| Variable | Source |
|---|---|
| `SYSTEM_ACCESSTOKEN` | Injected automatically by Azure Pipelines |
| `ADO_FEED_NAME` | Your Azure Artifacts feed name |
| `ADO_ORG_URL` | e.g. `https://pkgs.dev.azure.com/your-org` |
| `PUBLIC_RELEASE` | Pipeline variable — set `true` for public-facing projects |
| Ecosystem tokens | See your ecosystem file |

Enable `SYSTEM_ACCESSTOKEN` in every job that needs it:
```yaml
env:
  SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

---

## Visibility Check

Azure DevOps projects are private by default. Gate public registry publishing on a pipeline variable:

```bash
if [ "$(PUBLIC_RELEASE)" = "true" ]; then
  # PUBLISH TO PUBLIC REGISTRY
fi
# always publish to Azure Artifacts below
```

Set `PUBLIC_RELEASE` as a non-secret pipeline variable. Leave unset or `false` for internal projects.

---

## Release-Please Scaffold

Release-Please has limited native ADO support. For pure ADO repos without a GitHub mirror, use semantic-release instead.

If your ADO repo mirrors to GitHub, use this pattern:

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: ubuntu-latest

variables:
  - group: release-secrets

stages:
  - stage: Release
    jobs:
      - job: ReleasePlease
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'
          - script: |
              npx release-please release-pr \
                --token $(GITHUB_TOKEN) \
                --repo-url YOUR_ORG/YOUR_REPO \
                --release-type REPLACE_WITH_ECOSYSTEM_TYPE
            displayName: Create or update release PR

      - job: PreRelease
        condition: ne(variables['RELEASE_CREATED'], 'true')
        steps:
          - checkout: self
            persistCredentials: true
          # ECOSYSTEM SETUP STEPS
          - script: |
              # ECOSYSTEM VERSION BUMP COMMANDS
            displayName: Bump pre-release version
          - script: |
              if [ "$(PUBLIC_RELEASE)" = "true" ]; then
                # ECOSYSTEM PUBLIC REGISTRY PUBLISH
              fi
              # ECOSYSTEM AZURE ARTIFACTS PUBLISH
            displayName: Publish pre-release
            env:
              SYSTEM_ACCESSTOKEN: $(System.AccessToken)
              # ECOSYSTEM SECRETS

      - job: StablePublish
        condition: eq(variables['RELEASE_CREATED'], 'true')
        steps:
          - checkout: self
            persistCredentials: true
          # ECOSYSTEM SETUP STEPS
          - script: |
              if [ "$(PUBLIC_RELEASE)" = "true" ]; then
                # ECOSYSTEM PUBLIC REGISTRY PUBLISH
              fi
              # ECOSYSTEM AZURE ARTIFACTS PUBLISH
            displayName: Publish stable
            env:
              SYSTEM_ACCESSTOKEN: $(System.AccessToken)
              # ECOSYSTEM SECRETS
          - script: |
              TAG=$(TAG_NAME)
              MAJOR=$(echo $TAG | cut -d. -f1 | tr -d v)
              git config user.email "pipeline@your-org.com"
              git config user.name "Release Pipeline"
              git tag -f "v$MAJOR" "$TAG"
              git push origin "v$MAJOR" --force
            displayName: Update floating tags
```

---

## semantic-release Scaffold

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: ubuntu-latest

variables:
  - group: release-secrets

jobs:
  - job: Release
    steps:
      - checkout: self
        fetchDepth: 0
        persistCredentials: true
      - task: NodeTool@0
        inputs:
          versionSpec: '20.x'
      # ECOSYSTEM SETUP STEPS
      - script: |
          npm ci
          npx semantic-release
        displayName: Run semantic-release
        env:
          GIT_AUTHOR_NAME: $(Build.RequestedFor)
          GIT_AUTHOR_EMAIL: $(Build.RequestedForEmail)
          GIT_COMMITTER_NAME: $(Build.RequestedFor)
          GIT_COMMITTER_EMAIL: $(Build.RequestedForEmail)
          SYSTEM_ACCESSTOKEN: $(System.AccessToken)
          # ECOSYSTEM SECRETS
```

Configure git remote auth for ADO before running semantic-release:
```bash
git remote set-url origin \
  https://$(SYSTEM_ACCESSTOKEN)@dev.azure.com/YOUR_ORG/YOUR_PROJECT/_git/YOUR_REPO
```

`.releaserc.json` base for ADO:

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

Quick reference — add after stable publish, requires `persistCredentials: true` on checkout:

```bash
TAG=$(TAG_NAME)
MAJOR=$(echo $TAG | cut -d. -f1 | tr -d v)
git config user.email "pipeline@your-org.com"
git config user.name "Release Pipeline"
git tag -f "v$MAJOR" "$TAG"
git push origin "v$MAJOR" --force
```

---

## Registry Auth Patterns

**Azure Artifacts — npm**
```yaml
- task: npmAuthenticate@0
  inputs:
    workingFile: .npmrc
```

`.npmrc`:
```
registry=https://pkgs.dev.azure.com/YOUR_ORG/_packaging/YOUR_FEED/npm/registry/
always-auth=true
```

**Azure Artifacts — Maven / Gradle**
```yaml
- task: MavenAuthenticate@0
  inputs:
    artifactsFeeds: YOUR_FEED_NAME
```
Feed URL: `https://pkgs.dev.azure.com/YOUR_ORG/_packaging/YOUR_FEED/maven/v1`

**Azure Artifacts — NuGet**
```yaml
- task: NuGetAuthenticate@1

- script: |
    dotnet nuget add source \
      "https://pkgs.dev.azure.com/YOUR_ORG/_packaging/YOUR_FEED/nuget/v3/index.json" \
      --name azure \
      --username az \
      --password $(System.AccessToken)
```

**Azure Artifacts — Python (twine)**
```yaml
- task: TwineAuthenticate@1
  inputs:
    artifactsFeed: YOUR_FEED_NAME

- script: python -m twine upload -r YOUR_FEED_NAME dist/*
```
