# Cutting a WinMice release

Operator checklist for **Developer ID signed + notarized** releases.

## Prerequisites: Apple signing (once)

### 1. Register the App ID

In [Apple Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list):

1. Register a macOS App ID.
2. Bundle ID: `cz.anibalribeiro.winmice` (explicit).
3. Description: `WinMice`.

### 2. Create a Developer ID Application certificate

In [Certificates](https://developer.apple.com/account/resources/certificates/list):

1. Create **Developer ID Application**.
2. Follow CSR instructions (Keychain Access → Certificate Assistant).
3. Download the certificate and double-click to install in login keychain.
4. In Keychain Access, select the **private key** under “My Certificates”, then
   **Export…** as a `.p12` with a strong password. Export the identity **with its
   certificate chain** (Developer ID Application + Apple intermediates) — a
   leaf-only `.p12` fails later during `codesign` with opaque chain errors.
5. Keep the password in a password manager.

Base64 for GitHub:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

If you export the `.p12` yourself (e.g. via `openssl pkcs12`) rather than from
Keychain Access, use `-legacy` on OpenSSL 3: its default AES encryption
produces a `.p12` that `security import` rejects with `MAC verification
failed during PKCS12 import`.

### 3. Create an App Store Connect API key

In [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api):

1. Generate a key with **Developer** (or Admin) access.
2. Download the `.p8` once.
3. Record **Key ID**, **Issuer ID**, and your **Team ID** (Membership details on developer.apple.com).

`APPLE_TEAM_ID` is stored as a secret for operator verification and log
context. Notarization itself authenticates with the ASC API key
(`APPLE_API_KEY_ID` / `APPLE_API_ISSUER_ID` / `APPLE_API_KEY_P8`).

### 4. Store secrets on the WinMice repo

Single-line secrets can use interactive `gh secret set`. The `.p8` is a
**multi-line PEM** — pipe the file (do not paste into a one-line prompt):

```bash
base64 -i DeveloperIDApplication.p12 | gh secret set APPLE_DEVELOPER_ID_P12_BASE64 --repo anibalribeiro/WinMice
gh secret set APPLE_DEVELOPER_ID_P12_PASSWORD --repo anibalribeiro/WinMice
# paste password when prompted

gh secret set APPLE_TEAM_ID --repo anibalribeiro/WinMice
gh secret set APPLE_API_KEY_ID --repo anibalribeiro/WinMice
gh secret set APPLE_API_ISSUER_ID --repo anibalribeiro/WinMice

# Multi-line PEM — pipe the file:
gh secret set APPLE_API_KEY_P8 --repo anibalribeiro/WinMice < AuthKey_<KEY_ID>.p8
```

Verify names only:

```bash
gh secret list --repo anibalribeiro/WinMice
```

Required Apple secret names:

- `APPLE_DEVELOPER_ID_P12_BASE64`
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_KEY_P8`

## Prerequisites: Homebrew tap token

The Release workflow bumps `anibalribeiro/homebrew-winmice` using `HOMEBREW_TAP_TOKEN`.

### 1. Create a fine-grained PAT for the tap

In GitHub → **Settings** → **Developer settings** → **Fine-grained tokens** → **Generate new token**:

| Setting | Value |
| --- | --- |
| Resource owner | `anibalribeiro` |
| Repository access | Only `homebrew-winmice` |
| Permissions | **Contents** → Read and write |

### 2. Store the secret on WinMice

```bash
gh secret set HOMEBREW_TAP_TOKEN --repo anibalribeiro/WinMice
```

```bash
gh secret list --repo anibalribeiro/WinMice | grep HOMEBREW_TAP_TOKEN
```

## Prerequisites: Sparkle update signing

### 1. Generate the EdDSA keypair (once)

Sparkle's tools live in the resolved SPM artifacts after a build:

```bash
swift build -c release
"$(find .build/artifacts -type f -name generate_keys | head -n 1)"
```

This saves the private key in your login Keychain and prints the **public** key.
Put that public key in `SPARKLE_PUBLIC_ED_KEY` at the top of
`scripts/build-app.sh` — it is not a secret and ships in every copy of the app.

Export the private key and store it in your password manager next to the `.p12`
password:

```bash
"$(find .build/artifacts -type f -name generate_keys | head -n 1)" -x sparkle-private-key.txt
```

Losing both the Keychain copy and this export would normally end your ability
to ship updates, because `SUPublicEDKey` is baked into every installed copy.
Sparkle can fall back to Developer ID code-signing verification, but do not
rely on that.

### 2. Store the private key on the WinMice repo

```bash
gh secret set SPARKLE_ED_PRIVATE_KEY --repo anibalribeiro/WinMice < sparkle-private-key.txt
rm sparkle-private-key.txt
```

### 3. Mark the cask as self-updating (once)

In the `anibalribeiro/homebrew-winmice` repo, add `auto_updates true` to
`Casks/winmice.rb`, below the `app "WinMice.app"` line. Without it, `brew`
keeps believing the user is on the version it installed while Sparkle has moved
them forward, and `brew upgrade` will try to reinstall over a newer app.

`scripts/update-homebrew-cask.sh` only rewrites `version` and `sha256`, so this
is a one-time manual commit rather than something the pipeline does.

### 4. Restrict the cask to Apple Silicon (once)

The cask must declare `depends_on arch: :arm64` so `brew install --cask winmice`
refuses to install on an Intel Mac rather than installing an app that cannot launch.
This lives in the tap repo and is not touched by `update-homebrew-cask.sh`; add it
once, by hand, in `Casks/winmice.rb`.

## Dry-run before the first real tag

After secrets are set, prove the pipeline **without** publishing a GitHub
Release or bumping Homebrew:

1. GitHub → **Actions** → **Release** → **Run workflow**
2. Leave **publish** unchecked (default)
3. Set the version to one that has a `docs/changelog/<version>.md`. This is not
   optional any more: the appcast is generated from that file, so the default
   `0.0.0-notarize-dry-run` has no changelog and the run stops immediately.
4. Confirm **Notarize app** / **Notarize DMG** / verify steps succeed
5. Download the workflow artifacts and smoke-test Gatekeeper + Accessibility

Only then cut a real `vX.Y.Z` tag.

A manual run tags `manual-<version>` rather than `v<version>`. If you do check
**publish** on one, it is deliberately constrained so it cannot be mistaken for
a real release: the GitHub Release is created as a **prerelease**, so it never
becomes `releases/latest` and the appcast there is never served to installed
copies, and the Homebrew cask is left alone. Real releases come from tag pushes.

Do not hand-promote a `manual-*` release by un-checking **Set as pre-release**
in the GitHub UI. The moment you do, GitHub makes it `latest`, and every
installed copy's next Sparkle check downloads that test build from
`releases/latest/download/appcast.xml`. If you need to exercise the real
`releases/latest/download` path end to end, do it with a throwaway repo or
accept the blast radius knowingly — the workflow cannot stop a promotion made
directly in the UI. It does refuse to compound the mistake: a subsequent
re-run of that workflow for the same tag now checks whether the existing
release is still a prerelease before uploading, and fails instead of silently
keeping the promotion.

## Release checklist

1. Ensure the Apple, Homebrew, and Sparkle prerequisites above are set, and a
   dry-run has passed once.

2. Write `docs/changelog/<version>.md` as a plain bullet list. The release will
   not build without it — it feeds both the GitHub release notes and the
   in-app update dialog.

3. Ensure `main` is green locally:

   ```bash
   swift test
   ./scripts/test-build-signing-mode.sh
   ./scripts/test-generate-appcast.sh
   ./scripts/build-app.sh --version 1.1.0
   ./scripts/verify-bundle-metadata.sh dist/WinMice.app 1.1.0
   ./scripts/verify-sparkle-embedding.sh dist/WinMice.app
   ./scripts/render-release-notes.sh 1.1.0
   ```

   When `create-dmg` is installed (`brew install create-dmg`), also verify the
   disk image:

   ```bash
   ./scripts/package-dmg.sh 1.1.0
   ```

   The release workflow's `Test` step now runs `swift test` and the
   `test-*.sh` script suite itself, before any signing secret is imported —
   a tag on a commit that never went green fails there in seconds instead of
   producing a signed, notarized release. This local run is therefore a
   convenience that surfaces failures before you push a tag, not the only
   gate.

4. Commit/push any pending release notes or docs on `main`.

5. Tag and push:

   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```

6. Watch **Actions** → **Release**:

   ```bash
   gh run watch --repo anibalribeiro/WinMice
   ```

   Confirm steps **Notarize app**, **Verify notarized app**, **Notarize DMG**,
   and **Verify notarized DMG** succeed.

7. Confirm the GitHub Release includes both `WinMice-1.1.0.dmg` and `WinMice-1.1.0.zip`:

   ```bash
   gh release view v1.1.0 --repo anibalribeiro/WinMice
   ```

- Confirm the release carries `appcast.xml` and that the feed URL resolves:

  ```bash
  curl -sL https://github.com/anibalribeiro/WinMice/releases/latest/download/appcast.xml | xmllint --noout -
  ```

- Confirm an older installed copy sees the update: with the previous version in
  `/Applications`, choose **Check for Updates…** and confirm the dialog offers
  the new version with the changelog shown. Let it install, then confirm
  **without touching System Settings** that autoscroll and side buttons still
  work — the Developer ID identity is stable across releases, so the
  Accessibility grant should survive.

8. Confirm the tap cask was bumped; test install. The cask's `sha256` is the
   **DMG's** checksum (not the zip's) — that's what the workflow's Checksum
   step computes and what `brew` verifies:

   ```bash
   brew uninstall --cask winmice 2>/dev/null || true
   brew untap anibalribeiro/winmice 2>/dev/null || true
   brew tap anibalribeiro/winmice
   brew trust anibalribeiro/winmice
   brew install --cask winmice
   ```

