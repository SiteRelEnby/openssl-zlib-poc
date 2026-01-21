#!/bin/bash
# Build and run the OpenSSL zlib DSO init bug PoC

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    echo "Usage: $0 [buggy|fixed|both]"
    echo ""
    echo "  buggy  - Build and run with original buggy OpenSSL"
    echo "  fixed  - Build and run with patched OpenSSL"
    echo "  both   - Build and run both versions to compare"
    exit 1
}

build_and_run() {
    local mode=$1
    local fix_flag=0
    local image_name="openssl-zlib-poc-${mode}"

    if [ "$mode" = "fixed" ]; then
        fix_flag=1
    fi

    echo "=============================================="
    echo "Building ${mode^^} version..."
    echo "=============================================="

    docker build \
        --build-arg FIX=$fix_flag \
        -t "$image_name" \
        -f Dockerfile \
        . 2>&1 | tail -20

    echo ""
    echo "=============================================="
    echo "Running ${mode^^} version..."
    echo "=============================================="
    echo ""

    # Run with timeout in case it hangs
    docker run --rm "$image_name" || true

    echo ""
}

case "${1:-both}" in
    buggy)
        build_and_run buggy
        ;;
    fixed)
        build_and_run fixed
        ;;
    both)
        build_and_run buggy
        echo ""
        echo "========================================================"
        echo ""
        build_and_run fixed
        ;;
    *)
        usage
        ;;
esac
