FROM node:20-alpine

RUN apk add --no-cache \
    git \
    bash \
    curl

RUN curl -LO https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl \
    && install -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl
