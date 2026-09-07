# Security policy

## Supported versions

Aurisia is currently an experimental `0.1.x` project. Security fixes are made
on the main development branch; no long-term support promise exists yet.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting feature when it is enabled for
the repository. Otherwise, contact the maintainer through a private channel
listed on the maintainer's GitHub profile. Do not disclose a suspected
vulnerability in a public issue before a fix is available.

Include the affected version, platform, reproduction steps, impact, and the
smallest safe diagnostic sample. Never include real microphone recordings,
transcripts, signing keys, access tokens, or another person's personal data.

## Security boundaries

The project treats the following as security-sensitive:

- Android signing and upload keys;
- microphone permission and audio retention;
- model and runtime download provenance;
- archive extraction paths and checksums;
- local loopback service exposure; and
- diagnostics that can contain transcript text.

Model installers pin expected sizes and SHA-256 hashes. A new model or runtime
must preserve those checks and document its source and license.
