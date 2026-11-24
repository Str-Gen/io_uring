#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
for test in tests/mojix/test_*.mojo tests/io_uring/test_*.mojo; do
    pixi run mojo run -D ASSERT=all -I . "$test"
done
