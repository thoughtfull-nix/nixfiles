#!@bash@

### Copyright © technosophist
###
### This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy
### of the MPL was not distributed with this file, You can obtain one at
### http://mozilla.org/MPL/2.0/.
###
### This Source Code Form is "Incompatible With Secondary Licenses", as defined by the Mozilla
### Public License, v. 2.0.

### @meta version ∞

set -euo pipefail
shopt -s nullglob
IFS=$'\n\t'

# shellcheck disable=SC1091
. @bashlib@

declare -g age_recipients hardware_config_path secrets_path TMPDIR
declare -ga ssh_opts

## @cmd Provision a new machine
##
## Running this script with a hostname argument and remote argument (e.g. ssh://user@host:port) will
## generate an SSH host key, generate a hardware-configuration.nix for hostname (in
## 'nixosConfigurations/${hostname}'), partition and format remote with disko using hostname's
## configuration, copy the SSH host key into remote's installation partitions, and install NixOS on
## remote using hostname's configuration.
##
## SSH host private keys are stored encrypted to the recipients in master-keys.txt using age.
##
## Remote must be booted with a NixOS installer.
##
## @meta default-subcommand
##
## @arg hostname!
## hostname to configure the remote for
##
## @arg ssh-destination!
## SSH destination (i.e. ssh://user@host:port) to provision
##
## @option --nixfiles-dir=`_find-nixfiles-dir` $TTFL_NIXFILES_DIR
## directory of local nixfiles checkout for reading/writing secrets and configuration
##
## @option --nixfiles-url=github:thoughtfull-nix/nixfiles $TTFL_NIXFILES_URL
## URL of nixfiles repository to pull to remote for install
##
## @option --age-identity-file=~/.ssh/id_ed25519 $TTFL_AGE_IDENTITY_FILE
## file containing age identity to use for decrypt secrets
main() {
  setup
  declare flake
  flake="${argc_nixfiles_url}#${argc_hostname}"

  ensure-ssh-host-key
  update-hardware-configuration
  format-remote
  copy-ssh-host-keys-to-installation
  install-remote
}

## @cmd Create SSH host key and hardware configuration for a new machine
##
## @arg hostname!
## hostname to configure the remote for
##
## @arg ssh-destination!
## SSH destination (i.e. ssh://user@host:port) to provision
##
## @option --nixfiles-dir=`_find-nixfiles-dir` $TTFL_NIXFILES_DIR
## directory of local nixfiles checkout for reading/writing secrets and configuration
init() {
  setup
  ensure-ssh-host-key
  update-hardware-configuration
}

## @cmd Format disks and copy SSH host key
##
## @arg hostname!
## hostname to configure the remote for
##
## @arg ssh-destination!
## SSH destination (i.e. ssh://user@host:port) to provision
##
## @option --nixfiles-dir=`_find-nixfiles-dir` $TTFL_NIXFILES_DIR
## directory of local nixfiles checkout for reading/writing secrets and configuration
##
## @option --nixfiles-url=github:thoughtfull-nix/nixfiles $TTFL_NIXFILES_URL
## URL of nixfiles repository to pull to remote for install
##
## @option --age-identity-file=~/.ssh/id_ed25519 $TTFL_AGE_IDENTITY_FILE
## file containing age identity to use for decrypt secrets
format() {
  setup
  format-remote
  copy-ssh-host-keys-to-installation
}

## @cmd Install NixOS
##
## @arg hostname!
## hostname to configure the remote for
##
## @arg ssh-destination!
## SSH destination (i.e. ssh://user@host:port) to provision
##
## @option --nixfiles-dir=`_find-nixfiles-dir` $TTFL_NIXFILES_DIR
## directory of local nixfiles checkout for reading/writing secrets and configuration
##
## @option --nixfiles-url=github:thoughtfull-nix/nixfiles $TTFL_NIXFILES_URL
## URL of nixfiles repository to pull to remote for install
install() {
  setup
  install-remote
}

_find-nixfiles-dir() {
  local flake_path
  if find-dominating-file flake_path flake.nix; then
    dirname "${flake_path}"
  else
    readlink -f .
  fi
}

ssh() {
  @ssh@ "$@"
}

ssh-keygen() {
  @ssh-keygen@ "${@}"
}

run() {
  # shellcheck disable=SC2029
  ssh "${ssh_opts[@]}" "${argc_ssh_destination}" "$@"
}

age() {
  @age@ "$@"
}

age-encrypt() {
  age -R "${age_recipients}" --armor "${@}"
}

age-decrypt() {
  @age@ --decrypt -i "${argc_age_identity_file}" "$@"
}

