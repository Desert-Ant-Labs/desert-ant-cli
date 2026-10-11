# The Linux build image for Tools/linux: the Swift image the release workflow
# builds in, plus what Tools/check, Tools/package, and the tests need. ffmpeg is
# here for the media tests; the binary only looks for it at run time.
FROM swift:6.2-jammy
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      git curl ca-certificates python3 binutils file ffmpeg \
      libcurl4-openssl-dev libxml2-dev zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
