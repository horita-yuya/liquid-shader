// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Liquid",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "Liquid",
            targets: ["Liquid"]
        ),
    ],
    targets: [
        .target(
            name: "Liquid"
        ),
    ]
)
