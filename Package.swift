// swift-tools-version: 6.0
import PackageDescription

// speech-core: the hearing layer interpreter-forge and companion-forge share.
// Pieces move here one at a time, each as its own minor tag. ObjCExceptions
// is 0.1.0. SileroVAD is 0.2.0. SampleBuffer is 0.3.0.
//
// NSException and the ONNX Runtime binary exist only on Apple platforms. The
// host that evaluates this manifest is what decides: a Mac builds those
// targets (and can cross-compile them for iOS), and anywhere else the same
// products are empty Swift modules so `swift build` still succeeds.
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
let objcExceptions: Target = .target(name: "ObjCExceptions")
let sileroVAD: Target = .target(
    name: "SileroVAD",
    dependencies: [
        .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
    ]
)
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.20.0"),
]
#else
let objcExceptions: Target = .target(
    name: "ObjCExceptions",
    path: "Sources/ObjCExceptionsLinux"
)
let sileroVAD: Target = .target(
    name: "SileroVAD",
    path: "Sources/SileroVADLinux"
)
let dependencies: [Package.Dependency] = []
#endif

let package = Package(
    name: "SpeechCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ObjCExceptions", targets: ["ObjCExceptions"]),
        .library(name: "SileroVAD", targets: ["SileroVAD"]),
        .library(name: "SampleBuffer", targets: ["SampleBuffer"]),
    ],
    dependencies: dependencies,
    targets: [
        // NSException to NSError, for AVAudioEngine, which raises instead of throwing.
        objcExceptions,
        .testTarget(name: "ObjCExceptionsTests", dependencies: ["ObjCExceptions"]),
        // Silero VAD v5. The weights stay with the app; this loads them.
        sileroVAD,
        .testTarget(
            name: "SileroVADTests",
            dependencies: ["SileroVAD"],
            exclude: ["make_fixture.py"],
            resources: [.copy("Fixtures")]
        ),
        // 16 kHz mono samples. Plain Swift, so the same target builds everywhere.
        .target(name: "SampleBuffer"),
        .testTarget(name: "SampleBufferTests", dependencies: ["SampleBuffer"]),
    ]
)
