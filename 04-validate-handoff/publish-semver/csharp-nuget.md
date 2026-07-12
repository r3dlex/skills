# Ecosystem: C# + NuGet

## Table of Contents
1. [Secrets Needed](#secrets-needed)
2. [.csproj Setup](#csproj-setup)
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
| `NUGET_API_KEY` | nuget.org → Account → API Keys |

---

## .csproj Setup

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <PackageId>YourOrg.YourPackage</PackageId>
    <Version>0.0.0</Version>
    <Authors>Your Name</Authors>
    <Description>Your package description</Description>
    <RepositoryUrl>https://github.com/your-org/your-package</RepositoryUrl>
    <PackageLicenseExpression>Apache-2.0</PackageLicenseExpression>
    <GeneratePackageOnBuild>false</GeneratePackageOnBuild>
  </PropertyGroup>
</Project>
```

Set `GeneratePackageOnBuild` to `false`. Pack explicitly in CI only.

---

## Version Bump Commands

```bash
CSPROJ=$(find src -name "*.csproj" | head -1)
CURRENT=$(grep -oP '(?<=<Version>)[^<]+' "$CSPROJ")

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

sed -i "s|<Version>$CURRENT</Version>|<Version>$NEXT</Version>|" "$CSPROJ"
dotnet build --configuration Release
dotnet pack --configuration Release --no-build -o ./nupkg
```

---

## Publish Commands

**Public registry (nuget.org)**
```bash
dotnet nuget push ./nupkg/*.nupkg \
  --api-key $NUGET_API_KEY \
  --source https://api.nuget.org/v3/index.json \
  --skip-duplicate
```

**GitHub Packages**
```bash
dotnet nuget push ./nupkg/*.nupkg \
  --api-key $GITHUB_TOKEN \
  --source "https://nuget.pkg.github.com/$GITHUB_REPOSITORY_OWNER/index.json" \
  --skip-duplicate
```

**Azure Artifacts**
```bash
# Auth via NuGetAuthenticate task — see host-ado.md
dotnet nuget push ./nupkg/*.nupkg \
  --source "https://pkgs.dev.azure.com/YOUR_ORG/_packaging/YOUR_FEED/nuget/v3/index.json" \
  --skip-duplicate
```

---

## Release-Please Config

No native .NET type. Use `simple` with an XML xpath selector:

```json
{
  "release-type": "simple",
  "extra-files": [
    {
      "type": "xml",
      "path": "src/YourPackage/YourPackage.csproj",
      "xpath": "//Project/PropertyGroup/Version"
    }
  ]
}
```

---

## semantic-release Config

Install: `npm install --save-dev @semantic-release/exec @semantic-release/changelog @semantic-release/git`

`prepareCmd`:
```bash
sed -i 's|<Version>.*</Version>|<Version>${nextRelease.version}</Version>|' src/YourPackage/YourPackage.csproj && dotnet pack --configuration Release -o ./nupkg
```

`publishCmd`:
```bash
dotnet nuget push ./nupkg/*.nupkg --api-key $NUGET_API_KEY --source https://api.nuget.org/v3/index.json --skip-duplicate
```

Version file for assets: `src/YourPackage/YourPackage.csproj`
