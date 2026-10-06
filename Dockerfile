FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Architecture used for kubectl / helm downloads: amd64 | arm64
ARG K8S_ARCH=amd64
# Leave KUBECTL_VERSION empty to use the latest stable release
ARG KUBECTL_VERSION=""
ARG HELM_VERSION=v3.16.4

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
      unzip \
      wget && \
    rm -rf /var/lib/apt/lists/*

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
    curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${K8S_ARCH}.tar.gz" | tar -xz -C /tmp; \
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
ENV PATH="${PATH}:/kaniko"
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG=/kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG=/kaniko/.config/gcloud/docker_credential_gcr_config.json

# Copy Needed Files from Kaniko Image
COPY --from=gcr.io/kaniko-project/executor /kaniko/executor /kaniko/executor
COPY --from=gcr.io/kaniko-project/executor /kaniko/docker-credential-gcr /kaniko/docker-credential-gcr
COPY --from=gcr.io/kaniko-project/executor /kaniko/docker-credential-ecr-login /kaniko/docker-credential-ecr-login
COPY --from=gcr.io/kaniko-project/executor /kaniko/docker-credential-acr-env /kaniko/docker-credential-acr-env
COPY --from=gcr.io/kaniko-project/executor /kaniko/.docker /kaniko/.docker

# Generate latest ca-certificates
RUN update-ca-certificates && \
    mkdir -p /kaniko/ssl/certs/ && \
    cat /etc/ssl/certs/*.crt > /kaniko/ssl/certs/ca-certificates.crt

ENTRYPOINT [ "./start.sh" ]
