#!/usr/bin/env bash
set -euo pipefail

# 00_check_prerequisites.sh
# Read-only. Confirms Xcode Command Line Tools, Homebrew, and git are
# present before anything is installed. Run this first.

echo "==> Checking prerequisites"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "✘ Xcode Command Line Tools not found."
  echo "  Install with: xcode-select --install"
  exit 1
else
  echo "✔ Xcode Command Line Tools present"
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "✘ Homebrew not found."
  echo "  Install from https://brew.sh, then re-run this script."
  exit 1
else
  echo "✔ Homebrew present ($(brew --version | head -1))"
fi

if ! command -v git >/dev/null 2>&1; then
  echo "✘ git not found."
  exit 1
else
  echo "✔ git present ($(git --version))"
fi

echo "==> All prerequisites satisfied. Proceed to 01_install_system_deps.sh"
