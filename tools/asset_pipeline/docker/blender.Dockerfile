# Headless Blender for `asset cleanup` when Blender is not installed locally.
# Build with `uv run asset blender-image build` (passes the version from versions.yaml).
FROM debian:bookworm-slim
ARG BLENDER_VERSION=4.5.9
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl xz-utils libxi6 libxrender1 libxkbcommon0 libxxf86vm1 libxfixes3 libgl1 libsm6 \
        libegl1 libx11-6 libxext6 libgomp1 \
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    minor="${BLENDER_VERSION%.*}"; \
    base="https://download.blender.org/release/Blender${minor}"; \
    curl -sSL --fail -o /tmp/blender.tar.xz "${base}/blender-${BLENDER_VERSION}-linux-x64.tar.xz"; \
    curl -sSL --fail -o /tmp/blender.sha256 "${base}/blender-${BLENDER_VERSION}.sha256"; \
    expected="$(grep "blender-${BLENDER_VERSION}-linux-x64.tar.xz" /tmp/blender.sha256 | cut -d' ' -f1)"; \
    echo "${expected}  /tmp/blender.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/blender; \
    tar -xf /tmp/blender.tar.xz -C /opt/blender --strip-components=1; \
    ln -s /opt/blender/blender /usr/local/bin/blender; \
    rm /tmp/blender.tar.xz /tmp/blender.sha256
# CPU only, no GUI. Runs as whatever --user the caller passes, so HOME must be writable.
ENV HOME=/tmp
ENTRYPOINT ["blender"]
