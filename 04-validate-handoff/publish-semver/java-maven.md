# Ecosystem: Java + Maven Central

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [pom.xml Setup](#pomxml-setup)
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

## pom.xml Setup

```xml
<project>
  <groupId>com.your-org</groupId>
  <artifactId>your-artifact</artifactId>
  <version>0.0.0</version>

  <distributionManagement>
    <snapshotRepository>
      <id>ossrh</id>
      <url>https://s01.oss.sonatype.org/content/repositories/snapshots</url>
    </snapshotRepository>
    <repository>
      <id>ossrh</id>
      <url>https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/</url>
    </repository>
  </distributionManagement>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-gpg-plugin</artifactId>
        <version>3.1.0</version>
        <executions>
          <execution>
            <id>sign-artifacts</id>
            <phase>verify</phase>
            <goals><goal>sign</goal></goals>
          </execution>
        </executions>
      </plugin>
      <plugin>
        <groupId>org.sonatype.plugins</groupId>
        <artifactId>nexus-staging-maven-plugin</artifactId>
        <version>1.6.13</version>
        <extensions>true</extensions>
        <configuration>
          <serverId>ossrh</serverId>
          <nexusUrl>https://s01.oss.sonatype.org/</nexusUrl>
          <autoReleaseAfterClose>true</autoReleaseAfterClose>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
```

Do not use Maven SNAPSHOT versions. Use `-pre.N` consistently.

---

## Version Bump Commands

```bash
CURRENT=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)

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

mvn versions:set -DnewVersion="$NEXT" -DgenerateBackupPoms=false
```

---

## Publish Commands

Import GPG key before publishing:
```bash
echo "$GPG_PRIVATE_KEY" | gpg --import --batch
```

**Public registry (Maven Central via OSSRH)**
```bash
mvn --no-transfer-progress deploy -Dgpg.passphrase=$GPG_PASSPHRASE
```
Env: `MAVEN_USERNAME=$OSSRH_USERNAME`, `MAVEN_PASSWORD=$OSSRH_TOKEN`

**GitHub Packages**
```bash
mvn --no-transfer-progress deploy \
  -DaltDeploymentRepository=github::https://maven.pkg.github.com/$GITHUB_REPOSITORY
```
Env: `GITHUB_TOKEN`

**Azure Artifacts**
```bash
# Auth via MavenAuthenticate task — see host-ado.md
mvn --no-transfer-progress deploy \
  -DaltDeploymentRepository=azure::https://pkgs.dev.azure.com/YOUR_ORG/_packaging/YOUR_FEED/maven/v1
```

---

## Release-Please Config

`release-type: maven` — native support, updates `pom.xml` directly.

---

## semantic-release Config

Install: `npm install --save-dev @semantic-release/exec @semantic-release/changelog @semantic-release/git`

`prepareCmd`:
```bash
mvn versions:set -DnewVersion=${nextRelease.version} -DgenerateBackupPoms=false
```

`publishCmd`:
```bash
mvn --no-transfer-progress deploy -Dgpg.passphrase=$GPG_PASSPHRASE
```

Version file for assets: `pom.xml`
