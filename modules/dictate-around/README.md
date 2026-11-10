# dictate-around

**Dictate into one text field while you click, scroll and switch apps anywhere else.**

macOS Dictation types live into whatever has focus, so the moment you click somewhere else it
stops, or worse, keeps typing into the wrong place. That makes it useless for the most natural
way to write a long prompt or message: talking it through while you look things up.

dictate-around flips the order. You press a hotkey in the field you want to fill, talk while you
move around freely, and press the hotkey again. Your speech is transcribed on your Mac and pasted
into the field where you started.

```
 double-tap Fn  ──►  talk, click, scroll, switch apps  ──►  double-tap Fn
   (tink, 🎙)            nothing is typed meanwhile           (pop, ✍︎)
                                                                 │
                     text appears in the field where you started ◄┘
```

- **Goes back to where you started.** The text lands in the original field even if you're in a
  different app when you stop.
- **Any hotkey.** Double-tap Fn by default, or double-tap any modifier, or any key combination.
- **Any mic, without changing your system input.** Record from a headset while every other app
  keeps using your desk mic.
- **Turns other audio down while you talk**, the way macOS Dictation does, on any output device,
  including headsets whose volume macOS can't control.
- **Fully local.** Transcription runs on your Mac with [whisper.cpp](https://github.com/ggml-org/whisper.cpp).
  No account, no API key, and no audio leaves the machine.
- **Leaves your clipboard alone.** It pastes through the clipboard and then puts back what was
  there.

---

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Using it](#using-it)
- [Settings](#settings)
- [Hotkeys](#hotkeys)
- [Choosing a mic](#choosing-a-mic)
- [Turning other audio down](#turning-other-audio-down)
- [How it works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Privacy](#privacy)
- [Limitations](#limitations)
- [Uninstall](#uninstall)
- [Files](#files)

---

## Requirements

| | |
|---|---|
| **macOS** | 14 Sonoma or later (the audio ducking API needs 14). |
| **Mac** | Apple silicon recommended. Transcription works on Intel, more slowly. |
| **[Homebrew](https://brew.sh)** | The installer uses it for Hammerspoon, ffmpeg and whisper.cpp. |
| **Command Line Tools** | For building the small ducking helper: `xcode-select --install`. Without them everything works except ducking. |
| **Disk** | About 600 MB, almost all of it the speech model. |

## Install

```bash
git clone https://github.com/tyler-berggren/dictate-around.git ~/dev/dictate-around
cd ~/dev/dictate-around
./install.sh
```

The installer is safe to re-run, and does this:

1. Installs **Hammerspoon**, **ffmpeg** and **whisper-cpp** with Homebrew, if they're missing.
2. Downloads the speech model, `ggml-large-v3-turbo-q5_0.bin` (about 550 MB), to
   `~/.local/share/whisper/`.
3. Builds the ducking helper into `~/.local/share/dictate-around/`.
4. Links `~/.hammerspoon/dictate-around.lua` to the module in this folder, so a `git pull` updates
   it, and adds a marked block to `~/.hammerspoon/init.lua` that loads it. Anything else in your
   `init.lua` is left alone.
5. Starts or reloads Hammerspoon.

Then a few steps only you can do. The installer prints the ones that apply:

1. **System Settings → Privacy & Security → Accessibility:** turn on **Hammerspoon**. It needs
   this to see the hotkey and to paste. Then click the Hammerspoon menu-bar icon → **Reload Config**.
2. **Microphone:** the first time you use it, macOS asks whether Hammerspoon may use the
   microphone. Click **Allow**.
3. **Hammerspoon → Preferences:** tick **Launch Hammerspoon at login**.
4. **Only with an Fn hotkey (the default):** System Settings → Keyboard → set **Press 🌐 key to**
   to **Do Nothing**, and set the **Dictation** shortcut to **Off**. If "Press 🌐 key to" is left
   unset, macOS treats it as *Show Emoji & Symbols*, and the emoji picker opens on every tap.

Check everything at once:

```bash
./install.sh --status
```

```
module:   /Users/you/.hammerspoon/dictate-around.lua -> /Users/you/dev/dictate-around/dictate-around.lua
init.lua: hooked
config:   { "mic": "Headset Mic", "duck": "mid"}
model:    /Users/you/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin
fn key:   Do Nothing (ok)
running:  listening=true hotkey=double-fn accessibility=true state=idle mic=Headset Mic model=ok duck=mid
```

## Using it

1. **Click into a text field** and **double-tap Fn**. You hear a *tink* and see 🎙 in the menu
   bar. dictate-around has noted the app, the window and the exact field you're in, and is
   recording.
2. **Talk, and move around as much as you like.** Click links, scroll, switch apps, type
   somewhere else. Nothing is typed while you talk, so nothing can interrupt it. Other audio is
   turned down while you talk.
3. **Double-tap Fn again.** You hear a *pop*, and ✍︎ shows while it transcribes, usually a second
   or two. Then it brings the original window forward, puts the cursor back in your field, pastes
   the text and restores your clipboard. You're left there, in the field you started in.

If it can't bring the original app back to the front within two seconds, it doesn't paste
anywhere. It leaves the text on your clipboard and tells you, so you can paste it yourself.

## Settings

Settings live in `~/.config/dictate-around/config.json`. Every key is optional, and the file
doesn't need to exist.

```json
{
  "mic": "Headset Mic",
  "hotkey": "double-fn",
  "duck": "mid"
}
```

| Key | Default | What it does |
|---|---|---|
| `hotkey` | `"double-fn"` | What starts and stops recording. See [Hotkeys](#hotkeys). |
| `mic` | system input | The input device to record from, by its exact name. See [Choosing a mic](#choosing-a-mic). |
| `duck` | `"mid"` | How far to turn other audio down while recording: `"min"`, `"mid"`, `"max"` or `"off"`. |
| `language` | `"en"` | The language you speak, as a whisper language code (`"de"`, `"es"`, `"ja"`...), or `"auto"` to detect it. |
| `returnToCurrent` | `false` | After pasting, go back to wherever you were when you stopped, instead of staying in the original field. |
| `tapMax` | `0.30` | The longest press, in seconds, that counts as a tap for a double-tap hotkey. |
| `doubleTapWindow` | `0.40` | The longest gap, in seconds, between the two taps. |
| `model` | `~/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin` | The whisper.cpp model file. |
| `ffmpeg` | `/opt/homebrew/bin/ffmpeg` | Path to ffmpeg. |
| `whisper` | `/opt/homebrew/bin/whisper-cli` | Path to whisper.cpp's command-line tool. |
| `duckHelper` | `~/.local/share/dictate-around/dictate-around-duck` | Path to the ducking helper. |

The installer writes the common ones for you and reloads Hammerspoon:

```bash
./install.sh --mic "Headset Mic"           # record from this input
./install.sh --hotkey double-rightcmd      # change the hotkey
./install.sh --duck max                    # turn other audio down further
./install.sh --mic default --duck default  # back to the defaults
```

They can be combined in one command. If you edit the file by hand, use **Reload Config** from the
Hammerspoon menu afterwards.

### A different model

Any whisper.cpp `ggml` model works. Smaller is faster and less accurate:

```bash
MODEL_URL=https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin ./install.sh
```

Then set `"model"` in the settings to the downloaded file. English-only models (`.en`) are a little
more accurate for English at the same size. `large-v3-turbo` is the default because on Apple silicon
it's both fast and close to the most accurate.

## Hotkeys

Two forms:

**Double-tap a modifier.** Two quick taps with nothing else pressed. Because a tap only counts on
its own, normal shortcuts that use the same key keep working: Fn+arrow, ⌘C and so on.

| Spec | Key |
|---|---|
| `double-fn` (default) | Fn / 🌐 |
| `double-cmd` · `double-leftcmd` · `double-rightcmd` | Command, either side or one side |
| `double-alt` · `double-leftalt` · `double-rightalt` | Option (`option` also works) |
| `double-ctrl` · `double-leftctrl` · `double-rightctrl` | Control |
| `double-shift` · `double-leftshift` · `double-rightshift` | Shift |

One-sided keys are the most conflict-free choice: almost nothing uses right ⌘ or right ⌥ on its own.

**A key combination.** Press once to start and again to stop:

```
ctrl+alt+d      cmd+shift+space      f13      hyper keys: ctrl+alt+cmd+shift+d
```

Modifiers are `cmd`, `alt` (or `option`), `ctrl`, `shift` and `fn`. The key is any key name
Hammerspoon knows: letters, digits, `space`, `return`, `f1`–`f20`, `pad1`... A function key with
no other use, like F13–F19 on an extended keyboard or remapped with Karabiner-Elements, makes an
excellent single-key toggle.

If a hotkey can't be understood, you get an alert when Hammerspoon loads and `--status` shows the
error, e.g. `hotkey=ERROR unknown modifier "hyper"`.

## Choosing a mic

By default it records from your system input, the one selected in System Settings → Sound. To
record from a particular device instead, give its exact name:

```bash
./install.sh --list-mics
```
```
MacBook Pro Microphone
Studio Display Microphone
Headset Mic
```
```bash
./install.sh --mic "Headset Mic"
```

The system input doesn't change. Calls, recordings and every other app keep using whatever they
were using, and only dictate-around records from the headset. It's handy if your desk mic is your
main input but a headset is better for dictation, or the other way round.

If the device isn't connected when you start recording, you get an alert naming it, and nothing
is recorded.

## Turning other audio down

While you're recording, other audio (music, videos, a call) is turned down and comes back when you
stop, like with macOS Dictation.

It doesn't change your device's volume, which many USB and Bluetooth headsets don't let macOS
control anyway. Instead, a small helper turns on Apple's voice-processing audio path, which
lowers *other* apps' audio, the same mechanism FaceTime and Dictation use. It records nothing:
recording is done separately, so the helper can't affect what's captured.

- **Levels:** `min`, `mid` (default) and `max`. Apple offers these three levels, not a
  percentage. `off` turns ducking off.
- **It starts about a second after the *tink*,** while voice processing spins up. Recording
  starts immediately, so your first words aren't lost, only the music dips a moment later.
- **It always ends.** The helper stops when you stop recording, when recording fails, and on its
  own if Hammerspoon quits or crashes.

## How it works

Four pieces, all local:

| Piece | Role |
|---|---|
| [Hammerspoon](https://www.hammerspoon.org) | Watches for the hotkey, remembers where you started (the app, the window, and the text field through the macOS Accessibility API), runs the other pieces, and pastes. `dictate-around.lua` is a Hammerspoon module. |
| [ffmpeg](https://ffmpeg.org) | Records from the chosen device by name through AVFoundation, as 16 kHz mono WAV, until it's told to stop. |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | Turns the recording into text on your Mac, using the GPU on Apple silicon. |
| `dictate-around-duck` | A small Swift helper that turns other audio down through voice processing for as long as it runs. |

When you stop, the text has to land in a field that may no longer be in front. Recent macOS
versions bring an app forward asynchronously, so pasting straight away goes to the wrong app.
dictate-around asks for the original window, **waits until that app is actually frontmost**
(nudging it again if needed, for up to two seconds), puts the cursor back in the original field,
and only then pastes with ⌘V. Your clipboard is saved first and restored after.

Detecting a double-tap of Fn has a quirk worth knowing if you change the code: each time Fn is
released, macOS sends an extra key event (key code 179, the Globe key). It has to be ignored, or
it looks like a normal keypress between the taps and cancels the double-tap.

## Troubleshooting

Start with `./install.sh --status`. It covers most of these.

**The emoji picker opens when I tap Fn.**
System Settings → Keyboard → *Press 🌐 key to* → **Do Nothing**. "Unset" means emoji, and turning
off the Dictation shortcut can reset it to unset.

**Nothing happens when I press the hotkey.**
- `--status` should show `listening=true accessibility=true`. If accessibility is `false`, turn on
  Hammerspoon under Privacy & Security → Accessibility, then Reload Config.
- If the hotkey shows `ERROR`, fix the spec.
- **Secure input** blocks every hotkey tool: while a password field has focus, or in a terminal
  with *Secure Keyboard Entry* turned on, macOS hides keystrokes from other apps. Click
  somewhere else first.
- With a double-tap: two quick taps, with nothing else pressed in between. If your taps are slow,
  raise `doubleTapWindow`.

**"Recording failed (is "…" connected?)"**
The mic isn't connected, or its name has changed. `--list-mics` shows the exact names. If it's
your system input that's missing, check System Settings → Sound.

**"No speech detected"**
The recording was silent. Check that the right mic is selected and not muted (many headsets have
a mute switch or a flip-up boom), and that Hammerspoon has microphone permission in Privacy &
Security → Microphone.

**"Couldn't return to … — text is on your clipboard"**
The original app wouldn't come to the front, for example because its window was closed meanwhile.
Paste with ⌘V.

**The text went into the right app but not the right field.**
Some apps, web pages and Electron apps especially, may not let another app put the cursor back in
a particular field. The text lands in whatever field that window has focused. Clicking back into
the field before you stop avoids it.

**Hammerspoon says "dictate-around ready" but transcription fails.**
Run whisper by hand to see the error:
`/opt/homebrew/bin/whisper-cli -m ~/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin -f "$TMPDIR/dictate-around.wav"`.

**The installer says ffmpeg "won't run".**
Homebrew upgraded a library under it. `brew reinstall ffmpeg` (or `ffmpeg-full`, whichever you
have) fixes it.

**Other audio doesn't get quieter.**
`--status` shows `duck=… (helper not built)` if the helper is missing: install the Command Line
Tools (`xcode-select --install`) and re-run `./install.sh`. Ducking needs macOS 14 or later.

## Privacy

- Audio is recorded to one temporary file, `$TMPDIR/dictate-around.wav`, overwritten on every use.
- Transcription runs entirely on your Mac. The only network access is the installer downloading
  the model once from Hugging Face, and Homebrew installing the tools.
- Nothing is logged. The transcribed text exists only in the field you pasted it into (and on your
  clipboard, if it couldn't get back to the original app).

## Limitations

- **Text arrives when you stop, not word by word.** That's the trade for being able to move
  around: nothing is typed while you talk.
- **It pastes.** A field that blocks pasting won't receive the text; it stays on your clipboard
  instead.
- **One recording at a time.** A press while it's transcribing is ignored.
- **Long recordings take longer to transcribe.** A sentence or two takes a second or two on
  Apple silicon; minutes of speech take noticeably longer.
- **Fn depends on the keyboard.** Some third-party keyboards handle Fn in hardware and never tell
  macOS. Use another hotkey with those.

## Uninstall

```bash
./install.sh --uninstall
```

This removes the block from `~/.hammerspoon/init.lua`, the module link and the ducking helper. It
leaves Hammerspoon, ffmpeg, whisper-cpp, the model and your settings, since other things may use
them. To remove those too:

```bash
rm ~/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin
rm -r ~/.config/dictate-around
brew uninstall whisper-cpp            # and ffmpeg / hammerspoon, if nothing else needs them
```

## Files

| Path | What |
|---|---|
| `dictate-around.lua` | The Hammerspoon module: hotkey, recording, transcription, pasting. |
| `dictate-around-duck.swift` | The ducking helper's source. |
| `install.sh` | Install, update, settings, status, uninstall. |
| `~/.config/dictate-around/config.json` | Your settings. |
| `~/.local/share/whisper/` | Speech models. |
| `~/.local/share/dictate-around/dictate-around-duck` | The built ducking helper. |

---

dictate-around also ships as a module of [tb-claude-kit](https://github.com/tyler-berggren/tb-claude-kit),
a Claude Code harness, where `scripts/install-dictate-around` runs this installer. It works the
same either way.

MIT licensed. See [LICENSE](LICENSE).
