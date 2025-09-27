// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftTUI",
    
    platforms: [
         .macOS(.v11),
    ],
    
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name   : "SwiftTUI",
            targets: ["SwiftTUI"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "Trace", url: "https://github.com/SteveTrewick/Trace", from: "1.0.3"),
        .package(name:"PosixInputStream", url: "https://github.com/SteveTrewick/PosixInputStream", from: "1.0.4"),
        .package(name: "SerialPort", url: "https://github.com/SteveTrewick/SerialPort", from: "1.0.5")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "SwiftTUI",
            dependencies: [
                .product(name: "Trace", package: "Trace", condition: .when(platforms: [.macOS])),
                .product(name: "PosixInputStream", package: "PosixInputStream", condition: .when(platforms: [.macOS])),
                .product(name: "SerialPort", package: "SerialPort", condition: .when(platforms: [.macOS]))
            ]),
        .testTarget(
            name: "SwiftTUITests",
            dependencies: ["SwiftTUI"]),
    ]
)
