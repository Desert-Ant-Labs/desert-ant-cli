#!/bin/sh
# Install desertant, the Desert Ant Labs CLI, from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh | sh
#
# The release lands in DESERTANT_HOME (~/.local/share/desertant) with the files the
# binary needs beside it; `desertant` and the `da` alias are symlinks in DESERTANT_BIN
# (~/.local/bin). DESERTANT_VERSION=v0.2.0 pins a release. `desertant update` runs
# this script again.
set -eu

repo="Desert-Ant-Labs/desert-ant-cli"
bin="${DESERTANT_BIN:-$HOME/.local/bin}"
home="${DESERTANT_HOME:-$HOME/.local/share/desertant}"
version="${DESERTANT_VERSION:-latest}"

case "$(uname -s)" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) echo "desertant has no build for $(uname -s)." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) arch="arm64" ;;
  x86_64 | amd64) arch="x86_64" ;;
  *) echo "desertant has no build for $(uname -m)." >&2; exit 1 ;;
esac

asset="desertant-$os-$arch.tar.gz"
if [ "$version" = "latest" ]; then
  base="https://github.com/$repo/releases/latest/download"
else
  base="https://github.com/$repo/releases/download/$version"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $asset."
if ! curl -fsSL -o "$tmp/$asset" "$base/$asset"; then
  echo "Could not download $base/$asset." >&2
  echo "Build from source instead: git clone https://github.com/$repo && cd desert-ant-cli && Tools/install" >&2
  exit 1
fi
if ! curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt"; then
  echo "Could not download $base/checksums.txt." >&2
  exit 1
fi

expected="$(grep " $asset\$" "$tmp/checksums.txt" | cut -d' ' -f1)"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/$asset" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$tmp/$asset" | cut -d' ' -f1)"
fi
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
  echo "The checksum of $asset does not match checksums.txt. Not installing." >&2
  exit 1
fi

mkdir -p "$home" "$bin"
tar -xzf "$tmp/$asset" -C "$home"
chmod 755 "$home/desertant"
ln -sf "$home/desertant" "$bin/desertant"
ln -sf "$home/desertant" "$bin/da"

echo "Installed desertant $("$bin/desertant" --version) into $bin."
case ":$PATH:" in
  *":$bin:"*) ;;
  *) echo "Add $bin to your PATH to run it as desertant or da." ;;
esac
