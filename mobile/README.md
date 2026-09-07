# Aurisia Mobile

Aurisia Mobile is the Android-first, offline transcription client. The same
Flutter source is retained for a later iOS build. Its first milestone is a
simple Arabic/RTL transcript in which each session-local speaker has a stable
number and a high-contrast color.

## Current mobile slice

- Android ARM64 Flutter host with no cloud dependency; the domain and adapter
  boundaries remain portable for a later iOS package.
- 16 kHz mono PCM16 microphone capture.
- Incremental Silero VAD plus a persistent Vosk decoder. Changed partial text
  reaches the screen while the person is still speaking; the profile-specific
  hard cap finalizes uninterrupted speech without buffering it indefinitely.
- A bounded raw-PCM history restores 250 ms of real microphone context around
  Tunisian VAD turns. Formal-Arabic turns retain 750 ms before the detected
  start and 450 ms after the detected end. This captures weak opening and
  closing phonemes without delaying VAD finalization.
- A model-neutral hypothesis policy retains a repeated, confident partial when
  a decoder final is an unrelated lower-confidence rewrite. Each profile can
  keep that conservative refinement gate or explicitly designate its final
  model as authoritative.
- The full Tunisian STT Kaldi graph through Vosk is the Android default. The
  high-accuracy graph replaces its simplified Android sibling while preserving
  the same streaming service contract, CPU-only runtime, and Arabic-script
  display normalizer. The Tunisian profile does not run a generative second
  pass: field diagnostics showed that Qwen degraded its dialect and French
  code-switching while increasing latency.
- The formal-Arabic profile refines completed turns with Qwen3-ASR 0.6B INT8. It runs
  through the pinned sherpa-onnx CPU runtime with the per-stream language hint
  set to `Arabic`; transcript-content hotwords remain empty because field
  testing showed prompt copying and language drift. MGB-2/Vosk provides
  immediate text. A profile-owned Fusha display lexicon fixes a small set of
  recurrent decoder confusions. The refinement gate accepts plausible recovery
  of a cropped multiword phrase, but rejects one-word completions, excessive
  expansion, and repeated-token generative output.
- The optional formal-speech preprocessor detects unusually long, stable phonation (for
  example a deliberately prolonged vowel), retains its onset and ending, and
  shortens only the repetitive middle with a crossfade. Live text and speaker
  attribution continue to use the untouched recording. Qwen3-ASR also receives
  the original waveform because the field trace recovered a three-second
  prolonged vowel correctly. A corrupt formal hypothesis containing a mixed
  Arabic/Latin token is withheld until refinement; legitimate Tunisian
  code-switching remains untouched.
- The older Audar and Omnilingual adapters remain replaceable comparison
  implementations, but their weights are excluded from this Android APK.
- 3D-Speaker ERes2Net embeddings and bounded online speaker clustering. New
  speaker candidates survive A-B-A-B alternation, expire when stale, and need
  three coherent turns before receiving a color. Temporal switch hysteresis
  retains the current speaker when two known voices score too similarly.
- CPU-heavy Android ASR runs on dedicated native or Dart worker isolates;
  speaker extraction and Qwen3 decoding never run on the UI isolate. Final-ASR
  work has a latest-wins backlog: one inference may run and only the newest
  waiting turn survives, so recognition delay cannot grow with the session.
- A light, high-contrast interface with 24 px transcript text, enlarged touch
  targets, subtly tinted cards, and six WCAG-AA speaker colors. Speaker numbers
  keep identity understandable independently of color perception.
- A versioned native model-pack installer that streams large assets to private
  application storage and verifies their size and SHA-256 checksum.

The full Tunisian pack ships as a checksum-pinned 542 MB archive and occupies
about 1.50 GB after extraction with VAD and speaker models. Qwen3 contributes
about 987 MB bundled and installed; MGB-2 contributes about 375 MB bundled and
740 MB installed. Allow at least 8 GB free for the APK, installed profiles, and
Android update staging. Qwen3 is materialized only when the formal profile is
selected; Tunisian-only use therefore avoids its RAM and CPU cost.

Field-comparison builds may opt into non-persistent transcript diagnostics
with `--dart-define=AURISIA_ASR_DIAGNOSTICS=true`. Each completed turn then
prints the Vosk baseline, final-ASR refinement, selected text, decision reason,
and audio duration to Android logcat. It also prints speaker decision scores
and reasons, but never audio or embeddings. Normal builds compile these
branches out; diagnostics must not be enabled in an APK distributed to users.

The available 1B Omnilingual INT8 ASR file is about 1.03 GB by itself. It is not
the default: the CTC runtime has no Tunisian language-conditioning input, and
package size alone does not prove a Tunisian accuracy gain.

