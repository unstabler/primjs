#!/usr/bin/env python3
# Copyright 2026 The Lynx Authors. All rights reserved.
# Licensed under the Apache License Version 2.0 that can be found in the
# LICENSE file in the root directory of this source tree.

"""
Regenerates spm/include, the public header directory of the PrimJS Swift
package.

A SwiftPM target exposes a single public header directory, while PrimJS
headers are included relative to several roots (see INCLUDE_ROOTS). This
script fills spm/include with relative symlinks so that every include form
used with those roots resolves from that one directory.

usage: update_spm_include.py [--check]

With --check, nothing is written and the exit status is 1 when spm/include
differs from what this script would generate.
"""

import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INCLUDE_DIR = os.path.join(ROOT, "spm", "include")

# Include roots that dependents (Lynx) add to their header search paths,
# mirroring the HEADER_SEARCH_PATHS used with the PrimJS pod.
#   (root, mode): mode "dirs" links the root's subdirectories,
#                 mode "headers" links the root's own *.h files.
INCLUDE_ROOTS = [
    ("src", "dirs"),
    ("src/interpreter", "dirs"),
    ("src/gc", "headers"),
    ("src/interpreter/quickjs/include", "headers"),
    ("src/napi", "headers"),
    ("src/napi/env", "headers"),
    ("src/napi/quickjs", "headers"),
    ("src/napi/jsc", "headers"),
]

# Subdirectories of a "dirs" root that are not exposed.
EXCLUDED_DIRS = {
    "src": {"wasm"},
    "src/interpreter": {"primjs"},
}


def expected_links():
    links = {}
    for root, mode in INCLUDE_ROOTS:
        root_path = os.path.join(ROOT, root)
        for name in sorted(os.listdir(root_path)):
            path = os.path.join(root_path, name)
            if mode == "dirs":
                if not os.path.isdir(path) or name in EXCLUDED_DIRS.get(root, set()):
                    continue
            elif not (os.path.isfile(path) and name.endswith(".h")):
                continue
            if name in links:
                raise Exception("%s is provided by both %s and %s" % (name, links[name], path))
            links[name] = os.path.relpath(path, INCLUDE_DIR)
    return links


def current_links():
    links = {}
    if not os.path.isdir(INCLUDE_DIR):
        return links
    for name in os.listdir(INCLUDE_DIR):
        path = os.path.join(INCLUDE_DIR, name)
        links[name] = os.readlink(path) if os.path.islink(path) else None
    return links


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Only report whether spm/include is up to date.")
    args = parser.parse_args()

    expected = expected_links()
    if args.check:
        if current_links() != expected:
            print("spm/include is out of date. Run tools/ios_tools/update_spm_include.py.")
            return 1
        return 0

    if os.path.isdir(INCLUDE_DIR):
        shutil.rmtree(INCLUDE_DIR)
    os.makedirs(INCLUDE_DIR)
    for name, target in sorted(expected.items()):
        os.symlink(target, os.path.join(INCLUDE_DIR, name))
    print("Wrote %d entries to %s" % (len(expected), os.path.relpath(INCLUDE_DIR, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
