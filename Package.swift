// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CursorQuotaWidget",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "CursorQuotaWidget",
            path: "Sources/CursorQuotaWidget",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CursorQuotaWidgetTests",
            dependencies: ["CursorQuotaWidget"],
            path: "Tests/CursorQuotaWidgetTests"
        )
    ]
)