Speaker attribution currently means *who sounds like the same person during
this recording session*. It does not know real names, persist a voiceprint, or
separate two people who speak at exactly the same time. Those are intentionally
separate capabilities behind the speaker port.

## Prepare Windows 11

Install current Flutter and Android Studio, including the Android SDK and an
Android SDK Platform matching the Flutter project's compile SDK. Run:

```powershell
flutter doctor -v
flutter doctor --android-licenses
```

Connect an Android phone with Developer options and USB debugging enabled,
then confirm Flutter can see it:

```powershell
flutter devices
```

## Install the offline models

From the repository root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& .\tools\install-mobile-models.ps1
```

The installer prepares the full Tunisian Vosk, formal-Arabic Vosk, and Qwen3
packs. It reuses verified models already under
`models\` when possible, otherwise it downloads pinned artifacts. It refuses
files with an unexpected size or checksum. Large binary assets are excluded
from Git.

## Run on Android

Because this repository is stored in OneDrive on the reference Windows PC,
configure the generated `build` directory as a junction to local application
storage once. This keeps large, disposable model-pack intermediates out of the
sync engine and prevents Gradle `AccessDeniedException` cleanup failures:

```powershell
Set-Location .\mobile
Set-ExecutionPolicy -Scope Process Bypass
& .\tool\configure-windows-build.ps1
```

The script removes only generated `mobile\build` output. Source code and model
assets are not moved. It is idempotent and reports the existing local target
when it has already been configured. `flutter clean` can remove the junction;
if you use it, run the configuration script again before the next build.

```powershell
Set-Location .\mobile
flutter pub get
flutter run
```

The first Android launch shows `نحضّر في نماذج النسخ...` while the full
Tunisian archive is copied, extracted, and its complete model tree is verified. Grant
microphone permission, press the microphone button, and speak Tunisian Arabic.
Everything after installation runs locally without Internet.

The Tunisian profile closes a turn after about 500 ms of detected silence; the
formal-Arabic profile uses about 550 ms to tolerate rhetorical pauses. Changed partial
text remains visible during that window. The additional context reduces phrase
fragmentation, false speaker changes on short fragments, and loss of
code-switch context. Selection diagnostics record confidence decisions and
latency, but never transcript text or microphone audio.

Use the language button in the header while recording is stopped to choose:

- `تونسي` for Tunisian conversation and French code-switching;
- `عربية فصحى` for formal Arabic. Its first selection
  takes longer because Android verifies the shared Qwen3 weights and the MGB-2
  archive, then extracts the Vosk model.

For UI work without loading inference models:

```powershell
flutter run --dart-define=AURISIA_DEMO=true
```

Build an ARM64 development APK for a modern physical phone:

```powershell
flutter build apk --release --target-platform android-arm64
```

On the reference OneDrive workstation, launch that verified APK without asking
`flutter run` to rebuild and recopy the 1 GB artifact:

```powershell
$apk = "$env:LOCALAPPDATA\Aurisia\flutter-build\app\outputs\flutter-apk\app-release.apk"
$device = "replace-with-flutter-device-id"
flutter run --release -d $device --use-application-binary=$apk
```

The release build fails explicitly if Flutter has not staged `libapp.so`; an
installable-but-crashing APK can therefore no longer pass the build step.

The Gradle file signs local proof-of-concept releases with the debug key only
when `mobile/android/key.properties` is absent. Copy
`mobile/android/key.properties.example`, keep the real keystore outside Git,
and set `AURISIA_REQUIRE_RELEASE_SIGNING=true` for a store candidate; Gradle
then refuses an unsigned or debug-signed store build. The self-contained APK is
intentionally too large for the Google Play base-module limit. A store release
should keep the same model-pack interface and deliver the weights with Play
Asset Delivery.

## Verify

```powershell
Set-Location .\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

The interfaces remain suitable for iOS, but the current live model pack and
native installer are Android-only. Producing and signing the later iOS adapter
will require macOS, Xcode, and an Apple developer setup.

## Replace a model

Model choice is isolated from the screen and recording flow. Streaming text is
published first; completed speech is sent concurrently to speaker attribution
and the optional final recognizer, then updates the same transcript event:

```text
                         ┌─> SpeechSegmenter ─> SpeechTurn ─┬─> Speaker engine ─┐
Microphone ─> PCM frames ┤                                  └─> Final ASR ──────┤─> event upsert ─> UI
                         └─> Streaming ASR ─────> partial/final text ──────────┘
```

Add a versioned manifest under `assets/model_packs`, implement or configure the
matching engine adapter, and change only the application composition. Do not
put runtime-specific tensors, tokens, or model conditions in presentation code.
