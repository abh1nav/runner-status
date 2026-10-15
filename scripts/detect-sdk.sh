#!/bin/bash
# Prints the macOS SDK path to compile against, or nothing to use the active default.
#
# On macOS 27+ SDKs SwiftUI's @State is a macro whose plugin ships only with Xcode, so with
# just Command Line Tools the default SDK can't build the app. Probe-compile a @State view
# against the default SDK, then every installed versioned SDK newest-first, and print the
# first that works.
#
# Usage: detect-sdk.sh <target-triple>
set -u

target=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/probe.swift" <<'EOF'
import SwiftUI
struct Probe: View {
    @State private var x = 0
    var body: some View { Text("\(x)") }
}
EOF

probe() {
    swiftc -typecheck -target "$target" ${1:+-sdk "$1"} "$tmp/probe.swift" >/dev/null 2>&1
}

if probe ""; then
    exit 0
fi

sdks_dir=$(dirname "$(xcrun --sdk macosx --show-sdk-path)")
for name in $(ls "$sdks_dir" | grep -E '^MacOSX[0-9][0-9.]*\.sdk$' | sort -rV); do
    if probe "$sdks_dir/$name"; then
        echo "$sdks_dir/$name"
        exit 0
    fi
done

echo "warning: no installed macOS SDK can compile SwiftUI @State; install Xcode" >&2
