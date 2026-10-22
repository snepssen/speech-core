# Changelog

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
