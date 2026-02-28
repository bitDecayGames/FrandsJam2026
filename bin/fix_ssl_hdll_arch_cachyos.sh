#!/usr/bin/env bash
#
# fix_ssl_hdll_arch_cachyos.sh — Replace Lime's bundled ssl.hdll with one
# linked against the system's mbedtls2. Fixes "Failed to load library ssl.hdll"
# on Arch-based distros (CachyOS, Manjaro, etc.) where mbedtls2 sonames differ
# from what Lime's pre-built binary expects.
#
# Usage: ./bin/fix_ssl_hdll_arch_cachyos.sh
#
# Prerequisites: hashlink package (preferred) or gcc + mbedtls2
#

set -euo pipefail

PREFIX="[fix_ssl_hdll]"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

log()  { echo "$PREFIX $*"; }
err()  { echo "$PREFIX ERROR: $*" >&2; }
die()  { err "$@"; exit 1; }

# ---------- 1. Find Lime template directories ----------

LIME_DIRS=()
for dir in "$PROJECT_DIR"/.haxelib/lime/*/templates/bin/hl/Linux64; do
    if [[ -d "$dir" && -f "$dir/ssl.hdll" ]]; then
        LIME_DIRS+=("$dir")
    fi
done

if [[ ${#LIME_DIRS[@]} -eq 0 ]]; then
    die "Could not find any Lime Linux64 HL template directories under .haxelib/lime/"
fi

# ---------- 2. Check which ones need fixing ----------

NEEDS_FIX=()
for dir in "${LIME_DIRS[@]}"; do
    MISSING=$(ldd "$dir/ssl.hdll" 2>&1 | grep "not found" || true)
    if [[ -n "$MISSING" ]]; then
        NEEDS_FIX+=("$dir")
        log "Broken: $dir/ssl.hdll"
        echo "$MISSING" | sed "s/^/  /"
    else
        log "OK:     $dir/ssl.hdll"
    fi
done

if [[ ${#NEEDS_FIX[@]} -eq 0 ]]; then
    log "All ssl.hdll files resolve correctly — nothing to do."
    exit 0
fi

# ---------- 3. Resolve a working ssl.hdll replacement ----------

REPLACEMENT=""

# 3a. Try system hashlink package
SYSTEM_SSL="/usr/lib/ssl.hdll"
if [[ -f "$SYSTEM_SSL" ]]; then
    SYS_MISSING=$(ldd "$SYSTEM_SSL" 2>&1 | grep "not found" || true)
    if [[ -z "$SYS_MISSING" ]]; then
        log "Using system ssl.hdll from $SYSTEM_SSL"
        REPLACEMENT="$SYSTEM_SSL"
    else
        log "System ssl.hdll also has unresolved deps — skipping."
    fi
fi

# 3b. Fallback: build from HashLink source
if [[ -z "$REPLACEMENT" ]]; then
    log "Building ssl.hdll from HashLink source..."

    for cmd in gcc make git pkg-config; do
        if ! command -v "$cmd" &>/dev/null; then
            die "Missing build dependency: $cmd"
        fi
    done

    # Find mbedtls2 headers
    MBEDTLS_INCLUDE=""
    if [[ -d /usr/include/mbedtls2 ]]; then
        MBEDTLS_INCLUDE="/usr/include/mbedtls2"
    elif pkg-config --exists mbedtls2 2>/dev/null; then
        MBEDTLS_INCLUDE=$(pkg-config --cflags-only-I mbedtls2 | sed 's/-I//')
    elif [[ -f /usr/include/mbedtls/ssl.h ]]; then
        MBEDTLS_INCLUDE="/usr/include"
    else
        die "mbedtls2 headers not found. Install mbedtls2 (Arch: sudo pacman -S mbedtls2)"
    fi

    MBEDTLS_LIB=""
    if [[ -d /usr/lib/mbedtls2 ]]; then
        MBEDTLS_LIB="/usr/lib/mbedtls2"
    elif pkg-config --exists mbedtls2 2>/dev/null; then
        MBEDTLS_LIB=$(pkg-config --libs-only-L mbedtls2 | sed 's/-L//')
    fi

    BUILD_DIR=$(mktemp -d)
    trap 'rm -rf "$BUILD_DIR"' EXIT

    log "Cloning HashLink source..."
    git clone --depth 1 https://github.com/HaxeFoundation/hashlink.git "$BUILD_DIR/hashlink" 2>&1 | tail -1

    HL_SRC="$BUILD_DIR/hashlink"
    SSL_SRC="$HL_SRC/libs/ssl"

    if [[ ! -d "$SSL_SRC" ]]; then
        die "ssl source not found in HashLink repo at libs/ssl/"
    fi

    log "Compiling ssl.hdll..."

    CFLAGS="-shared -fPIC -O2 -I$HL_SRC/src -I$MBEDTLS_INCLUDE"
    LDFLAGS="-lhl -lmbedtls -lmbedx509 -lmbedcrypto"

    if [[ -n "$MBEDTLS_LIB" ]]; then
        LDFLAGS="-L$MBEDTLS_LIB $LDFLAGS"
    fi

    gcc $CFLAGS "$SSL_SRC"/ssl.c -o "$BUILD_DIR/ssl.hdll" $LDFLAGS

    if [[ ! -f "$BUILD_DIR/ssl.hdll" ]]; then
        die "Compilation failed — ssl.hdll not produced."
    fi

    BUILD_MISSING=$(ldd "$BUILD_DIR/ssl.hdll" 2>&1 | grep "not found" || true)
    if [[ -n "$BUILD_MISSING" ]]; then
        die "Built ssl.hdll still has unresolved deps:\n$BUILD_MISSING"
    fi

    REPLACEMENT="$BUILD_DIR/ssl.hdll"
fi

# ---------- 4. Replace broken ssl.hdll files ----------

for dir in "${NEEDS_FIX[@]}"; do
    TARGET="$dir/ssl.hdll"
    cp "$TARGET" "$TARGET.bak"
    cp "$REPLACEMENT" "$TARGET"
    log "Fixed: $TARGET (backup at ssl.hdll.bak)"

    VERIFY=$(ldd "$TARGET" 2>&1 | grep "not found" || true)
    if [[ -n "$VERIFY" ]]; then
        err "Replacement at $TARGET still has unresolved deps — restoring backup."
        mv "$TARGET.bak" "$TARGET"
    fi
done

log "Done! All broken ssl.hdll files have been replaced."
