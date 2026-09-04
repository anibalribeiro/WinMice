# WinMice

<img src="docs/icon.png" alt="WinMice icon" width="128" height="128">

A tiny native macOS menu-bar utility that brings Windows-style mouse behavior to Mac: vector scrolling on middle-click and configurable back/forward side buttons. Built on Swift and AppKit with no Electron and no interpreted runtime. Ships as a ~1.7 MB download, about 4 MB installed — the app's own binary is under 1 MB and the rest is the Sparkle framework that delivers updates — runs as a single lightweight process, and uses negligible CPU and memory while idle.

**[Product site](https://anibalribeiro.cz/Winmice/)** — screenshots and a quick demo loop.

The app appears in the macOS menu bar. Open **Settings…** (⌘,) from the menu bar icon to configure everything.

## Install

Download the latest release from [GitHub Releases](https://github.com/anibalribeiro/WinMice/releases/latest):

1. Download `WinMice-<version>.dmg`, open it, and drag **WinMice** to **Applications**.
2. Open WinMice from Applications.
3. Grant **Accessibility** when prompted (Settings → Permissions in the app).

A `WinMice-<version>.zip` is also attached to each release if you prefer not to use a disk image.

Or with Homebrew:

```bash
brew tap anibalribeiro/winmice
brew trust anibalribeiro/winmice
brew install --cask winmice
```

Release builds are **Developer ID signed and notarized** by Apple.

Upgrading from an older **ad-hoc** (unsigned) release: remove every WinMice
row under **System Settings → Privacy & Security → Accessibility**, then
re-enable `/Applications/WinMice.app` once. Later notarized updates keep that
Developer ID identity.

### Updates

WinMice asks, shortly after you first run it, whether it may check for updates.
If you agree it checks once a day, shows you what changed, and installs the
update only when you say so. You can change your mind any time in
**Settings → General → Updates**, or check on demand with **Check for
Updates…** in the menu bar menu.

Homebrew users can keep using `brew upgrade --cask winmice` instead.

Coming from 1.0.0, this one upgrade has to be done by hand — 1.0.0 has no
updater to tell it about anything newer. Every release after this one can
update itself.

## Use

Open **Settings…** from the menu bar to configure:

### Scrolling

- Middle-click to start scrolling; move the pointer away from the anchor to control direction and speed.
- **Hold to Scroll** — scrolling starts on middle-click and stops when you release it.
- **Hold to Start** — hold middle-click for a configurable delay (default 200 ms), then scroll until any mouse button is pressed.
- **Speed** — 25–300%, for anyone who wants the pointer to travel more or less before things move.
- **Reverse vertical** — drag down to scroll up instead of down.
- **Reverse horizontal** — drag right to scroll left instead of right.
- Choose indicator style (light/dark), size (28–48 px), and scroll mode in Settings.

The distance from the anchor maps to speed slightly faster than linearly, so the first few
millimetres stay precise while the edge of the screen still moves quickly.

### Back/forward buttons

Mouse side buttons (by default button 4 = back, button 5 = forward) can navigate system-wide. Configure in Settings:

- **Enable back/forward** toggle
- **Mapping** — choose **Set** next to Back or Forward, then press the mouse button you want.
  Whatever button you press is stored, except left, right, and middle: the first two keep Set and
  Cancel clickable, and the middle button belongs to autoscroll. Mapping a button already used by
  the other direction swaps the two.
- **Swipe gesture** (Safari, Finder, browsers) or **keyboard shortcut** (⌘[ / ⌘])
- **Trigger on press or release**

A mapped button is consumed whole, so apps that already handle buttons 4 and 5 themselves — most
browsers do — navigate once rather than twice.

### General

- **Launch at login** and **hide menu bar icon** (reopen the app to restore the icon).
- **Restore Defaults** puts every setting back to how it shipped.
- All settings are saved between launches.

A middle click is held back until WinMice knows what it was: a press that ends without scrolling is
handed straight on to the app, and one that scrolled is kept, so holding the middle button to read a
page no longer opens a tab under the pointer when you let go.

In `Hold to Start`, a left or right click that stops scrolling is still delivered to whatever is
under the pointer, so stopping on a button or a link will also activate it. Stop over empty space,
or with the middle button, to avoid this.

## Build

```
swift build -c release      # binary only
./scripts/build-app.sh      # bundles WinMice.app into dist/
./scripts/install-app.sh    # bundles, then replaces /Applications/WinMice.app and relaunches
```

`build-app.sh` invokes `scripts/make-icons.swift` to render the iconset, then `iconutil` to pack it
into `WinMice.icns`, so the icon is generated at build time rather than checked in.

macOS may prompt for **Accessibility** permission. That is the only Privacy grant WinMice needs —
a modifying event tap is authorized via Accessibility on modern macOS.

If Settings → Permissions still shows Accessibility as missing after you flipped the switch:

1. Open `System Settings → Privacy & Security → Accessibility`
2. Remove **every** WinMice entry (including greyed-out ones)
3. Use **Request Access** in WinMice (or + add `/Applications/WinMice.app`)
4. Turn the switch on, then quit and reopen WinMice from `/Applications`

Local developer builds are ad-hoc signed, so a reinstall of a local build can look like a new app to macOS — re-grant Accessibility if scrolling stops after replacing a local build. After you have switched to notarized GitHub/Homebrew releases, those builds keep a stable Developer ID identity across versions.

Swipe navigation posts a clean-room trackpad-style gesture (MIT). If an app ignores swipes, switch **Buttons → Navigation method** to Keyboard.

The menu-bar icon uses a custom template glyph matching the classic middle-button scroll motif.

## License

WinMice is MIT (`LICENSE`), including VectorScroll-derived code. See `NOTICES.md` for notices.

## Support

If WinMice is useful, you can [buy me a coffee](https://paypal.me/anibalccribeiro).

## Credits

- [VectorScroll](https://github.com/Sowyu/VectorScroll) by sowyu — original vector scrolling utility (MIT)
