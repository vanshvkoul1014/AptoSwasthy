#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: AptoSwasthy is an iOS app and can only be built on macOS."
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools not found. Installing..."
  xcode-select --install
  echo "Finish the CLT install dialog, then re-run: ./setup.sh"
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

echo "Installing dependencies from Brewfile..."
brew bundle --file="$(pwd)/Brewfile"

echo "Generating Xcode project..."
cd AptoSwasthy
xcodegen generate

echo
echo "Done. Opening Xcode..."
open AptoSwasthy.xcodeproj
