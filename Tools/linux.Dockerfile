# The Linux build image for Tools/linux, CI, and the release: the Swift image the
# release builds in, plus what Tools/check, Tools/package, and the tests need. Jammy's
# glibc 2.35 is the binary's floor. ffmpeg is here for the media tests; the binary
# only looks for it at run time.
FROM swift:6.2-jammy
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      git curl ca-certificates python3 binutils file ffmpeg make xz-utils \
      libcurl4-openssl-dev libssl-dev libxml2-dev zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Upstream curl 7.81.0, jammy's version, built only to link against. Debian builds
# libcurl with versioned symbols, so a binary linked against it asks for
# CURL_OPENSSL_4, and Fedora, openSUSE, and Arch, whose libcurl has no versions,
# print a loader warning on every run. Upstream curl has none, so the binary binds
# to any distribution's libcurl.so.4. Nothing from here ships.
RUN cd /tmp \
 && curl -fsSLO https://curl.se/download/curl-7.81.0.tar.xz \
 && echo "a067b688d1645183febc31309ec1f3cdce9213d02136b6a6de3d50f69c95a7d3  curl-7.81.0.tar.xz" | sha256sum -c - \
 && tar -xJf curl-7.81.0.tar.xz \
 && cd curl-7.81.0 \
 && CC=clang ./configure -q --prefix=/opt/curl-link --with-openssl --disable-static \
      --without-libpsl --disable-ldap --disable-manual >/dev/null \
 && make -s -j"$(nproc)" >/dev/null \
 && make -s install >/dev/null \
 && cd / && rm -rf /tmp/curl-7.81.0*
