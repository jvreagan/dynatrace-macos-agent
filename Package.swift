// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DynatraceAgent",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DynatraceAgent",
            path: "Sources/DynatraceAgent",
            exclude: ["Resources/Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "Sources/DynatraceAgent/Resources/Info.plist"])
            ]
        )
    ]
)
