# AutoMalik

AutoMalik is a macOS karaoke and vocal-tuning studio. It captures or imports a track, isolates vocals from the instrumental, lets you sing along, applies pitch correction, and prepares a final mix.

## Features

- Import local audio, drag and drop a file, capture system audio, or download audio with `yt-dlp`.
- Separate a track into instrumental and vocal stems with Demucs.
- Preview source, instrumental, vocals, and recordings from the app.
- Save Step 1 packages after isolation and reload them later.
- Record vocals while the instrumental plays.
- Display pasted/imported lyrics during sing-along.
- Generate timestamped lyrics from audio with Apple Speech Recognition.
- Supports English, Hindi, and Hindi + English transcription modes.
- Auto-tune recorded vocals and export a final mix.

## Requirements

- macOS 13 or newer.
- Xcode with the macOS SDK.
- An Apple Development signing identity for permission-sensitive builds.
- Python 3 for Demucs setup.
- `yt-dlp` for URL downloads.

Optional setup:

```sh
brew install python yt-dlp ffmpeg
```

Demucs is installed by the app into:

```text
~/Library/Application Support/AutoMalik/demucs_env
```

The first separation can take a few minutes because the app creates a Python virtual environment and installs `demucs` plus `torchcodec`.

## Running Locally

The repo includes a local run script:

```sh
./Scripts/run-local.sh
```

The script builds a signed Debug app, quits any running AutoMalik instance, and opens the new build.

Equivalent manual build:

```sh
xcodebuild \
  -project AutoMalik.xcodeproj \
  -scheme AutoMalik \
  -configuration Debug \
  -derivedDataPath /tmp/AutoMalikTeamSignedDerivedData \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=UVD556ZKBG \
  CODE_SIGN_IDENTITY=8D1AF26CC49A3A27EDF925CD2FA82EFC2A318ABA \
  build
```

## Permissions

AutoMalik needs several macOS permissions depending on the workflow:

- Microphone: recording your vocal.
- Screen and System Audio Recording: capturing audio from other apps.
- Speech Recognition: generating lyrics from audio.
- User-selected file access: importing/exporting files and Step 1 packages.

For the most reliable permission behavior, run a consistently signed app bundle. Fresh ad-hoc builds can appear as different apps to macOS privacy services.

If permissions get stuck, remove AutoMalik from the relevant System Settings privacy list, add it again, quit AutoMalik, and relaunch the signed build.

## Workflow

1. Load a source track.
   Use file import, drag and drop, system audio capture, or a URL download.

2. Isolate stems.
   Click the isolation action to create `instrumental.wav` and `vocals.wav`.

3. Save Step 1.
   Save the captured source and isolated stems as a reloadable package.

4. Add or generate lyrics.
   Paste/import `.txt` or `.lrc` lyrics, or generate timestamped lyrics from the isolated vocal stem.

5. Sing along.
   Record vocals over the instrumental. The waveform and lyrics follow playback.

6. Auto-tune and mix.
   Tune the recorded vocal, balance levels, and export the final mix.

## Lyrics

Lyrics can be plain text or LRC-style timed lines:

```text
[00:12.50] पहली लाइन / first line
[00:18.20] next lyric line
```

Generated lyrics use Apple Speech Recognition. For best results:

- Isolate vocals first and generate from the `vocals.wav` stem.
- Use `Hindi + English` for Hinglish or mixed-language tracks.
- Expect transcription to be a draft, not a licensed lyric source.
- Review and edit generated lyrics before using them for a final sing-along.

Sung vocals are harder to recognize than spoken dictation. The app improves coverage by chunking audio with overlap, normalizing quiet chunks, keeping partial results, and merging English/Hindi passes, but noisy stems or heavy effects can still miss words.

## Project Outputs

Each session uses a project directory managed by the app. Typical generated files include:

- `captured.wav`
- `instrumental.wav`
- `vocals.wav`
- `lyrics.txt`
- raw and tuned vocal recordings
- final mix output

Step 1 packages contain the captured source, isolated stems, and a manifest so the isolation step can be restored later.

## Development Notes

- Main app state: `AutoMalik/App/AppState.swift`
- Source loading and Step 1 UI: `AutoMalik/Views/Cards/SourceCard.swift`
- Recording, lyrics, and speech-to-lyrics UI: `AutoMalik/Views/Cards/VocalsCard.swift`
- Permissions copy: `AutoMalik/Resources/Info.plist`
- App sandbox/signing entitlements: `AutoMalik/Resources/AutoMalik.entitlements`

Run tests:

```sh
xcodebuild test -project AutoMalik.xcodeproj -scheme AutoMalik
```
