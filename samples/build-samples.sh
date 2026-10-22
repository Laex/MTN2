#!/usr/bin/env bash
# Builds the demo plugins in samples/plugins for Linux and, with --install DIR,
# copies them to DIR (the plugins folder next to mtn2-tui / mtn2-sdl), where the
# host loads them at startup.
#
#   ./samples/build-samples.sh                       # build every sample whose toolchain is found
#   ./samples/build-samples.sh --install bin/linux64/plugins
#   ./samples/build-samples.sh --only mtn.demo.cpp,mtn.demo.go.wasm
#
# Each sample is built into samples/.build-linux/<id>/ (ignored by git). A sample
# whose toolchain is missing is skipped with a note, not a failure.
#
#   mtn.demo.cpp        C++    g++
#   mtn.demo.texttools  C++    g++
#   mtn.demo.panelkit   Rust   cargo (serde_json)
#   mtn.demo.highlight  Rust   cargo
#   mtn.demo.img        Rust   cargo (image crate)
#   mtn.demo.rs         Rust   cargo
#   mtn.demo.go         Go     go + gcc (cgo, -buildmode=c-shared)
#   mtn.demo.wc         Go     go (GOOS=wasip1, needs "wasi": true in plugin.json)
#   mtn.demo.go.wasm    Go     go (GOOS=wasip1)
#   mtn.demo.wat        WAT    nothing: the host assembles the text at load time
#   mtn.wasm.demo       WAT    nothing, as mtn.demo.wat
#
# Not built here: mtn.demo.video (Media Foundation), mtn.demo.nativeview (a native
# Windows window) and mtn.demo.pas (build it with dcclinux64 as the program is built).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLES="$HERE/plugins"
INCLUDE="$HERE/include"
BUILD="$HERE/.build-linux"
# The Rust intermediate files stay in the cache of the user: a checkout on a mounted
# Windows drive (/mnt/d) is slow for the many small files cargo writes.
CARGO_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mtn2-samples/cargo"
ONLY=""
INSTALL=""

while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="$2"; shift 2 ;;
        --install) INSTALL="$2"; shift 2 ;;
        *) echo "usage: $0 [--only id,id] [--install DIR]" >&2; exit 2 ;;
    esac
done

# Toolchains installed for the user (rustup, a Go tarball) are found without a login shell.
for dir in "$HOME/.cargo/bin" "$HOME/.local/go/bin" /usr/local/go/bin; do
    if [ -d "$dir" ]; then PATH="$PATH:$dir"; fi
done

have() { command -v "$1" >/dev/null 2>&1; }
want() { [ -z "$ONLY" ] || case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

stage() {
    mkdir -p "$BUILD/$1"
    cp -f "$SAMPLES/$1/plugin.json" "$BUILD/$1/"
    if [ -d "$SAMPLES/$1/resource" ]; then cp -rf "$SAMPLES/$1/resource" "$BUILD/$1/"; fi
}

skip() { echo "skip $1 : $2"; return 1; }

build_cpp() {
    have g++ || skip "$1" "g++ not found" || return 1
    stage "$1"
    g++ -shared -fPIC -O2 -std=c++17 -I"$INCLUDE" "$SAMPLES/$1/plugin.cpp" -o "$BUILD/$1/$2.so" || return 2
}

build_cargo() {
    have cargo || skip "$1" "cargo not found" || return 1
    stage "$1"
    (cd "$SAMPLES/$1" && CARGO_TARGET_DIR="$CARGO_CACHE/$1" cargo build --release) || return 2
    cp -f "$CARGO_CACHE/$1/release/lib$2.so" "$BUILD/$1/" || return 2
}

build_go_wasm() {
    have go || skip "$1" "go not found" || return 1
    stage "$1"
    (cd "$SAMPLES/$1" && GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o "$BUILD/$1/plugin.wasm" .) || return 2
}

build_go() {
    have go || skip "$1" "go not found" || return 1
    have gcc || skip "$1" "gcc is needed for cgo" || return 1
    stage "$1"
    (cd "$SAMPLES/$1" && CGO_ENABLED=1 go build -buildmode=c-shared -o "$BUILD/$1/mtn_demo_go.so" .) || return 2
    rm -f "$BUILD/$1/mtn_demo_go.h"
}

build_wat() {
    stage "$1"
    cp -f "$SAMPLES/$1/plugin.wat" "$BUILD/$1/"
}

built=""
failed=0

# A build function returns 0 when built, 1 when skipped (no toolchain) and 2 when the build failed.
run() {
    local id="$1"; shift
    want "$id" || return 0
    "$@"
    case $? in
        0) echo "OK: built $id"; built="$built $id" ;;
        1) : ;;
        *) echo "FAILED: $id" >&2; failed=1 ;;
    esac
}

run mtn.demo.cpp build_cpp mtn.demo.cpp mtn_demo_cpp
run mtn.demo.texttools build_cpp mtn.demo.texttools mtn_demo_texttools
run mtn.demo.panelkit build_cargo mtn.demo.panelkit mtn_demo_panelkit
run mtn.demo.highlight build_cargo mtn.demo.highlight mtn_demo_highlight
run mtn.demo.img build_cargo mtn.demo.img mtn_demo_img
run mtn.demo.rs build_cargo mtn.demo.rs mtn_demo_rs
run mtn.demo.go build_go mtn.demo.go
run mtn.demo.wc build_go_wasm mtn.demo.wc
run mtn.demo.go.wasm build_go_wasm mtn.demo.go.wasm
run mtn.demo.wat build_wat mtn.demo.wat
run mtn.wasm.demo build_wat mtn.wasm.demo

if [ -n "$INSTALL" ]; then
    for id in $built; do
        mkdir -p "$INSTALL/$id"
        cp -rf "$BUILD/$id/." "$INSTALL/$id/"
        echo "OK: installed $id -> $INSTALL/$id"
    done
fi

exit $failed
