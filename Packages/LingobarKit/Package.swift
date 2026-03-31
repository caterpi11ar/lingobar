// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LingobarKit",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "LingobarDomain", targets: ["LingobarDomain"]),
        .library(name: "LingobarApplication", targets: ["LingobarApplication"]),
        .library(name: "LingobarInfrastructure", targets: ["LingobarInfrastructure"]),
        .library(name: "LingobarTestSupport", targets: ["LingobarTestSupport"]),
        .executable(name: "LingobarVerification", targets: ["LingobarVerification"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "LingobarDomain"
        ),
        .target(
            name: "LingobarApplication",
            dependencies: ["LingobarDomain"]
        ),
        .target(
            name: "LingobarInfrastructure",
            dependencies: [
                "LingobarDomain",
                "LingobarApplication",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "LingobarTestSupport",
            dependencies: [
                "LingobarDomain",
                "LingobarApplication",
            ]
        ),
        .executableTarget(
            name: "LingobarVerification",
            dependencies: [
                "LingobarDomain",
                "LingobarApplication",
                "LingobarInfrastructure",
                "LingobarTestSupport",
            ]
        ),
        .testTarget(
            name: "LingobarDomainTests",
            dependencies: ["LingobarDomain"]
        ),
        .testTarget(
            name: "LingobarApplicationTests",
            dependencies: [
                "LingobarApplication",
                "LingobarDomain",
                "LingobarTestSupport",
            ]
        ),
        .testTarget(
            name: "LingobarInfrastructureTests",
            dependencies: [
                "LingobarInfrastructure",
                "LingobarApplication",
                "LingobarDomain",
                "LingobarTestSupport",
            ]
        ),
    ]
)
