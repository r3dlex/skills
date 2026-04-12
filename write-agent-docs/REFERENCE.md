# Progressive Disclosure Docs – Reference

## Table of Contents
1. [Layer 1 Examples](#layer-1-examples)
2. [Layer 2 Examples](#layer-2-examples)
3. [Splitting Examples](#splitting-examples)
4. [Audit Output Examples](#audit-output-examples)

---

## Layer 1 Examples

**Bad – too long, no trigger condition**
```yaml
description: >
  This skill helps you work with cloud deployments across multiple providers.
  It was built to support our DevOps workflows and covers AWS, GCP, and Azure.
  It's useful when you're deploying services, managing infrastructure, or
  provisioning resources in any of the supported clouds.
```

**Good – action + trigger**
```yaml
description: >
  Deploy services to AWS, GCP, or Azure using provider-specific runbooks.
  Use when the user mentions deploying, provisioning, or managing cloud
  infrastructure, or references a cloud provider by name.
```

---

## Layer 2 Examples

**Bad – Layer 2 body with Layer 3 content inline**
```md
# Cloud Deploy

## Overview
Cloud deployments involve coordinating compute, networking, and storage
resources across a provider's API surface. Each provider has a different
CLI and authentication model...

## AWS Setup
First, configure your credentials:
\`\`\`bash
aws configure
# Enter: Access Key ID
# Enter: Secret Access Key
# Enter: Region (e.g. eu-central-1)
# Enter: Output format (json)
\`\`\`
Then verify with:
\`\`\`bash
aws sts get-caller-identity
\`\`\`
...
[continues for GCP, Azure, each with full setup]
```

**Good – Layer 2 body that routes to Layer 3**
```md
# Cloud Deploy

## Quick Start
1. Pick your provider: AWS, GCP, or Azure.
2. Read the provider runbook: [aws.md](references/aws.md), [gcp.md](references/gcp.md), [azure.md](references/azure.md).
3. Run the deploy command from the runbook.

## When to read the reference files
- Setting up credentials for the first time → provider runbook, "Setup" section.
- Debugging a failed deploy → provider runbook, "Troubleshooting" section.
- Comparing provider costs → [cost-comparison.md](references/cost-comparison.md).
```

---

## Splitting Examples

**Before – one oversized SKILL.md covering two domains**
```
billing/SKILL.md   (180 lines)
  - Stripe webhook handling
  - Invoice generation
  - Auth token validation
  - Permission scopes
```

**After – split by domain**
```
billing/
├── SKILL.md          (50 lines – workflow + routing)
├── references/
│   ├── stripe.md     (Stripe webhooks + invoices)
│   └── auth.md       (token validation + scopes)
```

SKILL.md body after split:
```md
## Quick Start
Handle a billing event or auth check. Pick the relevant reference:
- Stripe webhooks or invoices → [stripe.md](references/stripe.md)
- Token validation or permissions → [auth.md](references/auth.md)
```

---

## Audit Output Examples

**Triage table output**
```
File                              | Lines | Issues
----------------------------------|-------|----------------------------------------
onboarding/SKILL.md               | 230   | Over limit (split needed), no ToC
deploy/AGENTS.md                  | 88    | "Background" section (remove), OK size
auth/SKILL.md                      | 40    | Vague ref to "details.md" (rename)
billing/SKILL.md                   | 55    | Clean
```

**After refactor – onboarding/SKILL.md**
```
onboarding/
├── SKILL.md           (62 lines)
└── references/
    ├── new-hire.md    (previous lines 80–160)
    └── offboarding.md (previous lines 161–230)
```
