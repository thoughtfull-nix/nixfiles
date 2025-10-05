#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

die() {
  echo "!! ${1}"
  exit "${2:-1}"
}

prompt() {
  echo "<< ${1}"
}

confirm() {
  read -rp "$(prompt "Type 'yes' to continue: ")" choice
  case "${choice,,}" in
  yes) return 0 ;;
  *) exit 0 ;;
  esac
}

log() {
  echo "== ${1}"
}

warn() {
  echo "** ${1}"
}

is_git_clean() {
  ${git} diff-index --quiet HEAD
}

set_vars() {
  hostname=${1}
  ssh_destination=${2:-ssh://root@localhost:22}
  disko_url=${TTFL_DISKO_URL:-github:nix-community/disko/v1.11.0}
  nixfiles=${TTFL_NIXFILES_DIR:-.}
  nixfiles_url=${TTFL_NIXFILES_URL:-github:thoughtfull-nix/nixfiles}
  gpg_ident=${TTFL_GPG_IDENTITY:-technosophist@thoughtfull.systems}

  run="@ssh@ -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=false ${ssh_destination}"
  git="@git@ -C ${nixfiles}"
  gpg="@gpg@"
  config_path=${nixfiles}/nixosConfigurations/${hostname}
  hardware_config_path=${config_path}/hardware-configuration.nix
  secrets=${config_path}/secrets
}

confirm_vars() {
  log "Using SSH destination: ${ssh_destination}"
  log "Using disko URL: ${disko_url}"
  log "Using nixfiles dir: ${nixfiles}"
  log "Using nixfiles URL: ${nixfiles_url}"
  log "Using GPG identity: ${gpg_ident}"

  ## pause for confirmation
  confirm

  ## verify hostname
  remote_hostname=$(${run} hostname)
  [[ ${remote_hostname} == "${hostname}" ]] ||
    die "Wrong hostname! Expected ${hostname} but was ${remote_hostname}"
}

update_hardware_configuration() {
  ## update the hardware-configuration.nix for hostname
  ##
  ## in the bootstrapping case the machine configuration, in anticipation of it existing, attempts
  ## to import hardware-configuration.nix, but because it doesn't yet exist disko will fail to
  ## evaluate the machine configuration to get the disko configuration.
  ##
  ## I attempted to put disko config in the top-level diskoConfiguration output, but could not
  ## figure out how to get it to work.
  ##
  ## I gave up and just decided to generate, commit, and push the hardware-configuration.nix before
  ## running disko.
  if is_git_clean; then
    if [[ -e ${hardware_config_path} ]]; then
      action="Updated"
    else
      action="Added"
    fi
    log "Generating hardware-configuration.nix from ${hostname}"
    ${run} nixos-generate-config --no-filesystems --show-hardware-config >"${hardware_config_path}"
    # add before checking because otherwise the modification date indicates a difference even when
    # the content is the same, and add will check the content
    ${git} add "${hardware_config_path}"
    if ! is_git_clean; then
      log "Committing hardware-configuration.nix for ${hostname}"
      ${git} commit --no-verify -m"${action} hardware-configuration.nix for ${hostname}"
      # remote machine needs this
      ${git} push origin
    else
      log "No hardware-configuration.nix changes to commit"
    fi
  else
    die "Cannot update hardware-configuration.nix, because git tree is dirty"
  fi
}

ensure_fde_passphrase() {
  ## ensure FDE passphrase
  passphrase_secret_file="${secrets}/fde-passphrase.gpg"
  if [[ ! -e ${passphrase_secret_file} ]]; then
    warn "Missing FDE passphrase secret for ${hostname}"
    if is_git_clean; then
      while true; do
        read -srp "$(prompt "Enter FDE passphrase secret for ${hostname}: ")" passphrase
        echo
        read -srp "$(prompt "Confirm FDE passphrase secret for ${hostname}: ")" confirm
        echo
        if [[ ${passphrase} == "${confirm}" ]]; then
          log "Encrypting FDE passphrase secret for ${hostname}"
          (echo -n "${passphrase}" | ${gpg} --armor -ser "${gpg_ident}") \
            >"${passphrase_secret_file}"
          log "Committing FDE passphrase secret for ${hostname}"
          ${git} add "${passphrase_secret_file}"
          ${git} commit --no-verify -m"Added FDE passphrase secret for ${hostname}"
          unset passphrase
          unset confirm
          break
        else
          warn "Passphrases do not match"
        fi
      done
    else
      die "Not creating FDE passphrase secret, because git tree is dirty"
    fi
  fi
}

copy_fde_passphrase() {
  ## copy FDE passphrase
  log "Copying FDE passphrase"
  if ! ${run} \[\[ -e /tmp/secret.key \]\]; then
    (${gpg} -d "${passphrase_secret_file}" | ${run} cat \>/tmp/secret.key) ||
      die "Failed to decrypt FDE passphrase secret for ${hostname}"
  fi
}

partition_and_format_disks() {
  ensure_fde_passphrase
  copy_fde_passphrase
  ## ensure latest revision of nixfiles
  ${run} nix flake prefetch --refresh "${nixfiles_url}"
  ## partition and format disk(s)
  log "Destroying disk(s)"
  ${run} nix run "${disko_url}" -- --mode destroy --flake "${nixfiles_url}#${hostname}" ||
    die "Failed to partition disk(s) for ${hostname}"
  log "Formatting disk(s)"
  ${run} nix run "${disko_url}" -- --mode format --flake "${nixfiles_url}#${hostname}" ||
    die "Failed to format disk(s) for ${hostname}"
  log "Finished"

  ## mount disk(s)
  echo "== Mounting disk(s)"
  ${run} nix run "${disko_url}" -- --mode mount --flake "${nixfiles_url}#${hostname}"

  ## copy ssh keys
  keys=("${secrets}"/ssh_host_*_key.gpg)
  if [[ ${#keys[*]} -gt 0 ]]; then
    if ${run} \[\[ -d /mnt/persistent \]\]; then
      persistent="persistent/"
    else
      persistent=""
    fi
    for key in "${keys[@]}"; do
      key=$(basename "${key}" .gpg)
      log "Copying ${key} to /mnt/${persistent}etc/ssh/${key}"
      (${gpg} -d | ${run} cat \>"/tmp/${key}") <"${secrets}/${key}.gpg"
      log "Copying ${key}.pub /mnt/${persistent}etc/ssh/${key}.pub"
      ${run} cat\>"/tmp/${key}.pub" <"${secrets}/${key}.pub"
    done
    ${run} mkdir -p -m0755 /mnt/${persistent}etc/ssh
    ${run} install -o root -g root -m0600 /tmp/ssh_host_\*_key /mnt/${persistent}etc/ssh
    ${run} install -o root -g root -m0644 /tmp/ssh_host_\*_key.pub /mnt/${persistent}etc/ssh
  fi
}

install_nixos() {
  ## pause for confirmation
  prompt "About to install NixOS..."
  confirm

  ## ensure latest revision of nixfiles
  ${run} nix flake prefetch --refresh "${nixfiles_url}"
  ## install nixos
  ${run} nixos-install --flake "${nixfiles_url}#${hostname}" --no-root-password
  log "Finished"
}

grab-ssh-keys() {
  ## grab keys from remote
  if is_git_clean; then
    for key in $(${run} ls -1 /etc/ssh/ssh_host_*_key); do
      log "Grabbing ${key}"
      key=$(basename "${key}")
      (${run} cat "/etc/ssh/${key}" | gpg --armor -ser "${gpg_ident}") >"${secrets}/${key}.gpg"
      log "Grabbing ${key}.pub"
      ${run} cat "/etc/ssh/${key}.pub" >"${secrets}/${key}.pub"
    done
    log "Committing keys"
    ${git} add "${secrets}"/ssh_host_*_key.*
    ${git} commit --no-verify -m"Added ssh host keys for ${hostname}"
  else
    die "Not grabbing keys, because git tree is dirty"
  fi
}

main() {
  [[ ${#*} -le 3 ]] || die "Expected 1 to 3 arguments, but got ${#*}"

  case $1 in
  partition)
    shift
    set_vars "${@}"
    confirm_vars
    update_hardware_configuration
    partition_and_format_disks
    ;;
  install)
    shift
    set_vars "${@}"
    confirm_vars
    update_hardware_configuration
    install_nixos
    ;;
  grab-ssh-keys)
    shift
    set_vars "${@}"
    confirm_vars
    grab-ssh-keys
    ;;
  *)
    set_vars "${@}"
    confirm_vars
    update_hardware_configuration
    partition_and_format_disks
    install_nixos
    ;;
  esac
}

main "${@}"
