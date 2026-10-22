# speech-core

The hearing layer of Velvet's workshop, shared by
[interpreter-forge](https://github.com/snepssen/interpreter-forge) and
[companion-forge](https://github.com/snepssen/companion-forge): the microphone
and the speaker, voice detection, speech recognition and the model store.

Each app carried its own copy. The copies move here one piece at a time, and
each piece is its own release. The apps take that version in the same change.

The workshop keeps one folder per repository. This one lives at
`~/Claude/speech-core`, beside the forges.

## Now

`ObjCExceptions`, since 0.1.0. AVAudioEngine reports misuse by raising
`NSException`, which Swift cannot catch. `TCTry` runs a block and turns that
exception into an `NSError`, so the failure stays where the audio engine was
called.

Both apps already had these two files, byte for byte:

    Sources/ObjCExceptions/ObjCExceptions.m
    Sources/ObjCExceptions/include/ObjCExceptions.h

The header in `include/` is the module. Each engine calls `TCTry` from its
`Audio.swift`.

`SileroVAD`, for 0.2.0. Silero VAD v5 on 32 ms frames: 512 samples at 16 kHz,
with the last 64 samples of the previous frame in front, which the v5 graph
expects. Speech starts at probability 0.5 and holds while it stays at or above
0.35. `probability` is the last frame's score, so a caller can ask for a surer
voice when it is talking over a reply than when it is talking into silence.

```swift
let vad = try SileroVAD(model: modelURL)
let speech = try vad.push(samples[...], at: time)
let gap = vad.silence(at: time)
```

The weights stay with the app (`silero_vad.onnx`). This package loads them
through ONNX Runtime, the same package the apps already use. The runtime
exists on Apple platforms. Elsewhere the product is an empty module, so
`swift build` still succeeds. The tests feed a tiny bundled graph, and run
on macOS (`swift test`).

`SampleBuffer`, for 0.3.0. The 16 kHz mono window the microphone writes and
the loop reads. `count` is how far the stream has got. `drop(before:)` lets
go of samples and leaves that count where it is, so a read still asks for
stream indices. `level` is the RMS of the last block. `everything` is the
samples still held. A `listener`, when set, is handed each block after it is
stored.

```swift
let buffer = SampleBuffer()
buffer.append(block)
let frame = buffer.read(start, end)
buffer.drop(before: start)
```

It is plain Swift, so the tests run on macOS and on Linux.

## Later

Still in the apps, to move once both have settled on one version:

- the model store
- PromptCache

## Use

macOS 14 and iOS 17, as the apps declare. 0.3.0 is the tag to cut once this
is on main. `ObjCExceptions` is 0.1.0 and `SileroVAD` is 0.2.0.

```swift
.package(url: "https://github.com/snepssen/speech-core", from: "0.3.0"),
```

```swift
.product(name: "ObjCExceptions", package: "speech-core"),
.product(name: "SileroVAD", package: "speech-core"),
.product(name: "SampleBuffer", package: "speech-core"),
```

`NSException` exists only on Apple platforms. The tests that raise one run on
macOS (`swift test`).

GPL-3.0, as interpreter-forge, which this was taken from.
