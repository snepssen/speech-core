# speech-core

The hearing layer shared by interpreter-forge and companion-forge. One folder
per repository: this one lives at `~/Claude/speech-core`, beside the forges.

## Release

Each piece that moves here gets its own minor tag: ObjCExceptions is 0.1.0,
then SileroVAD, SampleBuffer, the model store and PromptCache, one minor
version each.

The apps update to that tag in the same change that drops their copy. Both
apps' checks pass before the move, and both pass again after they depend on
the new package. A piece stays put until those checks have passed.

The tag is cut after the piece has landed on main. Apps depend on it with
`from:`, so the tag has to exist before their package resolve. This package's
own check is `swift test` on macOS. The apps' checks are the ones that decide
the move.

Once a tag exists, each app's daily **dependencies** workflow (site-core's
`update-dependency.yml`) moves it there after its own checks pass. A release
that only changes this package needs no app PR.
