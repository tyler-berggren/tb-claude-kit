---
name: video-editor
description: Edit video via Palmier Pro MCP — mlx-whisper transcribe, script review, timeline cuts, fades, captions, cleanup. Takes a video file path or "apply" to execute a reviewed script.
argument-hint: "<path-to-video.mp4> or apply"
---

# Video Editor

Transcript-based video editing via Palmier Pro MCP. Transcribes with mlx-whisper for accurate word-level timestamps, generates a reviewable script, then executes cuts, fades, and captions.

## Prerequisites

- **Palmier Pro** must be running with its MCP server connected (`palmier-pro` MCP)
- **Python 3** must be available (mlx-whisper installs into a cached venv)
- Source video must be imported into Palmier and on the timeline

## Dispatch

- `<path-to-video.mp4>` — Start a new edit: transcribe → generate script → stop for review
- `apply` — Apply the reviewed script: cuts → fades → captions → cleanup
- `cleanup` — Re-run caption cleanup only (after manual caption edits)

## Phase 1–2: Transcribe + Script (on file path input)

### Step 1 — Validate environment

1. Confirm the source video file exists.
2. Call `get_timeline` to verify Palmier MCP is connected and the video is on the timeline. Note the fps, total frames, and media ref.
3. Ask the user for a **project name** (kebab-case, e.g., `launch-walkthrough-short`). Create `cowork/video/<project-name>/` as the output directory.
4. Store the project state:
   - `PROJECT_DIR` = `cowork/video/<project-name>/`
   - `SOURCE_PATH` = the input video path
   - `FPS` = timeline fps (typically 60)

### Step 2 — Set up mlx-whisper

The venv is cached across sessions. Check if it exists, create if not:

```bash
VENV_DIR="$SCRATCHPAD_DIR/whisperx-env"
if [ ! -f "$VENV_DIR/bin/activate" ]; then
  python3 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"
  pip install mlx-whisper
else
  source "$VENV_DIR/bin/activate"
fi
```

Where `$SCRATCHPAD_DIR` is the session's scratchpad directory.

### Step 3 — Transcribe with mlx-whisper

Run mlx-whisper with word-level timestamps on the source video:

```python
import mlx_whisper, json

result = mlx_whisper.transcribe(
    "<SOURCE_PATH>",
    path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
    word_timestamps=True,
    language="en",
)

# Extract word-level data
words = [{"text": w["word"].strip(), "start": w["start"], "end": w["end"]}
         for seg in result["segments"] for w in seg.get("words", [])]
```

Save the raw transcript to `$PROJECT_DIR/whisper-transcript.json`.

**Why mlx-whisper instead of Palmier's built-in transcription:** Palmier's on-device transcription reports 0ms gaps between adjacent words — the timestamps touch with no silence represented. mlx-whisper with large-v3-turbo captures real silence gaps (100ms–3000ms+) between phrases, which is essential for identifying safe cut points.

### Step 4 — Build sentence index

Parse the word-level transcript into sentences (splitting on `.`, `?`, `!`). For each sentence, record:

- Sentence number (S001, S002, ...)
- Start frame and end frame (seconds × fps)
- Full text
- Gap to next sentence in milliseconds

Save to `$PROJECT_DIR/sentences.txt` in this format:
```
S001 [0:00.0] (1.2s) w0-2 f0-70 [gap:320ms]
  Hey, I'm Tyler.
```

### Step 5 — Generate the script

Create `$PROJECT_DIR/script.md` — the editable script the user reviews before any cuts happen.

Format:
```markdown
# <Project Name> — Edit Script

> Source: `<source path>`
> Generated: <date>
> Sentence index: sentences.txt

---

## Scene 1: <label>
**Sentences:** S001–S005 | **Source:** 0:00–0:33 (33s)

> <full text of kept sentences>

## Scene 2: <label>
...
```

**To build the initial script:** Use the sentence index to select which sentences tell the story. Group consecutive sentences into scenes with descriptive labels. Every scene must start and end on a complete sentence boundary — never mid-sentence.

**Rules for scene selection:**
- Prefer sentences that end with large gaps (400ms+) — these are natural chapter boundaries
- Skip filler content: setup/waiting time, error debugging, consent dialogs, OAuth flows, detailed UI walkthroughs
- Keep: value propositions, key demonstrations, payoff moments, the narrative arc
- Target duration: whatever the user specifies (default 3–5 minutes for social, 5–8 for YouTube)

### Step 6 — Stop for review

Present the script summary to the user:
- Total duration estimate
- Number of scenes
- Compression ratio (original → cut)

Tell the user: "Review and edit `<PROJECT_DIR>/script.md`. You can add/remove scenes, change sentence ranges, or add notes. When ready, run `/video-editor apply` to execute the cuts."

**The script is the contract.** No edits touch the timeline until the user approves.

---

## Phase 3–4: Apply (on "apply" input)

### Step 7 — Find the active project

Look for the most recently modified `script.md` in `cowork/video/*/`. Confirm with the user which project to apply.

Load:
- `script.md` — the reviewed script
- `whisper-transcript.json` — word-level timestamps
- `sentences.txt` — sentence index (for reference)

### Step 8 — Parse script into frame ranges

For each scene in the script, extract the sentence range (e.g., `S001–S005`). Look up each sentence's start and end frames from the whisper transcript data.

