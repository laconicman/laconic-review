// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "laconic-review",
    platforms: [
        // A host CLI — it only ever builds/runs on macOS. But SwiftPM validates deployment
        // targets on *every* platform a dependency declares, so we must meet or exceed
        // GitLabKit's minimums on all of them. iOS/tvOS/watchOS are declared purely to satisfy
        // resolution (nothing is actually built for those platforms); macOS is the real target.
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        // The CLI you run.
        .executable(name: "flat-review", targets: ["flat-review"]),
        // The testable core — review intelligence is provider-neutral; only `GitLabConnection`
        // touches GitLab. This is the surface the skill self-heals from (via its DocC).
        .library(name: "FlatReviewCore", targets: ["FlatReviewCore"]),
    ],
    dependencies: [
        // Local path dep during bring-up; swap to a Git URL once GitLabKit is published.
        .package(path: "../GitLabKit"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "flat-review",
            dependencies: [
                "FlatReviewCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "FlatReviewCore",
            dependencies: [
                // Façade (adds `Client` conveniences) + the generated client/types.
                .product(name: "GitLabKit", package: "GitLabKit"),
                .product(name: "GitLabOpenAPI", package: "GitLabKit"),
            ]
        ),
        .testTarget(
            name: "FlatReviewCoreTests",
            dependencies: ["FlatReviewCore"]
        ),
    ]
)
