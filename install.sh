#!/bin/sh
# Install desertant, the Desert Ant Labs CLI, from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh | sh
#
# The release lands in DESERTANT_HOME (~/.local/share/desertant) with the files the
# binary needs beside it; `desertant` and the `da` alias are symlinks in DESERTANT_BIN
# (~/.local/bin). DESERTANT_VERSION=v0.2.0 pins a release, and DESERTANT_BASE_URL
# installs from another folder of release assets. `desertant update` runs this
# script again.
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
# A shell under Rosetta reports x86_64 on an Apple silicon Mac, which runs the arm64 build.
if [ "$os" = "darwin" ] && [ "$arch" = "x86_64" ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    arch="arm64"
  else
    echo "desertant needs an Apple silicon Mac. This Mac has an Intel processor." >&2
    exit 1
  fi
fi

# The Linux build links glibc 2.35 and loads the system's libcurl. Alpine and other
# musl systems have neither, and an older glibc stops the binary before it prints
# anything.
glibc_floor="2.35"
if [ "$os" = "linux" ]; then
  if ldd --version 2>&1 | grep -qi musl || ls /lib/ld-musl-* >/dev/null 2>&1; then
    echo "desertant needs glibc $glibc_floor or later, and this system uses musl (Alpine and similar)." >&2
    exit 1
  fi
  # "glibc 2.35" -> major 2, minor 35, compared as numbers.
  glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
  glibc="${glibc#glibc }"
  have_major="${glibc%%.*}" have_minor="${glibc#*.}" have_minor="${have_minor%%.*}"
  need_major="${glibc_floor%%.*}" need_minor="${glibc_floor#*.}"
  case "$have_major$have_minor" in
    '' | *[!0-9]*) ;;
    *)
      if [ "$have_major" -lt "$need_major" ] || { [ "$have_major" -eq "$need_major" ] && [ "$have_minor" -lt "$need_minor" ]; }; then
        echo "desertant needs glibc $glibc_floor or later, and this system has $glibc." >&2
        exit 1
      fi
      ;;
  esac
fi

asset="desertant-$os-$arch.tar.gz"
if [ -n "${DESERTANT_BASE_URL:-}" ]; then
  base="$DESERTANT_BASE_URL"
elif [ "$version" = "latest" ]; then
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

# Run the new binary before it replaces anything, so a missing library leaves the
# installed copy as it was.
mkdir -p "$tmp/new"
tar -xzf "$tmp/$asset" -C "$tmp/new"
chmod 755 "$tmp/new/desertant"
if ! installed="$("$tmp/new/desertant" --version 2>"$tmp/error")"; then
  echo "The downloaded desertant did not start:" >&2
  sed 's/^/  /' "$tmp/error" >&2
  if grep -q "libcurl" "$tmp/error"; then
    echo "Install libcurl, which the curl package brings on most systems, and run this script again." >&2
  elif grep -q "GLIBCXX" "$tmp/error"; then
    echo "desertant needs libstdc++ from GCC 12 or later, and this system's is older." >&2
  fi
  exit 1
fi

mkdir -p "$home" "$bin"
rm -rf "$home"/*.bundle "$home"/*.resources
cp -R "$tmp/new/." "$home/"
ln -sf "$home/desertant" "$bin/desertant"
ln -sf "$home/desertant" "$bin/da"

echo "Installed desertant $installed into $bin."
case ":$PATH:" in
  *":$bin:"*) ;;
  *)
    echo "Add $bin to your PATH to run it as desertant or da:"
    case "${SHELL:-}" in
      */fish) echo "  fish_add_path $bin" ;;
      */zsh) echo "  echo 'export PATH=\"$bin:\$PATH\"' >> ~/.zshrc && exec zsh" ;;
      */bash) echo "  echo 'export PATH=\"$bin:\$PATH\"' >> ~/.bashrc && exec bash" ;;
      *) echo "  export PATH=\"$bin:\$PATH\"" ;;
    esac
    ;;
esac
if [ "$os" = "linux" ] && ! command -v ffmpeg >/dev/null 2>&1; then
  echo "Install ffmpeg to read audio other than WAV, video, and images."
fi
