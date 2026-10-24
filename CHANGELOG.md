# Changelog

## 0.5.1

`ModelStore` builds for iOS again. `sharedRoot`'s `home:` defaulted to
`FileManager.default.homeDirectoryForCurrentUser`, which exists only on macOS
and Linux, so every iOS build of a package depending on ModelStore failed to
compile. It now defaults to `NSHomeDirectory()`. Nothing else changes, and CI
builds every product for iOS as well as testing on macOS.

## 0.5.0

`PromptCache`. An MLX attention cache reused across calls whose prompts share
a prefix: trimmed back to what is shared, at least one token always read, and
what was generated past the prompt trimmed after. A sliding-window cache that
can no longer be trimmed restarts from a copy kept with `keep(_:)` when the
prompt begins with it, and from nothing otherwise. Depends on mlx-swift-lm
from 3.32.3 on Apple platforms; elsewhere the product is empty.

## 0.4.1

`ModelStore` can read one shared folder. On an unsandboxed Mac that is
`~/Library/Application Support/snepssen/models`. On Linux it is
`$XDG_DATA_HOME/snepssen/models`, or `~/.local/share/snepssen/models`. A
sandboxed app uses the app group `group.com.snepssen.models`. A Release
store reads that folder and no checkout path, and it does not download,
move, or delete. A missing file is named by its path. The 0.4.0 initializer
is unchanged.

## 0.4.0

`ModelStore`. Locating a pinned model, checking each file's size, and fetching
what is missing from its Hugging Face revision. Each app keeps its own folder.
A symlink counts as the file it names, and can be left in place instead of
written through.

## 0.3.0

`SampleBuffer`. The 16 kHz mono window both apps keep: stream indices that
survive a drop, the RMS of the last block, and an optional listener for each
block as it arrives.

## 0.2.0

`SileroVAD`. Silero VAD v5 on 32 ms frames: 512 samples at 16 kHz, the previous
frame's last 64 samples in front, speech from 0.5 held down to 0.35, and the
last frame's probability.

## 0.1.0

`ObjCExceptions`. `TCTry` turns an `NSException` from AVAudioEngine into an
`NSError`.
