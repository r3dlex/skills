# Ecosystem: Kotlin + Gradle + Maven Central

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [gradle.properties and build.gradle.kts Setup](#gradleproperties-and-buildgradlekts-setup)
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
| `OSSRH_USERNAME` | Sonatype OSSRH account username |
| `OSSRH_TOKEN` | Sonatype OSSRH account token |
| `GPG_PRIVATE_KEY` | `gpg --export-secret-keys --armor KEY_ID` |
| `GPG_PASSPHRASE` | Passphrase for the GPG key |

Maven Central requires GPG signing for all published artifacts.

---

## gradle.properties and build.gradle.kts Setup

Keep version in `gradle.properties` — not hardcoded in `build.gradle.kts`. CI version bumps are then a single `sed` line.

`gradle.properties`:
```properties
version=0.0.0
```

`build.gradle.kts` publishing block:
```kotlin
publishing {
  publications {
    create<MavenPublication>("maven") {
      from(components["java"])
      pom {
        name.set("Your Library")
        description.set("Your library description")
        url.set("https://github.com/your-org/your-lib")
        licenses {
          license {
            name.set("Apache-2.0")
            url.set("https://www.apache.org/licenses/LICENSE-2.0")
          }
        }
      }
    }
  }
  repositories {
    maven {
      name = "OSSRH"
      url = uri("https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/")
      credentials {
        username = System.getenv("OSSRH_USERNAME")
        password = System.getenv("OSSRH_TOKEN")
      }
    }
    maven {
      name = "GitHubPackages"
      url = uri("https://maven.pkg.github.com/${System.getenv("GITHUB_REPOSITORY")}")
      credentials {
        username = System.getenv("GITHUB_ACTOR")
        password = System.getenv("GITHUB_TOKEN")
      }
    }
    maven {
      name = "AzureArtifacts"
      url = uri("https://pkgs.dev.azure.com/YOUR_ORG/_packaging/YOUR_FEED/maven/v1")
      credentials {
        username = "az"
        password = System.getenv("SYSTEM_ACCESSTOKEN")
      }
    }
  }
}

signing {
  useInMemoryPgpKeys(
    System.getenv("GPG_PRIVATE_KEY"),
    System.getenv("GPG_PASSPHRASE")
  )
  sign(publishing.publications["maven"])
}
```

---

## Version Bump Commands

```bash
CURRENT=$(grep '^version=' gradle.properties | cut -d'=' -f2)

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

sed -i "s/^version=$CURRENT/version=$NEXT/" gradle.properties
```

---

## Publish Commands

**Public registry (Maven Central via OSSRH)**
```bash
./gradlew publishMavenPublicationToOSSRHRepository
```
Env: `OSSRH_USERNAME`, `OSSRH_TOKEN`, `GPG_PRIVATE_KEY`, `GPG_PASSPHRASE`

**GitHub Packages**
```bash
./gradlew publishMavenPublicationToGitHubPackagesRepository
```
Env: `GITHUB_TOKEN`, `GITHUB_ACTOR`, `GITHUB_REPOSITORY`

**Azure Artifacts**
```bash
./gradlew publishMavenPublicationToAzureArtifactsRepository
```
Env: `SYSTEM_ACCESSTOKEN`

Publish to all configured repositories at once:
```bash
./gradlew publish
```

---

## Release-Please Config

No native Kotlin/Gradle type. Use `simple` targeting `gradle.properties`:

```json
{
  "release-type": "simple",
  "extra-files": [
    {
      "type": "generic",
      "path": "gradle.properties",
      "search-for": "version=",
      "replace-with": "version="
    }
  ]
}
```

---

## semantic-release Config

Install: `npm install --save-dev @semantic-release/exec @semantic-release/changelog @semantic-release/git`

`prepareCmd`:
```bash
sed -i 's/^version=.*/version=${nextRelease.version}/' gradle.properties
```

`publishCmd`:
```bash
./gradlew publish
```

Version file for assets: `gradle.properties`
