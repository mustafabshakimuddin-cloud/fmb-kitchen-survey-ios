// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KitchenSurvey",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .executable(name: "KitchenSurvey", targets: ["KitchenSurvey"])
    ],
    dependencies: [
        .package(url: "https://github.com/google/generative-ai-swift", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "KitchenSurvey",
            dependencies: [
                .product(name: "GoogleGenerativeAI", package: "generative-ai-swift")
            ],
            path: "."
        )
    ]
)
