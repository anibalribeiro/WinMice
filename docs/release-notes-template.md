## WinMice {{VERSION}}

### Changes

{{CHANGES}}

### Install

1. Download `WinMice-{{VERSION}}.dmg` below, open it, and drag **WinMice** to **Applications**.
2. Open WinMice from Applications.
3. Grant **Accessibility** when prompted (Settings → Permissions in the app).

A `WinMice-{{VERSION}}.zip` is also attached to this release if you prefer not to use a disk image.

Or with Homebrew:

```bash
brew tap anibalribeiro/winmice
brew trust anibalribeiro/winmice
brew install --cask winmice
```

### Notes

- This build is **Developer ID signed and notarized** by Apple.
- If you are upgrading from an ad-hoc (unsigned) build, remove every old WinMice row in **Accessibility** and re-enable `/Applications/WinMice.app` once.
- Source for this release: tag `v{{VERSION}}` on this repository.
