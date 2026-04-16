# LUnette — macOS Loudness Analyser
> A SwiftUI app for EBU R128 / BS.1770 loudness analysis — built for audio engineers

---

## Overview

LUnette is a native macOS app that performs accurate EBU R128 / BS.1770 loudness analysis on audio files via drag-and-drop. It targets **audio engineers, mastering engineers, and broadcast QC professionals** who want fast, reliable readings without opening a DAW or running terminal commands.

The name is a play on **LU** (Loudness Units) and *lunette* — a small lens — reflecting the app's purpose: a focused, precise window into a track's loudness.

---

## Goals

- Drag-and-drop any audio file (FLAC, WAV, AIFF, MP3, AAC) for instant EBU R128 / BS.1770 results
- Full metering readout: Integrated, LRA, True Peak, PLR, Momentary, Short-term, Thresholds
- Visual loudness history plot — short-term LUFS over time with target overlays
- Standards compliance view: streaming platforms + broadcast targets side by side
- Batch mode: analyse a whole album or delivery folder, export as CSV or plain text
- Dense, professional UI — no hand-holding, no consumer fluff
- No DAW, no plugins, no ffmpeg dependency

---

## Tech Stack

| Concern | Approach |
|---|---|
| UI | SwiftUI (macOS 13+) |
| Audio decoding | AVFoundation (`AVAudioFile`) |
| Loudness metering | `libebur128` (bundled static lib, Swift wrapper) |
| Loudness plot | Swift Charts (native, macOS 13+) |
| File handling | `NSOpenPanel` + drag-and-drop (`DropDelegate`) |
| Export | CSV + plain text summary |
| Distribution | Direct download (.dmg) — avoid App Store sandboxing friction |

