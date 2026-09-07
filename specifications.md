# Aurisia

> **Making the Invisible Visible**

Author: Mahmoud Ben Amor

Version: 0.1 (MVP)

---

# Vision

Aurisia is an AI-powered perception platform whose mission is to augment human senses.

The first product focuses on helping people with profound hearing loss by transforming the surrounding soundscape into an intuitive visual interface.

Instead of attempting to restore hearing, Aurisia creates a completely new sensory experience.

The system listens to the world, understands what is happening, determines where sounds originate, evaluates their importance, and renders them spatially inside the user's field of view.

Aurisia is not a speech-to-text application.

Aurisia is a real-time perception engine.

---

# Long Term Vision

Imagine walking through a city.

Instead of hearing sounds, the user naturally sees them.

Example:

                           👤 Ahmed

                    "السلام عليكم"

🚍 ≈≈≈≈                               🚗

               🚨

                               🔔

The user instantly understands:

- Someone is speaking.
- A bus is approaching from the left.
- A car is moving on the right.
- A doorbell rang.
- An alarm is active.

No audio is required.

---

# Primary Objectives

The platform should eventually detect:

- Speech
- Speaker position
- Speaker identity (optional)
- Environmental sounds
- Vehicle sounds
- Emergency sounds
- Movement
- Sound direction
- Distance estimation
- Sound priority

Future versions should support:

- AR glasses
- Android
- Offline AI
- Edge computing
- Multiple languages
- Downloadable language packs

---

# MVP Scope

The first MVP runs entirely on a desktop computer.

No AR hardware.

No VR hardware.

No Internet required.

No cloud inference.

The objective is validating the perception engine.

---

# User Experience

Example:

                         👤 Sarah

             "Can you hear me?"

🚍

≈≈≈≈

                         🚗

                              🔔

---

# Architecture

                 Microphone
                      │
                      ▼
          Audio Capture Engine
                      │
                      ▼
        Voice Activity Detection
                      │
        ┌─────────────┴─────────────┐
        ▼                           ▼
 Speech Recognition         Sound Classification
        │                           │
        └─────────────┬─────────────┘
                      ▼
            Direction Estimation
                      ▼
             Rendering Engine
                      ▼
           Transparent Desktop HUD

Every module must be replaceable.

No module should depend on implementation details of another.

---

# Phase 1

Desktop Prototype

Features

✓ Live microphone

✓ Offline speech recognition

✓ Environmental sound detection

✓ Transparent overlay

✓ Real-time rendering

✓ Configurable models

---

# Folder Structure

Aurisia/

    audio/
    speech/
    vad/
    sound_detection/
    localization/
    rendering/
    ui/
    models/
    config/
    assets/
    tests/
    docs/

    main.py

    requirements.txt

---

# Module 1

Audio Engine

Responsibilities

- Microphone capture
- Circular audio buffer
- Continuous streaming
- Device selection
- Audio normalization

Suggested libraries

sounddevice

or

PyAudio

---

# Module 2

Voice Activity Detection

Purpose

Only run speech recognition when someone speaks.

Suggested model

Silero VAD

Output

{
    speech: true,
    start_time: ...
}

---

# Module 3

Speech Recognition

Requirements

Offline

Streaming

Replaceable engine

Supported engines

Whisper.cpp

Future:

- SenseVoice
- Moonshine
- NVIDIA Parakeet
- Canary
- Faster Whisper

Output

{
    text,
    confidence,
    timestamp
}

---

# Module 4

Environmental Sound Detection

Recognize sounds such as

Vehicles

- Bus
- Car
- Motorcycle
- Bicycle

Human

- Footsteps
- Knock
- Door
- Doorbell
- Applause

Emergency

- Alarm
- Siren
- Smoke detector

Animals

- Dog
- Cat

Other

- Glass breaking
- Baby crying

Suggested models

YAMNet

PANNs

BEATs

Output

{
    sound,
    confidence
}

---

# Module 5

Direction Estimation

MVP

Fake direction.

Random:

LEFT

CENTER

RIGHT

Purpose

Validate rendering.

Future

Real localization using

- microphone array
- beamforming
- GCC-PHAT
- DOA estimation

Future output

{
    angle,
    distance,
    confidence
}

---

# Module 6

Rendering Engine

Technology

PySide6

Requirements

Transparent window

Always on top

Click-through mode

60 FPS

Animated icons

Fade animations

Smooth transitions

---

# Visual Language

Speech

👤

Displayed near the detected speaker.

Vehicle

🚍

Car

🚗

Motorcycle

🏍

Doorbell

🔔

Alarm

🚨

Dog

🐕

Baby

👶

Glass breaking

🪟

---

# Color Convention

Green

Conversation

Blue

Information

Yellow

Attention

Orange

Vehicle

Red

Danger

---

# Animation

Approaching

🚍 >>>>

Leaving

<<<< 🚍

Loud sounds

≈≈≈≈≈

Pulse amplitude proportional to loudness.

---

# Configuration

The application must support

config.yaml

Example

speech_engine:

    whisper

sound_engine:

    yamnet

language:

    ar

theme:

    dark

fps:

    60

---

# Future Language Packs

Each language should be installable independently.

Examples

Arabic

French

English

Spanish

German

Tunisian Arabic

Egyptian Arabic

No recompilation required.

---

# Future Sound Packs

Allow downloadable classifiers.

Example

Industrial

Medical

Military

Construction

Wildlife

Urban

---

# Accessibility Rules

Never overload the user.

Do NOT display every detected sound.

Instead

Prioritize

Emergency

↓

Human speech

↓

Vehicles

↓

Relevant notifications

↓

Everything else

The user must always stay focused.

---

# Non Functional Requirements

Latency

Target

<300ms

Memory

<2GB

Offline

Mandatory

Internet

Optional only

Cross-platform

Windows first

Linux later

Android later

---

# Coding Guidelines

Python 3.12

Type hints everywhere.

PEP8.

Dependency injection.

Interfaces for every AI engine.

No global state.

Logging everywhere.

Configuration-driven.

Unit tests.

Modular architecture.

Every AI backend must be replaceable without changing business logic.

---

# Interfaces

Create abstract interfaces.

Example

IAudioProvider

ISpeechRecognizer

ISoundClassifier

ILocalizationEngine

IRenderer

Every implementation must inherit from them.

---

# Future Roadmap

Phase 1

Desktop MVP

↓

Phase 2

Real sound localization

↓

Phase 3

Offline Android application

↓

Phase 4

AR glasses support

↓

Phase 5

Custom wearable prototype

↓

Phase 6

Fully embedded edge AI glasses

---

# Future Hardware

Possible future devices

XREAL

RayNeo

Rokid

Custom OLED module

Birdbath optics

Waveguide optics

---

# Stretch Goals

Speaker recognition

Keyword spotting

Emotion detection

Translation

Conversation history

Automatic summaries

Offline LLM cleanup

Voice cloning (accessibility)

Name detection

Example

"Mahmoud"

↓

Highlight in red

---

# Ultimate Goal

Aurisia should become a perception operating system.

Instead of merely converting speech into text, Aurisia understands the entire surrounding environment and represents it visually.

The user no longer "hears."

The user perceives.

Speech.

Movement.

Danger.

Direction.

Context.

Everything becomes visible.

The objective is not to restore hearing.

The objective is to invent a new human sense.