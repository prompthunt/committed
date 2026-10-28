# 09: Sign Windows builds with Azure Artifact Signing

**What to build:** Release builds of the Windows app and installer are Authenticode-signed with Azure Artifact Signing from GitHub Actions using a short-lived OIDC login, so no certificate or password is stored in GitHub. Each signing job requires a reviewer's approval. The release refuses to publish unsigned Windows assets.

**Needs a human first:** someone has to create the Azure Artifact Signing account, pass Microsoft's identity validation (likely as Prompt Hunt), and create the certificate profile. Confirm current eligibility before starting.

**Blocked by:** 08

**Status:** needs-human

- [ ] The released app and installer carry a valid Authenticode signature under the validated publisher name
- [ ] Signing runs in CI through OIDC with no stored certificate or password, behind an approval-required environment
- [ ] The release process fails if any Windows asset is unsigned
- [ ] Setup steps are documented so the signing identity can be renewed
