#!/usr/bin/env bash
# hadolint ignore=SC2086,DL3015,DL3008,DL3013,SC2015

set -euo pipefail

echo en_US.UTF-8 UTF-8 >> /etc/locale.gen

function install_gnupg() {
  apt-get update
  apt-get install -y --no-install-recommends gnupg
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${GIT_CORE_PPA_KEY} \
      || apt-key adv --keyserver pgp.mit.edu --recv-keys ${GIT_CORE_PPA_KEY} \
      || apt-key adv --keyserver keyserver.pgp.com --recv-keys ${GIT_CORE_PPA_KEY}
}

function install_main() {
  apt-get update
  apt-get install -y --no-install-recommends \
      gnupg \
      lsb-release \
      curl \
      tar \
      unzip \
      zip \
      apt-transport-https \
      ca-certificates \
      sudo \
      gpg-agent \
      software-properties-common \
      build-essential \
      zlib1g-dev \
      zstd \
      gettext \
      libcurl4-openssl-dev \
      inetutils-ping \
      jq \
      wget \
      dirmngr \
      openssh-client \
      locales \
      python3-pip \
      python3-setuptools \
      python3-venv \
      python3 \
      dumb-init \
      nodejs \
      rsync \
      libpq-dev \
      gosu \
      pkg-config
}

install_gnupg
install_main

DPKG_ARCH="$(dpkg --print-architecture)"
LSB_RELEASE_CODENAME="$(lsb_release --codename | cut -f2)"
sed -e 's/Defaults.*env_reset/Defaults env_keep = "HTTP_PROXY HTTPS_PROXY NO_PROXY FTP_PROXY http_proxy https_proxy no_proxy ftp_proxy"/' -i /etc/sudoers

function install_git() {
  ( [[ "${LSB_RELEASE_CODENAME}" == "focal" ]] \
   && (echo deb http://ppa.launchpad.net/git-core/ppa/ubuntu focal main>/etc/apt/sources.list.d/git-core.list ) || : )

  apt-get update

  ( apt-get install -y --no-install-recommends git \
   || apt-get install -t stable -y --no-install-recommends git )
}

function install_liblttng_ust() {
  ( [[ $(apt-cache search -n liblttng-ust0 | awk '{print $1}') == "liblttng-ust0" ]] \
    && apt-get install -y --no-install-recommends liblttng-ust0 || : )

  ( [[ $(apt-cache search -n liblttng-ust1 | awk '{print $1}') == "liblttng-ust1" ]] \
    && apt-get install -y --no-install-recommends liblttng-ust1 || : )
}

function install_awscli() {
  ( curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip -d /tmp/ \
    && /tmp/aws/install \
    && rm awscliv2.zip \
  ) \
    || pip3 install --no-cache-dir awscli
}

function install_gitlfs() {
  curl -s "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-${DPKG_ARCH}-v${GIT_LFS_VERSION}.tar.gz" -L -o /tmp/lfs.tar.gz \
    && tar -xzf /tmp/lfs.tar.gz -C /tmp \
    && /tmp/git-lfs-${GIT_LFS_VERSION}/install.sh \
    && rm -rf /tmp/lfs.tar.gz /tmp/git-lfs-${GIT_LFS_VERSION}
}

function install_docker() {
  distro=$(lsb_release -is | awk '{print tolower($0)}')
  mkdir -p /etc/apt/keyrings
  ( curl -fsSL https://download.docker.com/linux/${distro}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg )

  version=$(lsb_release -cs | sed 's/trixie\|n\/a/bookworm/g')
  ( echo "deb [arch=${DPKG_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distro} ${version} stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null )

  apt-get update
  apt-get install -y docker-ce docker-ce-cli docker-buildx-plugin containerd.io docker-compose-plugin --no-install-recommends --allow-unauthenticated

  echo -e '#!/bin/sh\ndocker compose --compatibility "$@"' > /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose
}

function install_container_tools() {
  ( [[ "${LSB_RELEASE_CODENAME}" == "focal" ]] \
    && ( echo "available in 20.10 and higher" \
    && echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_20.04/ /" \
      | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list \
    && curl -L "https://build.opensuse.org/projects/devel:kubic/signing_keys/download?kind=gpg" \
      | apt-key add - ) || : )

  apt-get update
  ( apt-get install -y --no-install-recommends podman buildah skopeo || : )
}

function install_githubcli() {
  GH_CLI_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/cli/cli/releases/latest \
      | jq -r '.tag_name' | sed 's/^v//g')

  GH_CLI_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/cli/cli/releases/latest \
      | jq ".assets[] | select(.name == \"gh_${GH_CLI_VERSION}_linux_${DPKG_ARCH}.deb\")" \
      | jq -r '.browser_download_url')

  curl -sSLo /tmp/ghcli.deb ${GH_CLI_DOWNLOAD_URL} \
    && apt-get -y install /tmp/ghcli.deb \
    && rm /tmp/ghcli.deb
}

function install_yq() {
  YQ_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/mikefarah/yq/releases/latest \
      | jq -r '.tag_name' \
      | sed 's/^v//g')

  YQ_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/mikefarah/yq/releases/latest \
      | jq ".assets[] | select(.name == \"yq_linux_${DPKG_ARCH}.tar.gz\")" \
      | jq -r '.browser_download_url')

  ( curl -s ${YQ_DOWNLOAD_URL} -L -o /tmp/yq.tar.gz \
    && tar -xzf /tmp/yq.tar.gz -C /tmp \
    && mv /tmp/yq_linux_${DPKG_ARCH} /usr/local/bin/yq)
}

function install_powershell() {
  PWSH_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
      | jq -r '.tag_name' \
      | sed 's/^v//g')

  PWSH_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
      | jq -r ".assets[] | select(.name == \"powershell-${PWSH_VERSION}-linux-${DPKG_ARCH//amd64/x64}.tar.gz\") | .browser_download_url")

  ( curl -L -o /tmp/powershell.tar.gz $PWSH_DOWNLOAD_URL \
    && mkdir -p /opt/powershell \
    && tar zxf /tmp/powershell.tar.gz -C /opt/powershell \
    && chmod +x /opt/powershell/pwsh \
    && ln -s /opt/powershell/pwsh /usr/bin/pwsh )
}

install_git
install_liblttng_ust
install_awscli
install_gitlfs
install_docker
install_container_tools
install_githubcli
install_yq
install_powershell

rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
sed -i 's/ulimit -Hn/# ulimit -Hn/g' /etc/init.d/docker
groupadd -g 121 runner
useradd -mr -d /home/runner -u 1001 -g 121 runner
usermod -aG sudo runner
usermod -aG docker runner
echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
( [[ -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list ]] && rm /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list || : )