9. Smoke-test Gatekeeper: open `/Applications/WinMice.app` **without** Open Anyway. Grant **Accessibility** when prompted.

   **Upgrading from ad-hoc (unsigned) releases:** the first Developer ID build
   is a new code identity. Remove every old WinMice row under
   **System Settings → Privacy & Security → Accessibility**, then re-enable
   `/Applications/WinMice.app`. Later notarized updates keep that identity.

## If notarization fails

`notarytool submit --wait` returns exit status 0 even when Apple reports
`Invalid` or `Rejected`. The Release scripts parse the JSON status and fail
the job; on failure they also print `notarytool log` into the workflow log.

If you need the log again from a laptop with the same API key:

```bash
xcrun notarytool log <submission-id> \
  --key AuthKey_<KEY_ID>.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
```

That prints the specific rejection (e.g. missing hardened runtime, missing
timestamp, disallowed entitlement). Fix the cause, then re-run — see below.

## Re-running after a failure

Every step from **Import Developer ID certificate** onward is safe to
re-run on the same tag after fixing the cause of a failure:

- Use **Re-run jobs** / **Re-run failed jobs** in the Actions UI for the tag
  workflow run (an empty commit will **not** re-trigger a tag-only workflow).
- `gh release upload ... --clobber` (Publish GitHub Release) overwrites the
  existing release assets rather than failing if the tag already has a
  release.
- The Homebrew tap bump (`update-homebrew-cask.sh` + `git commit`/`push`) is
  idempotent: if the cask is already at the target version/sha256, the diff
  is empty and the commit is skipped.
