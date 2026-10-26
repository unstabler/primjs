// swift-tools-version: 6.1
// Copyright 2026 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSE file in the root directory of this source tree.

// Swift Package Manager manifest that mirrors PrimJS.podspec.
//
// Differences from the podspec that come from SwiftPM itself:
// - CocoaPods compiles every subspec into one pod target and exposes all of
//   the pod's headers through a flattened header map. SwiftPM compiles each
//   target separately and exposes one public header directory per target, so
//   every header directory is listed explicitly in `headerSearchPaths` and the
//   include roots that dependents rely on are each owned by one target.
// - CocoaPods merges the preprocessor definitions of the subspecs in use into
//   the single pod target. The definitions below are therefore applied to
//   every target, because several of them change the layout of structures in
//   public headers (quickjs-inner.h). ENABLE_QUICKJS_DEBUGGER, which the
//   podspec enables through the quickjs_debugger subspec, is the
//   `QuickJSDebugger` trait.

import PackageDescription

/// Directories, relative to the package root, that hold headers included by
/// file name only. Mirrors the header map CocoaPods generates for the pod.
let headerDirectories = [
  "src",
  "src/basic/log",
  "src/gc",
  "src/inspector",
  "src/interpreter",
  "src/interpreter/quickjs/include",
  "src/napi",
  "src/napi/common",
  "src/napi/env",
  "src/napi/internal",
  "src/napi/jsc",
  "src/napi/quickjs",
  ".",
]

/// Builds the C/C++ settings of a target located `depth` directories below
/// the package root.
func primjsSettings(
  depth: Int,
  extraDefines: [(String, String?)] = []
) -> (c: [CSetting], cxx: [CXXSetting]) {
  let up = Array(repeating: "..", count: depth).joined(separator: "/")
  let paths = headerDirectories.map { dir -> String in
    dir == "." ? up : "\(up)/\(dir)"
  }
  let defines: [(String, String?)] = [
    ("OS_IOS", "1"),
    ("ENABLE_CODECACHE", nil),
    ("ENABLE_VIRTUAL_STACK", "1"),
    ("ENABLE_PRIMJS_SNAPSHOT", nil),
    ("ENABLE_COMPATIBLE_MM", nil),
    ("ENABLE_LEPUSNG", nil),
    ("LYNX_SIMPLIFY", "0"),
  ] + extraDefines

  var c: [CSetting] = paths.map { .headerSearchPath($0) }
  var cxx: [CXXSetting] = paths.map { .headerSearchPath($0) }
  for (name, value) in defines {
    c.append(.define(name, to: value))
    cxx.append(.define(name, to: value))
  }
  c.append(.define("ENABLE_QUICKJS_DEBUGGER", .when(traits: ["QuickJSDebugger"])))
  cxx.append(.define("ENABLE_QUICKJS_DEBUGGER", .when(traits: ["QuickJSDebugger"])))
  return (c, cxx)
}

func primjsTarget(
  name: String,
  dependencies: [Target.Dependency] = [],
  path: String,
  exclude: [String] = [],
  sources: [String]? = nil,
  publicHeadersPath: String = ".",
  extraDefines: [(String, String?)] = [("JSC_OBJC_API_ENABLED", "1")],
  linkerSettings: [LinkerSetting] = []
) -> Target {
  let depth = path.split(separator: "/").count
  let settings = primjsSettings(depth: depth, extraDefines: extraDefines)
  return .target(
    name: name,
    dependencies: dependencies,
    path: path,
    exclude: exclude,
    sources: sources,
    publicHeadersPath: publicHeadersPath,
    cSettings: settings.c,
    cxxSettings: settings.cxx,
    linkerSettings: linkerSettings
  )
}

let package = Package(
  name: "PrimJS",
  platforms: [.iOS(.v15)],
  products: [
    .library(
      name: "PrimJS",
      type: .dynamic,
      targets: [
        "PrimJSLog",
        "PrimJSGC",
        "PrimJSQuickJS",
        "PrimJSNapi",
        "PrimJSNapiEnv",
        "PrimJSNapiQuickJS",
        "PrimJSNapiJSC",
      ]
    )
  ],
  traits: [
    .trait(
      name: "QuickJSDebugger",
      description: "Builds the engine with ENABLE_QUICKJS_DEBUGGER, as the quickjs_debugger subspec does."
    )
  ],
  targets: [
    // Subspec "log". Owns the `src` include root.
    primjsTarget(
      name: "PrimJSLog",
      path: "src",
      sources: ["basic/log/logging.cc", "basic/log/primjs_logging.cc"]
    ),
    // Subspec "quickjs", split by include root: `src/gc` and
    // `src/interpreter`.
    primjsTarget(
      name: "PrimJSGC",
      dependencies: ["PrimJSLog"],
      path: "src/gc",
      exclude: ["BUILD.gn"]
    ),
    // embedded.S calls functions that quickjs declares QJS_HIDE. Xcode
    // prelinks each package target with `ld -r`, which turns hidden symbols
    // into local ones, so the assembly must be in the same target as the
    // quickjs sources.
    primjsTarget(
      name: "PrimJSQuickJS",
      dependencies: ["PrimJSLog", "PrimJSGC"],
      path: "src/interpreter",
      sources: ["quickjs/source", "primjs/ios/embedded.S"]
    ),
    // Subspec "napi/core".
    primjsTarget(
      name: "PrimJSNapi",
      path: "src/napi",
      sources: ["napi.cc", "napi_module.cc", "common/code_cache.cc"]
    ),
    // Subspec "napi/env".
    primjsTarget(
      name: "PrimJSNapiEnv",
      dependencies: ["PrimJSNapi"],
      path: "src/napi/env",
      exclude: ["BUILD.gn"]
    ),
    // Subspec "napi/quickjs".
    primjsTarget(
      name: "PrimJSNapiQuickJS",
      dependencies: ["PrimJSNapi", "PrimJSQuickJS"],
      path: "src/napi/quickjs",
      exclude: ["BUILD.gn"]
    ),
    // Subspec "napi/jsc".
    primjsTarget(
      name: "PrimJSNapiJSC",
      dependencies: ["PrimJSNapi", "PrimJSLog", "PrimJSQuickJS"],
      path: "src/napi/jsc",
      exclude: ["BUILD.gn"],
      extraDefines: [("JSC_OBJC_API_ENABLED", "0")],
      linkerSettings: [.linkedFramework("JavaScriptCore")]
    ),
  ],
  cxxLanguageStandard: .gnucxx17
)
