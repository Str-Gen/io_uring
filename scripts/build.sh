#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
for package in linux_raw mojix io_uring; do
    pixi run mojo precompile -I . "$package" -o "build/$package.mojoc"
done
