#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift --version
swift build