### Why libebur128 over ffmpeg?
- No external dependency for the user
- Fully spec-compliant EBU R128 gating (validated against ffmpeg's `ebur128` filter)
- Fed PCM frames directly from AVFoundation
- MIT licensed, easy to bundle
- **Note:** no official SPM wrapper exists — C source will be vendored with a thin Swift `LoudnessMeter` class

---

## Standards Supported

| Standard | Region | Target | Notes |
|---|---|---|---|
| **EBU R128** | Europe / global | −23 LUFS | Primary broadcast standard |
| **ATSC A/85** | North America (TV) | −24 LKFS | Same BS.1770 algorithm, different name |
| **ITU-R BS.1770** | Underlying algorithm | — | The measurement spec both above are built on |
| **ARIB TR-B32** | Japan | −24 LKFS | Regional broadcast variant |
| **Spotify** | Streaming | −14 LUFS | Normalisation target |
| **Apple Music** | Streaming | −16 LUFS | Normalisation target |
| **YouTube** | Streaming | −14 LUFS | Normalisation target |
| **Tidal** | Streaming | −14 LUFS | Normalisation target |
| **Amazon Music** | Streaming | −14 LUFS | Normalisation target |
| **Deezer** | Streaming | −15 LUFS | Normalisation target |
| **SoundCloud** | Streaming | −14 LUFS | Normalisation target (lossy transcode, flag) |

---

## Metrics — Full Readout

### Primary (always shown)
| Metric | Description |
|---|---|
| **Integrated (I)** | Loudness over entire file, gated per BS.1770 |
| **LRA** | Loudness Range — spread between LRA low and LRA high |
| **LRA low / high** | Actual LUFS boundaries of the loudness range |
| **True Peak** | Inter-sample peak per channel (L / R) |
| **Integrated threshold** | Gate level used in R128 calculation |
| **LRA threshold** | Gate level used in LRA calculation |

### Secondary (always shown in single-file view)
| Metric | Description |
|---|---|
| **PLR** | Program Loudness Range — integrated LUFS minus true peak; indicates headroom and compression aggressiveness |
| **Momentary max (M)** | Loudest 400ms window — catches transient peaks |
| **Short-term max (S)** | Loudest 3s window — shows loudest musical passage |
| **Per-channel true peak** | L and R reported separately |
| **Clipping flag** | Warning if true peak > −1 dBTP; error if > 0 dBTP |

---

## Loudness Plot

A visual loudness history graph rendered with **Swift Charts**, shown below the metrics card in single-file view.

- X axis: time (seconds)
- Y axis: LUFS
- **Short-term LUFS** plotted as a continuous line (3s window, 1s hop)
- **Momentary LUFS** plotted as a lighter fill underneath
- Horizontal reference lines (dashed, labelled) for selected streaming/broadcast targets
- Integrated LUFS shown as a solid horizontal line across the full duration
- Clip regions (where true peak > −1 dBTP) highlighted in red on the time axis
- Zoomable / scrollable for long files

```
  LUFS
  −8  ┤
 −10  ┤         ╭───╮
 −12  ┤     ╭───╯   ╰──╮        ╭──╮
 −14  ┼─────────────────────────────────  ← Spotify / YouTube
 −16  ┤  ╭──╯            ╰──────╯  ╰─╮   ← Apple Music
 −18  ┤╭─╯                            ╰─
 −20  ┤
 −23  ┼─────────────────────────────────  ← EBU R128 broadcast
      └────────────────────────────────▶ time
```

---

## UI Design Direction

**Tone:** Dense, professional, utilitarian — closer to Nugen VisLM or iZotope Insight than a consumer app. No onboarding copy, no emoji, no "great job!" feedback. Engineers want numbers.

**Typography:** Monospaced or tabular-figures typeface for all metric values so columns align. Clear hierarchy between label and value.

**Colour use:** Minimal — use colour only for status (green = pass, amber = warning, red = clip/fail). Dark mode default.

### Single file view
Show everything — there's no screen real estate pressure and engineers want the full picture at a glance. Layout:
1. File info bar (filename, format, samplerate, bit depth, duration)
2. Two-column metrics card (labels left, values right, grouped by category)
3. Standards compliance panel
4. Loudness plot (full width)

### Standards compliance panel
```
Spotify    −14 LUFS  →  no change          ✓
Apple      −16 LUFS  →  +1.8 dB boost      ✓
YouTube    −14 LUFS  →  no change          ✓
Amazon     −14 LUFS  →  no change          ✓
Tidal      −14 LUFS  →  no change          ✓
Deezer     −15 LUFS  →  +0.8 dB boost      ✓
SoundCloud −14 LUFS  →  no change          ✓  ⚠ lossy transcode
EBU R128   −23 LUFS  →  +8.8 dB boost      ✓  broadcast
ATSC A/85  −24 LUFS  →  +9.8 dB boost      ✓  broadcast
```

### Batch / folder view
Sortable table. Column visibility toggled by **right-clicking any column header**. Default columns: Track, I (LUFS), LRA, True Peak, PLR, Clip flag. All others available but hidden by default.

---

## UI Sketch — Single File

```
┌──────────────────────────────────────────────┐
│  LUnette                               ⚙  ↗  │
├──────────────────────────────────────────────┤
│  Mice on Venus — C418                        │
│  FLAC 16bit / 44.1kHz / Stereo / 4:42        │
├───────────────────────┬──────────────────────┤
│  INTEGRATED           │        −14.2 LUFS    │
│  Threshold            │        −26.5 LUFS    │
├───────────────────────┼──────────────────────┤
│  LRA                  │          19.4 LU     │
│  LRA low              │        −30.5 LUFS    │
│  LRA high             │        −11.0 LUFS    │
│  LRA threshold        │        −36.5 LUFS    │
├───────────────────────┼──────────────────────┤
│  TRUE PEAK  L         │         −0.1 dBTP    │
│             R         │         +0.1 dBTP  ⚠ │
│  PLR                  │          14.1        │
│  Momentary max        │         −7.4 LUFS    │
│  Short-term max       │        −11.0 LUFS    │
├───────────────────────┴──────────────────────┤
│  STANDARDS                                   │
│  Spotify   −14  →  no change          ✓      │
│  Apple     −16  →  +1.8 dB            ✓      │
│  YouTube   −14  →  no change          ✓      │
│  Amazon    −14  →  no change          ✓      │
│  Tidal     −14  →  no change          ✓      │
│  Deezer    −15  →  +0.8 dB            ✓      │
│  SoundCld  −14  →  no change          ✓  ⚠   │
│  EBU R128  −23  →  +8.8 dB            ✓      │
│  ATSC A/85 −24  →  +9.8 dB            ✓      │
├──────────────────────────────────────────────┤
│  LOUDNESS PLOT                               │
│  ╭─────────────────────────────────────────╮ │
│  │   short-term ──  momentary ░░           │ │
│  │        ╭───╮                            │ │
│  │    ╭───╯   ╰──╮       ╭──╮             │ │
│  ┼────────────────────────────────  −14    │ │
│  │ ╭──╯           ╰──────╯  ╰─╮    −16    │ │
│  ┼─────────────────────────────────  −23   │ │
│  ╰─────────────────────────────────────────╯ │
└──────────────────────────────────────────────┘
```

---

## Export

### Single file
- **Copy to clipboard** — plain text summary (matches the metrics card layout)
- **Save as .txt** — same format, useful for delivery documentation
- **Save as .csv** — one row per metric, machine-readable

### Batch
- **Save as .csv** — one row per track, all visible columns exported
- **Save as .txt** — formatted table, similar to foobar2000 DR log style
- Column selection for export mirrors the visible columns in the table

### CSV format (batch example)
```
Track,Integrated (LUFS),LRA (LU),True Peak L (dBTP),True Peak R (dBTP),PLR,Momentary Max (LUFS),Short-term Max (LUFS),Clip
01-Key,-22.1,11.2,-10.91,-10.91,11.2,-14.2,-16.1,false
11-Mice on Venus,-14.2,19.4,-0.1,0.1,14.1,-7.4,-11.0,true
12-Dry Hands,-15.2,24.4,-0.5,0.0,14.7,-8.1,-11.0,false
```

---

## Milestones

| # | Task | Notes |
|---|---|---|
| 1 | Project setup | SwiftUI app target, macOS 13+, SPM workspace |
| 2 | AVFoundation audio reader | Decode any format to PCM float32 frames |
| 3 | libebur128 integration | Vendor C source, write Swift `LoudnessMeter` wrapper |
| 4 | Full metrics calculation | Integrated, LRA, PLR, momentary, short-term, per-channel TP |
| 5 | Single file UI | Drop target, full readout card, clip warning |
| 6 | Standards compliance panel | All streaming + broadcast targets with gain delta |
| 7 | Loudness plot | Swift Charts — short-term + momentary lines, target overlays, clip markers |
| 8 | Batch / folder mode | Sortable table, right-click column toggle, multi-select |
| 9 | Export | CSV + .txt for both single file and batch |
| 10 | Polish + DMG build | App icon, notarization, release |

---

## Settings (minimal popover, not a full window)
Only things that genuinely need to be configurable:
- **Default broadcast standard** — which spec to highlight (EBU R128 vs ATSC A/85 vs ARIB)
- **True peak warning threshold** — default −1 dBTP, adjustable
- **Plot reference lines** — which streaming/broadcast targets to show on the loudness plot
- **Theme** — dark / light / system

Column visibility lives in the batch table itself (right-click header), not here.

---

## Out of Scope (v1.0)

- Realtime monitoring (mic input)
- Windows / Linux support
- Plugin version (AU/VST)
- Dolby Atmos / spatial audio loudness

---

## Reference

- EBU R128 spec: https://tech.ebu.ch/docs/r/r128.pdf
- ITU-R BS.1770-4: https://www.itu.int/rec/R-REC-BS.1770
- ATSC A/85: https://www.atsc.org/atsc-documents/a85-techniques-for-establishing-and-maintaining-audio-loudness/
- libebur128: https://github.com/jiixyj/libebur128
- Swift Charts docs: https://developer.apple.com/documentation/charts
- Validation command: `ffmpeg -i input.flac -af ebur128=peak=true -f null -`
