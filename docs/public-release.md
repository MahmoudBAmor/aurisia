# Public repository and release checklist

This checklist separates publishing source code from distributing a signed
Android application. A clean public repository does not imply that a binary is
ready for Google Play.

## First public Git push

1. Review `README.md`, `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`,
   `THIRD_PARTY_NOTICES.md`, and `LICENSE`.
2. Replace or confirm the maintainer identity in `NOTICE` and `pyproject.toml`.
3. Do not add `recordings/`, `transcript.json`, `console.txt`, `context.txt`,
   model weights, native runtimes, APKs, app bundles, or signing files.
4. Stage the intended source with `git add .`.
5. Run `python tools/check_public_repo.py`; it audits every tracked file,
   including ignored files that may have been tracked in earlier history.
6. Inspect `git diff --cached --stat` and `git diff --cached` before committing.
7. Run the Python and Flutter checks documented in `CONTRIBUTING.md`.
8. Enable GitHub private vulnerability reporting and branch protection after
   creating the remote repository.

Never use `git add --force` for a model, recording, transcript, generated build,
or secret. If a private file was already committed, removing it from the latest
tree is insufficient: rewrite the unpublished history or rotate the exposed
credential before pushing.

## Public beta APK

The current local APK is intentionally a self-contained engineering build. It
is approximately 1.8 GB and falls back to Android's debug signing key. It is
suitable only for controlled testing.

Before distributing a public beta:

- choose the final Android application ID;
- generate and securely back up a dedicated upload keystore;
- keep `key.properties` and the keystore outside Git;
- disable `AURISIA_ASR_DIAGNOSTICS`;
- publish a final privacy-policy URL;
- verify every packaged model and dependency notice;
- test install, update, low-storage, permission denial, and offline startup; and
- generate an Android App Bundle rather than uploading the current monolithic
  APK to Google Play.

Start from `mobile/android/key.properties.example`. A store candidate must set
the signing guard before building:

```powershell
$env:AURISIA_REQUIRE_RELEASE_SIGNING = "true"
Set-Location .\mobile
flutter build appbundle --release --target-platform android-arm64
```

The build stops during Gradle configuration if the private signing properties
are missing or incomplete. Without that environment variable, local release
APKs deliberately retain the debug-key fallback used for USB testing.

## Google Play packaging

Keep the application shell and model interfaces unchanged. Move large weights
to independently versioned Play Asset Delivery packs:

- the full Tunisian Vosk model;
- the formal-Arabic MGB-2 Vosk model; and
- the shared Qwen final recognizer.

The Android adapter must resolve an installed pack through the existing model
manifest interface. Presentation and domain layers must not depend on Play
Asset Delivery. Prefer fast-follow for the default Tunisian pack and on-demand
delivery for optional formal-Arabic refinement, while keeping all recognition
offline after the selected packs are installed.
