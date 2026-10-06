# Make Intro

A macOS app that adds a short intro sequence to a video (e.g. a screencast): a still image with a title, a background and an optional logo. The poster is drawn with CoreText and the video is composed with AVFoundation – no external tools like `ffmpeg` are required.

## Features

- **Workflow:** enter a title, pick a preset, choose a video or drag it into the window (only video files are accepted), click “Create Intro…” and choose a destination folder. Afterwards the folder opens in the Finder, and title and video are reset for the next video.
- **Live preview** of the poster in the main window.
- **Presets** (menu “Presets…” / ⌘, or “Edit…” next to the preset picker): create, duplicate, rename, delete. Each preset configures:
  - Background: color or image (with darkening)
  - Logo: image, corner, size, margin
  - Title: font and style, size, color, position, shadow
  - Intro: duration, fade in from black, cross-fade into the video
  - Output: codec (H.264/HEVC), save poster as PNG, create subfolder
- Sizes and margins are relative to the video size, so the result looks the same at any resolution.
- Videos without an audio track and rotated videos are supported.
- Localized in English and German (follows the system language).

Output: `<destination>/<video name>/<video name>.mp4` and `<video name>.png` (without the subfolder if disabled in the preset).

## Installation

Download the ZIP from the [latest release](https://github.com/ntzrbtr/make_intro/releases/latest), unzip it and move **Make Intro.app** to your Applications folder. The app is not notarized by Apple, so macOS blocks the first launch: open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway** (or run `xattr -dr com.apple.quarantine "/Applications/Make Intro.app"`).

## Requirements

- macOS 15 or later (Apple Silicon or Intel)
- To build: Xcode (for the Swift compiler and `xcstringstool`). With the Command Line Tools alone, the app is built in English only.

## Building

```bash
./app/build.sh            # builds build/Make Intro.app
./app/build.sh --install  # also copies it to ~/Applications
```

The app is built as a universal binary (Apple Silicon and Intel); set `ARCHS=arm64` for a faster single-architecture build. The version is taken from `$VERSION` or the latest `v*` tag, the build number is the number of commits. An app you build yourself starts without a Gatekeeper warning.

## Releasing

Releases are built by GitHub Actions (`.github/workflows/release.yml`):

```bash
git tag v1.2.0
git push origin v1.2.0
```

The workflow builds the universal app, checks that all strings are translated and the String Catalog is committed, and publishes a GitHub release with `Make-Intro-1.2.0.zip`. Running the workflow manually (“Run workflow”) only builds the app and keeps the ZIP as a workflow artifact.

## Details

**Images:** The app ships without any images. Background image and logo are chosen in the preset; they are copied to `~/Library/Application Support/Make Intro/Assets/` (content-addressed, `<checksum>/<file name>`), so the originals can be moved or deleted. Identical images are stored only once; copies no longer in use are removed when a preset is deleted and on app launch.

**Fonts:** All fonts installed on the Mac are available. If a preset's font or image is missing (e.g. on another Mac), the app points this out and blocks the export.

**Localization:** The source language in the code is English. Translations live in the String Catalog `app/Localizable.xcstrings`, which can also be edited in Xcode. `build.sh` syncs it with the strings in the code on every build, warns about missing translations and compiles it into the app. To add a language, add its code to `LANGUAGES` in `build.sh` and to `CFBundleLocalizations`, then add the translations to the catalog.

**Icon:** The app icon is drawn at build time by `app/AppIcon.swift`.

## License

Released under the [MIT License](LICENSE). © 2026 Thomas Off – [www.netzarbeiter.info](https://www.netzarbeiter.info)
