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

`ObjCExceptions`. AVAudioEngine reports misuse by raising `NSException`, which
Swift cannot catch. `TCTry` runs a block and turns that exception into an
`NSError`, so the failure stays where the audio engine was called.

Both apps already had these two files, byte for byte:

    Sources/ObjCExceptions/ObjCExceptions.m
    Sources/ObjCExceptions/include/ObjCExceptions.h

The header in `include/` is the module. Each engine calls `TCTry` from its
`Audio.swift`.

## Later

Still in the apps, to move once both have settled on one version:

- SileroVAD
- SampleBuffer
- the model store
- PromptCache

## Use

macOS 14 and iOS 17, as the apps declare.

```swift
.package(url: "https://github.com/snepssen/speech-core", from: "0.1.0"),
```

```swift
.product(name: "ObjCExceptions", package: "speech-core"),
```

`NSException` exists only on Apple platforms. Elsewhere the same product is an
empty module, so `swift build` still succeeds. The tests that raise an
`NSException` run on macOS (`swift test`).

GPL-3.0, as interpreter-forge, which this was taken from.