setup() {
  local config_path remote_hostname

  argc_nixfiles_dir=$(readlink -f "${argc_nixfiles_dir}")
  age_recipients=${argc_nixfiles_dir}/master-keys.txt
  config_path=${argc_nixfiles_dir}/nixosConfigurations/${argc_hostname}
  hardware_config_path=${config_path}/hardware-configuration.nix
  secrets_path=${config_path}/secrets

  TMPDIR=$(mktemp -d)
  export TMPDIR
  addtrap "rm -rf ${TMPDIR}" EXIT SIGHUP SIGINT SIGQUIT SIGPIPE SIGTERM
  ssh_opts=("-oUserKnownHostsFile=${TMPDIR}/known_hosts")

  echo "argc_hostname=${argc_hostname}"
  echo "argc_ssh_destination=${argc_ssh_destination}"
  echo "argc_nixfiles_dir=${argc_nixfiles_dir}"
  [[ -v argc_nixfiles_url ]] && echo "argc_nixfiles_url=${argc_nixfiles_url}"
  [[ -v argc_age_identity_file ]] && echo "argc_age_identity_file=${argc_age_identity_file}"
  echo "age_recipients=${age_recipients}"
  echo "config_path=${config_path}"
  echo "hardware_config_path=${hardware_config_path}"
  echo "secrets_path=${secrets_path}"
  echo "TMPDIR=${TMPDIR}"

  confirm

  log "Checking hostname on remote"
  remote_hostname=$(run hostname -s)
  [[ ${remote_hostname} == "${argc_hostname}" ]] ||
    die "Wrong hostname! Expected ${argc_hostname} but was ${remote_hostname}"
}

ensure-ssh-host-key() {
  declare host_key_path enc_host_key_path
  host_key_path=${secrets_path}/ssh_host_ed25519_key
  enc_host_key_path=${host_key_path}.age
  if [[ ! -s ${enc_host_key_path} ]]; then
    mkdir -p "${secrets_path}"
    warn "SSH host key missing for ${argc_hostname}"
    {
      log "Generating SSH host key for ${argc_hostname}" &&
        ssh-keygen -f "${host_key_path}" -C "${argc_hostname} SSH host key" -N "" -t "ed25519" &&
        log "Encrypting SSH host private key for ${argc_hostname}" &&
        age-encrypt -o "${enc_host_key_path}" "${host_key_path}" &&
        rm "${host_key_path}"
    } ||
      {
        rm -f "${host_key_path}" "${host_key_path}.pub" "${enc_host_key_path}"
        die "Failed to generate and encrypt SSH host key for ${argc_hostname}"
      }
  else
    log "SSH host key exist for ${argc_hostname}"
  fi
}

update-hardware-configuration() {
  log "Generating hardware-configuration.nix from remote"
  declare tmpfile
  tmpfile=$(mktemp)
  run nixos-generate-config --no-filesystems --show-hardware-config >"${tmpfile}" ||
    die "Failed to generate hardware-configuration.nix from remote"
  mv "${tmpfile}" "${hardware_config_path}"
}

format-remote() {
  declare flake
  flake="${argc_nixfiles_url}#${argc_hostname}"

  log "Fetching latest nixfiles from ${argc_nixfiles_url} on remote"
  run nix flake prefetch --refresh "${argc_nixfiles_url}" ||
    die "Failed to fetch latest nixfiles from ${argc_nixfiles_url} on remote"
  log "Formatting disk(s) for ${argc_hostname} on remote"
  run disko --mode destroy,format,mount --flake "${flake}" ||
    die "Failed to format disk(s) for ${argc_hostname} on remote"
}

copy-ssh-host-key-to-remote() {
  declare key_name key_path
  key_name=$(basename "$1" .age)
  key_path="$(dirname "$1")/${key_name}"
  remote_key_path="$2/${key_name}"
  if ! run test -s "${remote_key_path}"; then
    log "Copying SSH host key ${key_path} to remote"
    age-decrypt "${key_path}.age" |
      run install -o root -g root -m0600 \<\(cat\) "${remote_key_path}" ||
      die "Failed to copy SSH host key ${key_path} to remote"
  else
    log "SSH host key ${key_path} already exists on remote"
  fi
  if ! run test -s "${remote_key_path}.pub"; then
    log "Copying SSH host key ${key_path}.pub to remote"
    run install -o root -g root -m0644 \<\(cat\) "${remote_key_path}.pub" <"${key_path}.pub" ||
      die "Failed to copy SSH host key ${key_path}.pub to remote"
  else
    log "SSH host key ${key_path}.pub already exists on remote"
  fi
}

copy-ssh-host-keys-to-installation() {
  declare ssh_host_keys_path
  declare -a keys
  if run test -d /mnt/persistent; then
    ssh_host_keys_path="/mnt/persistent/etc/ssh"
  else
    ssh_host_keys_path="/mnt/etc/ssh"
  fi
  run mkdir -p "${ssh_host_keys_path}" || die "Failed to create ${ssh_host_keys_path}"
  log "Copying SSH host keys to ${ssh_host_keys_path} on ${argc_hostname}"
  keys=("${secrets_path}"/ssh_host*_key.age)
  [[ ${#keys[*]} -gt 0 ]] || die "No SSH host keys for ${argc_hostname} to copy to remote"
  log "Copying SSH host keys for ${argc_hostname} to remote"
  for key in "${keys[@]}"; do
    copy-ssh-host-key-to-remote "${key}" "${ssh_host_keys_path}"
  done
}

install-remote() {
  declare flake
  flake="${argc_nixfiles_url}#${argc_hostname}"

  log "Fetching latest nixfiles from ${argc_nixfiles_url} on remote"
  run nix flake prefetch --refresh "${argc_nixfiles_url}" ||
    die "Failed to fetch latest nixfiles from ${argc_nixfiles_url} on remote"
  log "Mounting disk(s) for ${argc_hostname} on remote"
  run disko --mode mount --flake "${flake}" ||
    die "Failed to mount disk(s) for ${argc_hostname} on remote"
  run nixos-install --flake "${flake}" --no-root-password ||
    die "Failed to install NixOS for ${argc_hostname} on remote"
}
