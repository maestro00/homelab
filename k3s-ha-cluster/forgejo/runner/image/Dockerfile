FROM node:20-alpine

RUN apk add --no-cache \
    git \
    bash \
    curl \
    jq

# kaniko — daemon-less image builds for job containers that have no Docker
# daemon access. Official releases ship no standalone binaries, so the static
# executor is copied out of the debug image.
COPY --from=gcr.io/kaniko-project/executor:debug /kaniko/executor /usr/local/bin/kaniko

RUN curl -LO https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl \
    && install -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Helm — pinned to the version used for local manual deploys
RUN curl -Ls https://get.helm.sh/helm-v3.18.4-linux-amd64.tar.gz | tar -xz -C /tmp \
    && install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm \
    && rm -rf /tmp/linux-amd64

COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/node-disk-alert.sh
