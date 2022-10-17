//
//  Workspace.swift
//  valenciaManifests
//
//  Created by Eric Rabil on 10/17/22.
//

import ProjectDescription
import ProjectDescriptionHelpers

let workspace = Workspace(name: "Valencia", projects: [
    ".",
    "SPM"
], additionalFiles: [.folderReference(path: "docs")])
