// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIQuotaWidget",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AIQuotaWidget",
            path: "Sources/AIQuotaWidget",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "AIQuotaWidgetTests",
            dependencies: ["AIQuotaWidget"],
            path: "Tests/AIQuotaWidgetTests"
        )
    ]
)
