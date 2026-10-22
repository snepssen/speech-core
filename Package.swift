// swift-tools-version: 6.0
import PackageDescription

// speech-core: the hearing layer interpreter-forge and companion-forge share.
// Pieces move here one at a time, each as its own minor tag. ObjCExceptions
// is the first (0.1.0).
//
// NSException exists only on Apple platforms. The host that evaluates this
// manifest is what decides: a Mac builds the Objective-C target (and can
// cross-compile it for iOS), and anywhere else the same product is an empty
// Swift module so `swift build` still succeeds.
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
let objcExceptions: Target = .target(name: "ObjCExceptions")
#else
let objcExceptions: Target = .target(
    name: "ObjCExceptions",
    path: "Sources/ObjCExceptionsLinux"
)
#endif

let package = Package(
    name: "SpeechCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ObjCExceptions", targets: ["ObjCExceptions"]),
    ],
    targets: [
        // NSException to NSError, for AVAudioEngine, which raises instead of throwing.
        objcExceptions,
        .testTarget(name: "ObjCExceptionsTests", dependencies: ["ObjCExceptions"]),
    ]
)
