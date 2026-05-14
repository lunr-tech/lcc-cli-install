#!/bin/sh
set -e
# LCC for Debian Linux installation script
#
# See https://github.com/lunr-tech/lcc-cli-install for the installation steps.
#
# This script is meant for quick & easy install via:
#   $ curl -s -L lcc.sh | bash

DRY_RUN=${DRY_RUN:-}
LCC_VERSION=${LCC_VERSION:-0.1.7}

while [ $# -gt 0 ]; do
  case "$1" in
  --version)
    LCC_VERSION=$2
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    ;;
  --*)
    echo "Illegal option $1"
    ;;
  esac
  shift $(($# > 0 ? 1 : 0))
done

DEFAULT_DOWNLOAD_URL="https://update.lcc.sh/lcc-cli"
if [ -z "$DOWNLOAD_URL" ]; then
  DOWNLOAD_URL=$DEFAULT_DOWNLOAD_URL
fi

get_distribution() {
  lsb_dist=""
  if [ -r /etc/os-release ]; then
    lsb_dist="$(. /etc/os-release && echo "$ID")"
  fi
  echo "$lsb_dist"
}

is_dry_run() {
  if [ -z "$DRY_RUN" ]; then
    return 1
  else
    return 0
  fi
}

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

do_install() {
  echo "# Executing LCC install script, version: $LCC_VERSION"

  user="$(id -un 2>/dev/null || true)"

  exec_command='bash -c'
  if [ "$user" != 'root' ]; then
    if command_exists sudo; then
      exec_command='sudo -E bash -c'
    elif command_exists su; then
      exec_command='su -c'
    else
      echo 'Error: this installer needs the ability to run commands as root.'
      echo 'We are unable to find either "sudo" or "su" available to make this happen.'
      exit 1
    fi
  fi

  if is_dry_run; then
    exec_command="echo"
  fi

  lsb_dist=$(get_distribution)
  lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

  case "$lsb_dist" in
  ubuntu | linuxmint | debian)
    $exec_command 'apt-get update -qq >/dev/null'
    $exec_command "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq wget apache2-utils iputils-ping netcat-openbsd python3 python3-pip python3-venv >/dev/null"
    ;;
  *)
    echo "Error: unsupported distribution '$lsb_dist'. Only ubuntu, linuxmint, and debian are supported."
    exit 1
    ;;
  esac

  # Create venv on first install; reuse on upgrade
  $exec_command "mkdir -p /usr/local/lib/lcc && python3 -m venv /usr/local/lib/lcc"
  $exec_command "export LC_ALL=C.UTF-8 LANG=C.UTF-8 && source /usr/local/lib/lcc/bin/activate && python3 -m pip install --upgrade pip >/dev/null && python3 -m pip install --upgrade ansible docker websocket jsondiff firewall >/dev/null && ansible-galaxy collection install ansible.posix community.docker >/dev/null"

  # Download the release tarball with visible errors on failure
  TARBALL_URL="$DOWNLOAD_URL/v$LCC_VERSION/lcc-cli.v$LCC_VERSION.tar.gz"
  echo "# Downloading LCC CLI v$LCC_VERSION from $TARBALL_URL"
  $exec_command "wget -O /tmp/lcc-cli.tar.gz '$TARBALL_URL' || { echo 'Error: failed to download LCC CLI v$LCC_VERSION. Check that the version exists and the server is reachable.'; rm -f /tmp/lcc-cli.tar.gz; exit 1; }"

  $exec_command "cd /tmp && tar -xzf lcc-cli.tar.gz"

  # Verify extraction produced the expected wheel
  WHL="/tmp/lcc_cli-${LCC_VERSION}-py3-none-any.whl"
  $exec_command "test -f '$WHL' || { echo 'Error: expected wheel not found after extraction ($WHL). The archive may be corrupt or the version format has changed.'; rm -f /tmp/lcc-cli.tar.gz; exit 1; }"

  $exec_command "source /usr/local/lib/lcc/bin/activate && pip install --upgrade '$WHL'"

  # Clean up temporary files
  $exec_command "rm -f /tmp/lcc-cli.tar.gz '$WHL'"

  $exec_command "export LC_ALL=C.UTF-8 LANG=C.UTF-8 && source /usr/local/lib/lcc/bin/activate && printf \"\033c\" && lcc-cli init"
}

do_install