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
        .executable(name: "laconic-review", targets: ["laconic-review"]),
        // The testable core — report format, neutral DTOs, the `ReviewHost` seam. No
        // provider imports: each forge client lives in its own target below.
        .library(name: "LaconicReviewCore", targets: ["LaconicReviewCore"]),
        // The forge connections — public so their DocC stays the self-heal contract
        // (a skill re-derives mappings from the symbol graph, not from source).
        .library(name: "GitLabConnection", targets: ["GitLabConnection"]),
    ],
    dependencies: [
        // Local path dep during bring-up; swap to a Git URL once GitLabKit is published.
        .package(path: "../swift-gitlab"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // For `ErrorExplain`'s `ClientError` handling in the CLI (GitLabKit's error type).
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "laconic-review",
            dependencies: [
                "LaconicReviewCore",
                "GitLabConnection",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ]
        ),
        .target(
            name: "LaconicReviewCore"
        ),
        .target(
            name: "GitLabConnection",
            dependencies: [
                "LaconicReviewCore",
                // Façade (adds `Client` conveniences) + the generated client/types.
                .product(name: "GitLabKit", package: "swift-gitlab"),
                .product(name: "GitLabOpenAPI", package: "swift-gitlab"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ]
        ),
        .testTarget(
            name: "LaconicReviewCoreTests",
            dependencies: ["LaconicReviewCore"]
        ),
        .testTarget(
            name: "GitLabConnectionTests",
            dependencies: ["GitLabConnection", "LaconicReviewCore"]
        ),
    ]
)
