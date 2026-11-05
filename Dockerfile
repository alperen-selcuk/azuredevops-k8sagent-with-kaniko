# Kaniko tag: "latest" unless overridden with --build-arg KANIKO_VERSION=v1.x.y
ARG KANIKO_VERSION=latest
# Toolchain versions (override with --build-arg)
ARG NODE_VERSION=20
ARG MAVEN_VERSION=3.9
ARG DOTNET_SDK_VERSION=8.0

FROM gcr.io/kaniko-project/executor:${KANIKO_VERSION} AS kaniko
FROM node:${NODE_VERSION}-bookworm-slim AS node
FROM maven:${MAVEN_VERSION}-eclipse-temurin-17 AS maven

# Ubuntu 22.04 (jammy) based image with the .NET SDK preinstalled
FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_SDK_VERSION}-jammy

ENV DEBIAN_FRONTEND=noninteractive

# Architecture used for kubectl / helm downloads: amd64 | arm64
ARG K8S_ARCH=amd64
# Leave empty to use the latest release; set to pin a version (e.g. v1.x.y / v3.x.y)
ARG KUBECTL_VERSION=""
ARG HELM_VERSION=""
# Leave empty to use the latest Azure Pipelines agent; set to pin (e.g. 4.x.y)
ARG RUNNER_VERSION=""
ENV AZP_AGENT_VERSION=${RUNNER_VERSION}

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y -qq --no-install-recommends \
      apt-transport-https \
      apt-utils \
      ca-certificates \
      curl \
      git \
      iputils-ping \
      jq \
      lsb-release \
      software-properties-common \
      libicu70 \
      build-essential \
      python3 \
      openjdk-17-jdk-headless \
      unzip \
      wget && \
    ln -s "$(dirname "$(dirname "$(readlink -f "$(which java)")")")" /usr/lib/jvm/default-java && \
    rm -rf /var/lib/apt/lists/*

# Java is required by the SonarQube scanner tasks (also detected by the agent as the "java" capability)
ENV JAVA_HOME=/usr/lib/jvm/default-java

# Node.js + npm (copied from the official image, glibc compatible with jammy)
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    ln -s ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack

# Maven (uses the JDK installed above)
COPY --from=maven /usr/share/maven /usr/share/maven
RUN ln -s /usr/share/maven/bin/mvn /usr/local/bin/mvn
ENV MAVEN_HOME=/usr/share/maven

RUN set -eux; dotnet --version; node -v; npm -v; java -version; mvn -v

# Install powershell
RUN wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y -qq --no-install-recommends powershell && \
    rm -rf /var/lib/apt/lists/*

# Install az cli
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \
    rm -rf /var/lib/apt/lists/*

# Install kubectl (inside a pod it authenticates with the mounted ServiceAccount token)
RUN set -eux; \
    v="${KUBECTL_VERSION:-$(curl -fsSL https://dl.k8s.io/release/stable.txt)}"; \
    curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${v}/bin/linux/${K8S_ARCH}/kubectl"; \
    curl -fsSL "https://dl.k8s.io/release/${v}/bin/linux/${K8S_ARCH}/kubectl.sha256" -o /tmp/kubectl.sha256; \
    echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c -; \
    chmod +x /usr/local/bin/kubectl; \
    rm /tmp/kubectl.sha256

# Install helm
RUN set -eux; \
    h="${HELM_VERSION:-$(curl -fsSL https://get.helm.sh/helm-latest-version)}"; \
    curl -fsSL "https://get.helm.sh/helm-${h}-linux-${K8S_ARCH}.tar.gz" | tar -xz -C /tmp; \
    mv "/tmp/linux-${K8S_ARCH}/helm" /usr/local/bin/helm; \
    rm -rf "/tmp/linux-${K8S_ARCH}"; \
    kubectl version --client; helm version

# Can be 'linux-x64', 'linux-arm64', 'linux-arm', 'rhel.6-x64'.
ENV TARGETARCH=linux-x64

WORKDIR /azp
COPY ./start.sh .
RUN chmod +x start.sh

ENV HOME=/root
ENV USER=root
ENV AZP_WORK=/azp/_work
ENV PATH="${PATH}:/kaniko:/root/.dotnet/tools"
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG=/kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG=/kaniko/.config/gcloud/docker_credential_gcr_config.json

# Copy Needed Files from Kaniko Image
COPY --from=kaniko /kaniko/executor /kaniko/executor
COPY --from=kaniko /kaniko/docker-credential-gcr /kaniko/docker-credential-gcr
COPY --from=kaniko /kaniko/docker-credential-ecr-login /kaniko/docker-credential-ecr-login
COPY --from=kaniko /kaniko/docker-credential-acr-env /kaniko/docker-credential-acr-env
COPY --from=kaniko /kaniko/.docker /kaniko/.docker

# Generate latest ca-certificates
RUN update-ca-certificates && \
    mkdir -p /kaniko/ssl/certs/ && \
    cat /etc/ssl/certs/*.crt > /kaniko/ssl/certs/ca-certificates.crt

ENTRYPOINT [ "./start.sh" ]
