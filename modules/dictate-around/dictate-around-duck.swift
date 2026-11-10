// dictate-around-duck — turn other apps' audio down until SIGINT/SIGTERM, the way macOS Dictation
// does. It works on any output device, including ones with no volume control, because it doesn't
// change the device volume: it runs Apple's voice-processing audio path, whose ducking lowers
// everything else that's playing. It records nothing.
//
//   dictate-around-duck [--level min|mid|max]     default mid
//
// Exits on its own if the process that started it goes away. Built by
// install.sh with swiftc; macOS 14 or later.

import AVFoundation
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

var level: AVAudioVoiceProcessingOtherAudioDuckingConfiguration.Level = .mid
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--level":
        switch args.popFirst() {
        case "min": level = .min
        case "mid": level = .mid
        case "max": level = .max
        default: fail("--level takes min, mid or max")
        }
    default: fail("usage: dictate-around-duck [--level min|mid|max]")
    }
}

let engine = AVAudioEngine()
let input = engine.inputNode
do { try input.setVoiceProcessingEnabled(true) } catch { fail("voice processing unavailable: \(error)") }
input.voiceProcessingOtherAudioDuckingConfiguration =
    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: level)
// Leave engine.mainMixerNode alone: connecting it makes the voice-processing output fail to
// initialize (-10875). The tap just keeps the input running; its audio is discarded.
input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0)) { _, _ in }
engine.prepare()
do { try engine.start() } catch { fail("can't start voice processing: \(error)") }

func finish() -> Never {
    engine.stop()
    exit(0)
}
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
var sources: [DispatchSourceSignal] = []
for s in [SIGINT, SIGTERM] {
    let src = DispatchSource.makeSignalSource(signal: s, queue: .main)
    src.setEventHandler { finish() }
    src.resume()
    sources.append(src)
}
// Never outlive the caller: if Hammerspoon quits or crashes, stop ducking.
let parent = getppid()
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    if getppid() != parent { finish() }
}
RunLoop.main.run()
