# Privacy

Effective date: 7 September 2026

Aurisia is an experimental, offline transcription project. This document
describes the behavior of the source code in this repository. A distributor
who modifies the application or adds network services must publish a policy
that describes those changes.

## Mobile application

Aurisia requests microphone access only when the user starts transcription.
In the standard build:

- microphone audio is processed locally in memory;
- audio, transcripts, and speaker embeddings are not sent to Aurisia servers;
- microphone audio and speaker embeddings are not persisted;
- the visible transcript remains in application memory until the user clears
  it or the application process ends; and
- speaker numbers represent similarity within the current session. They are
  not names, identities, or persistent voiceprints.

The current Android application does not request the Internet permission.
Installing model files with the developer script is a separate, explicit
development operation that downloads checksum-pinned artifacts.

## Diagnostics

Normal builds do not log transcript content. A developer can explicitly build
with `AURISIA_ASR_DIAGNOSTICS=true`; that diagnostic build writes recognition
text and timing decisions to the Android system log. It still does not log
microphone audio or speaker embeddings. Diagnostic builds are for controlled
testing and must not be distributed as production releases.

## Desktop evaluation recordings

The desktop evaluation command can save WAV recordings and recognition reports
under the ignored local `recordings/` directory. It displays a notice and
requires explicit confirmation before recording. These files remain under the
operator's control and are never uploaded by Aurisia.

## Data collection and sharing

The project currently operates no analytics, advertising, telemetry, account,
or cloud transcription service. Aurisia therefore does not collect or share
personal data through an Aurisia-operated backend. Operating systems, app
stores, device manufacturers, and third-party distribution channels may
process their own diagnostics independently of Aurisia.

## Questions and changes

Privacy questions may be raised through the repository issue tracker. Do not
attach private recordings, transcripts, credentials, or identifying data to a
public issue. Report sensitive matters using the process in `SECURITY.md`.

Material changes to data handling must update this policy before release.
