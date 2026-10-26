// swift-tools-version: 6.1
// Copyright 2026 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSE file in the root directory of this source tree.

// Swift Package Manager manifest that mirrors PrimJS.podspec.
//
// The package has a single target, as the pod has a single pod target:
// - Tuist and similar integrations turn each SwiftPM target into its own
//   framework, so more targets would mean more frameworks than pods.
// - Xcode prelinks each package target with `ld -r`, which turns hidden
//   symbols into local ones. Sources that call QJS_HIDE functions of another
//   part of the engine (embedded.S calls into quickjs) must share a target.
//
// A target exposes one public header directory, while dependents include
// PrimJS headers relative to several roots. spm/include holds symlinks that
// combine those roots; regenerate it with tools/ios_tools/update_spm_include.py
// when headers are added or removed.
//
// CocoaPods merges the preprocessor definitions of the subspecs in use into
// the pod target; the definitions below are those of the subspecs this
// manifest covers. The quickjs_debugger, quickjs_heapprofiler,
// quickjs_profiler and napi/adapter subspecs are not covered yet.

import PackageDescription

/// Directories holding headers that PrimJS sources include by file name
/// only, relative to the package root. Mirrors the header map CocoaPods
/// generates for the pod.
let headerSearchPaths = [
  ".",
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
]

let defines: [(String, String?)] = [
  ("OS_IOS", "1"),
  // The podspec sets 1 at the root and 0 in the napi/jsc subspec. It only
  // affects Objective-C code that includes JavaScriptCore headers, and
  // PrimJS has no Objective-C sources.
  ("JSC_OBJC_API_ENABLED", "1"),
  ("ENABLE_CODECACHE", nil),
  ("ENABLE_VIRTUAL_STACK", "1"),
  ("ENABLE_PRIMJS_SNAPSHOT", nil),
  ("ENABLE_COMPATIBLE_MM", nil),
  ("ENABLE_LEPUSNG", nil),
  ("LYNX_SIMPLIFY", "0"),
]

let package = Package(
  name: "PrimJS",
  platforms: [.iOS(.v15)],
  products: [
    .library(name: "PrimJS", targets: ["PrimJS"])
  ],
  targets: [
    .target(
      name: "PrimJS",
      path: ".",
      exclude: [
        "src/gc/BUILD.gn",
        "src/napi/env/BUILD.gn",
        "src/napi/jsc/BUILD.gn",
        "src/napi/quickjs/BUILD.gn",
      ],
      sources: [
        // Subspec "log".
        "src/basic/log/logging.cc",
        "src/basic/log/primjs_logging.cc",
        // Subspec "quickjs".
        "src/gc",
        "src/interpreter/quickjs/source",
        "src/interpreter/primjs/ios/embedded.S",
        // Subspec "napi/core".
        "src/napi/napi.cc",
        "src/napi/napi_module.cc",
        "src/napi/common/code_cache.cc",
        // Subspecs "napi/env", "napi/quickjs" and "napi/jsc".
        "src/napi/env",
        "src/napi/quickjs",
        "src/napi/jsc",
      ],
      publicHeadersPath: "spm/include",
      cSettings: headerSearchPaths.map { .headerSearchPath($0) }
        + defines.map { .define($0.0, to: $0.1) },
      cxxSettings: headerSearchPaths.map { .headerSearchPath($0) }
        + defines.map { .define($0.0, to: $0.1) },
      linkerSettings: [.linkedFramework("JavaScriptCore")]
    )
  ],
  cxxLanguageStandard: .gnucxx17
)
