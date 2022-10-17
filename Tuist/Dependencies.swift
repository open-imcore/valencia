//
//  Dependencies.swift
//  Config
//
//  Created by Eric Rabil on 10/17/22.
//

import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init([
        .remote(url: "https://github.com/LucasXu0/fishhook", requirement: .branch("support_spm")),
        .remote(url: "https://github.com/apple/swift-log", requirement: .upToNextMajor(from: "1.0.0"))
    ]),
    platforms: [.macOS]
)
