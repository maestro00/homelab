FROM node:22-slim

# Pin the opencode-ai version at build time so the tag is reproducible.
ARG OPENCODE_VERSION=1.18.25

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "opencode-ai@${OPENCODE_VERSION}"

# `node:22-slim` already ships a non-root `node` user at UID 1000, so use
# 1001 for `opencode` to avoid the collision.
RUN useradd -m -u 1001 opencode
USER opencode
ENV HOME=/home/opencode
EXPOSE 4096
