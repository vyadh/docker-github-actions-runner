#!/usr/bin/env bash
# shellcheck disable=SC2086,DL3015,DL3008,DL3013,SC2015

set -euo pipefail

selected_to_install=()
source "$(dirname "$0")/installed_tools.sh"

declare -A install=(
  ["bootstrap"]="gnupg curl tar unzip zip apt-transport-https ca-certificates sudo jq dirmngr locales gosu"
  ["essentials"]="gpg-agent dumb-init docker-ce-cli"
  ["development"]="build-essential zlib1g-dev zstd gettext libcurl4-openssl-dev libpq-dev pkg-config software-properties-common"
  ["network-tools"]="inetutils-ping wget openssh-client rsync"
  ["python"]="python3-pip python3-setuptools python3-venv python3"
  ["nodejs"]="nodejs"
  ["docker"]="docker-ce docker-buildx-plugin containerd.io docker-compose-plugin"
  ["container-tools"]="podman buildah skopeo"
)

function is_selected() {
  for selected in "${selected_to_install[@]}"; do
    if [[ "$selected" == "$1" ]]; then
      return 0
    fi
  done
  return 1
}

function install_packages() {
  local packages=${install[$1]}
  read -r -a args <<< "$packages"
  apt-get install -y --no-install-recommends "${args[@]}"
}

function configure_git() {
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${GIT_CORE_PPA_KEY} \
    || apt-key adv --keyserver pgp.mit.edu --recv-keys ${GIT_CORE_PPA_KEY} \
    || apt-key adv --keyserver keyserver.pgp.com --recv-keys ${GIT_CORE_PPA_KEY}

  source /etc/os-release
  ( [[ "${VERSION_CODENAME}" == "focal" ]] \
   && (echo deb http://ppa.launchpad.net/git-core/ppa/ubuntu focal main>/etc/apt/sources.list.d/git-core.list ) || : )
}

function install_git() {
  ( apt-get install -y --no-install-recommends git \
   || apt-get install -t stable -y --no-install-recommends git )
}

function install_debugging_tools() {
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

function configure_docker() {
  source /etc/os-release

  mkdir -p /etc/apt/keyrings
  ( curl -fsSL "https://download.docker.com/linux/$ID/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg )

  version=$(echo "$VERSION_CODENAME" | sed 's/trixie\|n\/a/bookworm/g')
  ( echo "deb [arch=${DPKG_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID ${version} stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null )
}

function install_docker() {
  install_packages "docker"

  echo -e '#!/bin/sh\ndocker compose --compatibility "$@"' > /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose

  sed -i 's/ulimit -Hn/# ulimit -Hn/g' /etc/init.d/docker
}

function configure_container_tools() {
  source /etc/os-release

  ( [[ "${VERSION_CODENAME}" == "focal" ]] \
    && ( echo "available in 20.10 and higher" \
    && echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_20.04/ /" \
      | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list \
    && curl -L "https://build.opensuse.org/projects/devel:kubic/signing_keys/download?kind=gpg" \
      | apt-key add - ) || : )
}

function install_container_tools() {
  ( install "container-tools" || : )
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

function configure_sources() {
  configure_docker

  if is_selected "git" || is_selected "git-lfs"; then
    configure_git
  fi

  if is_selected "container-tools"; then
    configure_container_tools
  fi
}

function install_selected_packages() {
  is_selected "development" && install_packages "development"
  (is_selected "python" || is_selected "aws-cli") && install_packages "python"
  is_selected "nodejs" && install_packages "nodejs"
  is_selected "network-tools" && install_packages "network-tools"
  (is_selected "git" || is_selected "git-lfs") && install_git
  is_selected "debugging-tools" && install_debugging_tools
  is_selected "aws-cli" && install_awscli
  is_selected "git-lfs" && install_gitlfs
  is_selected "docker" && install_docker
  is_selected "container-tools" && install_container_tools
  is_selected "github-cli" && install_githubcli
  is_selected "yq" && install_yq
  is_selected "powershell" && install_powershell || true
}


echo en_US.UTF-8 UTF-8 >> /etc/locale.gen

apt-get update
install_packages "bootstrap"

DPKG_ARCH="$(dpkg --print-architecture)"
sed -e 's/Defaults.*env_reset/Defaults env_keep = "HTTP_PROXY HTTPS_PROXY NO_PROXY FTP_PROXY http_proxy https_proxy no_proxy ftp_proxy"/' -i /etc/sudoers

configure_sources
apt-get update
install_packages "essentials"
install_selected_packages

rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
groupadd -g 121 runner
useradd -mr -d /home/runner -u 1001 -g 121 runner
usermod -aG sudo runner
if is_selected "docker"; then
  usermod -aG docker runner
fi
echo '%sudo ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
( [[ -f /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list ]] && rm /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list || : )
