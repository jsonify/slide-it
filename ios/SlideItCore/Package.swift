// swift-tools-version:5.9
// The platform-independent heart of Slide It: rules, network protocol and the
// match referee. The iOS app compiles these same files directly; this package
// exists so the logic can be built and unit-tested anywhere with `swift test`.
import PackageDescription

let package = Package(
    name: "SlideItCore",
    products: [.library(name: "SlideItCore", targets: ["SlideItCore"])],
    targets: [
        .target(name: "SlideItCore"),
        .testTarget(name: "SlideItCoreTests", dependencies: ["SlideItCore"]),
    ]
)
