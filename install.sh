#!/bin/sh
# Build the render program and copy the package into the Emacs directory.
# The library goes into <dir>/lisp, and the program goes into <dir>/bin.
# The default directory is ~/.emacs.d. Set EMACS_DIR to use another one.
# This script runs on macOS, Linux, and Git Bash on Windows.

set -eu

cd "$(dirname "$0")"

emacs_dir="${EMACS_DIR:-$HOME/.emacs.d}"

cargo build --release

program=target/release/story-mapping-render
if [ -f "$program.exe" ]; then
  program="$program.exe"
fi

mkdir -p "$emacs_dir/lisp" "$emacs_dir/bin"
cp story-mapping.el "$emacs_dir/lisp/"
cp "$program" "$emacs_dir/bin/"

echo "Installed story-mapping.el into $emacs_dir/lisp"
echo "Installed $(basename "$program") into $emacs_dir/bin"