**Padding rules** (from research — see `cowork/research/060`):
- Lead: 5 frames (83ms) before the first sentence's first word
- Tail: variable, up to 18 frames (300ms) after the last sentence's last word
- Tail is capped at: `min(300ms, gap_to_next_word - 50ms safety margin)`
- For the first scene: no lead padding (start at frame 0 if scene starts there)
- For the last scene: no tail cap needed

**Computing delete ranges:**
1. Build keep-ranges from the parsed scenes (with padding)
2. Merge keep-ranges that overlap or are within 10 frames of each other
3. Invert: everything between keep-ranges becomes a delete range
4. Add the range from last keep-range end to total_frames

### Step 9 — Verify the timeline is clean

Call `get_timeline` to confirm the timeline has a single video clip and single audio clip (the original, unedited state). If edits are already present, warn the user and ask them to undo to the original before proceeding.

### Step 10 — Execute cuts

Call `ripple_delete_ranges` with `trackIndex: 1` (audio track, A1), `units: "frames"`, and all delete ranges. The tool handles linked video/audio sync automatically.

### Step 11 — Apply fades

After cutting, call `get_timeline` to get the new clip IDs for both video and audio tracks.

Apply opacity keyframes to every **video** clip:
- First clip: fade-out only (4 frames at end)
- Last clip: fade-in only (8 frames at start)  
- Middle clips: fade-in 8 frames + fade-out 4 frames
- Interpolation: `"linear"`

Apply volume keyframes to every **audio** clip:
- First clip: fade-out only (6 frames at end)
- Last clip: fade-in only (4 frames at start)
- Middle clips: fade-in 4 frames + fade-out 6 frames
- Interpolation: `"linear"`

**Why separate video and audio fades:** Video fades (opacity) create visual transitions between scenes — slightly longer for a smooth look. Audio fades (volume) prevent clicks and pops at cut points — shorter, just enough to eliminate artifacts. These are independent concerns with different optimal durations.

### Step 12 — Add captions

Call `add_captions` with:
- `fontSize`: 52
- `fontName`: "Helvetica-Bold"
- `color`: "#FFFFFF"
- `centerY`: 0.88
- `textCase`: "auto"

### Step 13 — Caption cleanup

Load `cowork/video/caption-dictionary.json` — a **project-owned** file. The kit ships an empty
template; each project fills in its own brand terms, transcription corrections, and capitalization.
It lives outside the skill folder because the skill directory is shared across projects (symlinked
in outside-repo mode), and this data must not be.

Call `get_timeline` to read all caption clips from the caption track's `captionGroups`.

For each caption clip, apply fixes in order:

1. **Replacements** — exact phrase substitution (e.g., "mug.org" → "mug.work"). Use `set_clip_properties` with `content` to update.

2. **Capitalize** — for each word in the `capitalize` list, find caption clips containing that word in any case and fix to the specified case. Only match whole words (e.g., "mug" → "Mug" but not "smuggle"). Use `set_clip_properties`.

3. **Remove fillers** — find caption clips whose entire text matches a filler entry (e.g., "uh," or "um,"). Remove them with `remove_clips`.

Report the fixes applied: N replacements, N capitalizations, N fillers removed.

### Step 14 — Report

Present the final result:
- Duration (original → cut)
- Number of clips, scenes
- Fades applied (video + audio)
- Captions added and cleaned
- Remind: "Play through in Palmier to verify. Any manual adjustments can be made directly in the editor."

---

## Cleanup-only mode (on "cleanup" input)

Re-runs Step 13 only — useful after manual caption edits in Palmier. Reads the current timeline captions and applies the dictionary fixes again.

---

## Reference

### Fade defaults
| Property | Fade-in | Fade-out | Applies to |
|----------|---------|----------|------------|
| Opacity  | 8 frames (133ms) | 4 frames (67ms) | Video clips |
| Volume   | 4 frames (67ms) | 6 frames (100ms) | Audio clips |

### Caption style defaults
| Property | Value |
|----------|-------|
| Font | Helvetica-Bold |
| Size | 52pt |
| Color | #FFFFFF |
| Position | centerY 0.88 (near bottom) |
| Case | auto |

### Research backing
Full analysis in `cowork/research/060_2026-06-29_ai-agent-video-editing-transcript-best-practices.md`:
- Silence gap classification: ≥400ms clean cut, 150-400ms cautious, <150ms never
- 0.2s padding is community-validated sweet spot
- 600ms most natural pause duration (PMC/NIH linguistics research)
- 4-10ms audio crossfade prevents clicks (Punch Track)
- Sentence boundaries > silence boundaries for cut points
- mlx-whisper large-v3-turbo for accurate word timestamps on Apple Silicon

### Palmier MCP tools used
- `get_timeline` — read timeline state
- `get_media` — verify media assets
- `get_transcript` — read post-edit transcript (verification)
- `ripple_delete_ranges` — execute cuts
- `set_keyframes` — opacity and volume fades
- `add_captions` — auto-caption from audio
- `set_clip_properties` — fix caption text
- `remove_clips` — delete filler captions
- `add_clips` — add segments to timeline
- `add_texts` — add manual caption clips

---

## Project overrides

If `.claude/kit.json` has a `rules."video-editor"` entry, read it and apply it as an additional
instruction for this skill. Absent file or key means no overrides — that is the normal case.

```bash
jq -r '.rules."video-editor" // empty' .claude/kit.json 2>/dev/null
```
