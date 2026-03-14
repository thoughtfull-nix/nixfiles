### © technosophist
###
### This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy
### of the MPL was not distributed with this file, You can obtain one at
### http://mozilla.org/MPL/2.0/.
###
### This Source Code Form is "Incompatible With Secondary Licenses", as defined by the Mozilla
### Public License, v. 2.0.
###
### @meta version ∞
### @meta inherit-flag-options
##
## @option --nixfiles-path=~/src/thoughtfull-nix/nixfiles $$
## path of the clone of the nixfiles repository
[[ -v TRACE ]] && set -x

export TMPDIR
TMPDIR="$(mktemp -d)"
addtrap "log \"Recursively deleting ${TMPDIR}\""
log "Using temporary directory ${TMPDIR}"

GPG_TTY=$(tty)
export GPG_TTY

GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"
export GIT_SSH_COMMAND

### CUSTOMIZE THESE ################################################################################
gpg_key="DF2034C6"
gpg_key_url="https://raw.githubusercontent.com/thoughtfull-nix/nixfiles/refs/heads/main/DF2034C6.pub"
git_user_name="technosophist"
git_user_email="technosophist@thoughtfull.systems"
####################################################################################################

## @cmd Setup and install NixOS onto a new host.
##
## Setup and configuration revolves around a Yubikey device.  The Yubikey is used for SSH keys to
## clone a nixfiles repository, and a GPG key to commit to and push the repository.  The Yubikey is
## also setup to unlock the LUKS partition with FIDO2.
##
## A LUKS recovery code and Restic recovery code are generated, encrypted, and committed to the
## repository along with a bootstrapped NixOS configuration and generated
## hardware-configuration.nix.
##
## This setup is designed to be idempotent and require as little input from the user as possible.
## The PINs for the Yubikey need to be entered, and the user will be required to confirm any
## destructive operations.
##
## @arg hostname=`_default-hostname`
## name of host to provision
##
## @option --nixfiles-git-url=git@github.com:thoughtfull-nix/nixfiles.git $$
## URL of the nixfiles repository to clone into nixfiles-path
##
## @option --nixfiles-git-branch=main $$
## branch to checkout in repository clone in nixfiles-path
##
## @option --age-identity $$
## private key used to decrypt secrets
provision() {
  argc_age_identity=${argc_age_identity:-${argc_nixfiles_path}/master-identities.txt}
  master_recipients="${argc_nixfiles_path}/master-recipients.txt"
  nixos_configs_path="${argc_nixfiles_path}/nixosConfigurations"
  host_path="${nixos_configs_path}/${argc_hostname}"
  secrets_path="${host_path}/secrets"
  git_opts=(-C "${argc_nixfiles_path}")
  # == Configure age+yubikey
  log "Configuring age+yubikey"
  cat <<EOF | sudo tee /etc/nixos/configuration2.nix
  { pkgs, ... }: {
    environment.systemPackages = with pkgs; [ age-plugin-yubikey ];
    imports = [ ./configuration.nix ];
    services.pcscd.enable = true;
  }
EOF
  sudo NIXOS_CONFIG=/etc/nixos/configuration2.nix nixos-rebuild switch
  # == Running SSH agent
  log "Running SSH agent"
  eval "$(@ssh-agent@ -s)" || die "Failed to start SSH agent"
  addtrap "log 'Killing ssh-agent'; kill ${SSH_AGENT_PID}"
  log "Ensure SSH keys are loaded"
  @ssh-add@ -K || die "Failed to add SSH keys to agent"
  # == Ensure GnuPG home exists
  log "Ensure GnuPG home exists"
  if [[ ! -d "${HOME}/.gnupg" ]]; then
    log "Creating GnuPG home"
    mkdir "${HOME}/.gnupg" -m 0700 || die "Failed to create GnuPG home"
  fi
  # == Ensure scdaemon is configured
  log "Ensure scdaemon is configured"
  if [[ ! -e "${HOME}/.gnupg/scdaemon.conf" ]]; then
    log "Configuring scdaemon"
    echo "disable-ccid" >"${HOME}/.gnupg/scdaemon.conf"
    @gpgconf@ --kill scdaemon || die "Failed to configure gpg-agent"
  fi
  # == Ensure gpg-agent is configured
  log "Ensure gpg-agent is configured"
  if [[ ! -e "${HOME}/.gnupg/gpg-agent.conf" ]]; then
    log "Configuring gpg-agent"
    echo "pinentry-program @pinentry@" >"${HOME}/.gnupg/gpg-agent.conf"
    @gpgconf@ --kill gpg-agent || die "Failed to configure gpg-agent"
  fi
  # == Ensure GPG public key is loaded
  log "Ensure GPG public key is loaded"
  if ! gpg -k | grep "${gpg_key}"; then
    log "Fetching GPG public key"
    gpg --fetch-keys "${gpg_key_url}" ||
      die "Failed to fetch PGP public key"
  fi
  # == Ensure GPG private key is loaded
  log "Ensure GPG private key is loaded"
  if ! gpg -K | grep "${gpg_key}"; then
    log "Finding GPG private key on key card"
    gpg --card-status || true
    while ! gpg -K | grep "${gpg_key}"; do
      echo "Please insert key card containing ${gpg_key}..."
      confirm
      gpg --card-status || true
    done
  fi
  # == Ensure nixfiles is cloned
  log "Ensure nixfiles is cloned"
  if [[ ! -d ${argc_nixfiles_path} ]]; then
    log "Cloning nixfiles repo"
    @git@ clone "${argc_nixfiles_git_url}" "${argc_nixfiles_path}" ||
      die "Failed to clone nixfiles repo: ${argc_nixfiles_git_url}"
    {
      git config user.name "${git_user_name}" &&
        git config user.email "${git_user_email}" &&
        git config user.signingkey "${gpg_key}" &&
        git config commit.gpgsign true &&
        git config gpg.openpgp.program @gpg@
    } ||
      die "Failed to configure nixfiles repo"
  fi
  # == Ensure correct branch is checked out
  log "Ensure correct branch is checked out"
  if ! git branch --show-current | grep "${argc_nixfiles_git_branch}"; then
    log "Checking out branch"
    git checkout "${argc_nixfiles_git_branch}" ||
      die "Failed to checkout git branch: ${argc_nixfiles_git_branch}"
  fi
  log "Pulling latest changes"
  git pull || die "Failed to pull git repo"
  # == Ensure host configuration
  log "Ensure host configuration"
  if [[ ! -e "${host_path}.nix" ]]; then
    log "Initializing NixOS configuration"
    sed "s/BOOTSTRAP/${argc_hostname}/g" \
      <"${nixos_configs_path}/bootstrap.nix" \
      >"${host_path}.nix" ||
      die "Failed to initialize NixOS configuration"
  fi
  # == Ensure hardware configuration
  log "Ensure hardware configuration"
  # shellcheck disable=SC2024
  if [[ ! -r "${host_path}/hardware-configuration.nix" ]]; then
    log "Generating hardware configuration in repository"
    mkdir -p "${host_path}"
    sudo nixos-generate-config \
      --no-filesystems \
      --show-hardware-config \
      >"${host_path}/hardware-configuration.nix" ||
      die "Failed to generate hardware configuration"
  fi
  # == Ensure passphrases
  ensure-passphrase "LUKS recovery passphrase"
  ensure-passphrase "Restic recovery passphrase"
  if [[ ! -r "${secrets_path}/hashed-user-passphrase.age" ]]; then
    log "Hashing user passphrase"
    user_passphrase=$(phraze)
    age-encrypt "hashed-user-passphrase" <(echo -n "${user_passphrase}" | mkpasswd -s)
    printf "Generated user passphrase: %s\n" "${user_passphrase}"
    pause "Press any key to continue (and clear the passphrase)"
    clear-lines 2
    printf "Generated user passphrase: %s\n" "${user_passphrase//?/*}"
    unset user_passphrase
  fi
  # == Ensure partitions
  log "Ensure partitions"
  # needed for mounting and/or formatting
  echo -n "${luks_recovery_passphrase}" >/tmp/luks-recovery-passphrase.txt ||
    die "Failed to write password file"
  unset luks_recovery_passphrase
  if ! sudo @disko@ --mode mount --flake "${argc_nixfiles_path}#${argc_hostname}"; then
    log "Partitions not found"
    error "Formatting disks, data could be permanently lost!"
    confirm
    sudo @disko@ --mode destroy,format,mount \
      --flake "${argc_nixfiles_path}#${argc_hostname}" \
      --yes-wipe-all-disks ||
      die "Failed to format disks"
  fi
  # == Ensure systemd FIDO2 enrollment
  log "Ensure systemd FIDO2 enrollment"
  luks_device=$(sudo blkid -t TYPE=crypto_LUKS -o device -l)
  if ! sudo systemd-cryptenroll "${luks_device}" | grep fido2; then
    log "Enrolling ${luks_device} with FIDO2"
    sudo systemd-cryptenroll --fido2-device=auto "${luks_device}" ||
      die "Failed to enroll ${luks_device} with FIDO2"
    log "Please remove your primary FIDO2 device and insert your backup device"
    pause
    luks_device=$(sudo blkid -t TYPE=crypto_LUKS -o device -l)
    log "Enrolling ${luks_device} with FIDO2"
    while ! sudo systemd-cryptenroll --fido2-device=auto "${luks_device}"; do
      echo "Failed to enroll ${luks_device} with FIDO2, retrying"
    done
    log "Please remove your backup FIDO2 devices and insert your primary device"
    pause
  fi
  # == Ensure SSH host key
  host_key_path="/mnt/persistent/etc/ssh/ssh_host_ed25519_key"
  log "Ensure SSH host key"
  if [[ ! -e ${host_key_path} ]]; then
    log "Generating SSH host key"
    sudo mkdir -p "$(dirname "${host_key_path}")" ||
      die "Failed to create host key parent directory"
    sudo ssh-keygen -f "${host_key_path}" -C "${argc_hostname} SSH host key" -N "" -t "ed25519" ||
      die "Failed to generate SSH host key: ${host_key_path}"
    cp "${host_key_path}.pub" "${host_path}/" ||
      die "Failed to copy host public key"
    rekey ||
      die "Failed to rekey secrets"
  fi
  # == Commit and push changes
  git add .
  if ! git diff-index --cached --quiet HEAD; then
    log "Commit and push changes"
    echo "The following changes are staged..."
    git status ||
      die "Failed to check git status"
    confirm
    while ! git commit -m "Provision ${argc_hostname}"; do
      echo "Failed to commit changes.  Trying again"
    done
    git push origin "${argc_nixfiles_git_branch}" ||
      die "Failed to push changes"
  fi
  ## - if persistent is empty (except for ssh key?), restore from restic
  log "Install NixOS"
  sudo nixos-install --flake "${argc_nixfiles_path}#${argc_hostname}" --no-root-password ||
    die "Failed to install NixOS"
}

ensure-passphrase() {
  name=$1
  secret_name=${1,,}
  secret_name=${secret_name// /-}
  local -n passphrase=${secret_name//-/_}
  if [[ -r "${secrets_path}/${secret_name}.age" ]]; then
    passphrase=$(age-decrypt "${secret_name}")
  else
    passphrase=$(phraze)
    age-encrypt "${secret_name}" <(echo -n "${passphrase}")
    printf "Generated ${name}: %s\n" "${passphrase}"
    pause "Press any key to continue (and clear the passphrase)"
    clear-lines 2
    printf "Generated ${name}: %s\n" "${passphrase//?/*}"
  fi
  [[ -n ${passphrase} ]] ||
    die "${name} is empty"
}

age-encrypt() {
  mkdir -p "${secrets_path}" ||
    die "Could not create secrets directory: ${secrets_path}"
  log "Encrypting $1"
  host_pub_key_arg=()
  if [[ "$(basename "${host_path}")" == "shared" ]]; then
    nixos_configs_path="$(dirname "${host_path}")"
    for host_dir in "${nixos_configs_path}"/*/; do
      host_dir_name="$(basename "${host_dir}")"
      [[ "${host_dir_name}" == "shared" ]] && continue
      host_pub_key="${host_dir}ssh_host_ed25519_key.pub"
      if [[ -r "${host_pub_key}" ]]; then
        host_pub_key_arg+=("-R" "${host_pub_key}")
      else
        warn "Missing host pub key for ${host_dir_name}, skipping"
      fi
    done
  else
    host_pub_key="${host_path}/ssh_host_ed25519_key.pub"
    if [[ -r ${host_pub_key} ]]; then
      host_pub_key_arg+=("-R" "${host_pub_key}")
    else
      warn "Missing host pub key, using only master key"
    fi
  fi
  secret_path="${secrets_path}/$1.age"
  relpath="$(basename "${host_path}")/secrets/$1"
  if [[ -e ${secret_path} ]]; then
    log "Backing up existing encrypted value to ${relpath}.bak"
    mv "${secret_path}" "${secret_path}.bak"
  fi
  log "Encrypting $1 to ${relpath}"
  age -e -R "${master_recipients}" "${host_pub_key_arg[@]}" -o "${secrets_path}/$1.age" "$2"
  if [[ -e "${secret_path}.bak" ]]; then
    log "Deleting ${relpath}.bak"
    rm "${secret_path}.bak"
  fi
}

age-decrypt() {
  log "Decrypting $1"
  age -d -i "${argc_age_identity}" "${secrets_path}/$1.age"
}

## @cmd Encrypt a (new) secret
##
## Encrypt a to 'nixosConfigurations/${host}/secrets/${secret_name}.age' using as recipients its ssh
## host public key and the keys in 'master-recipients.txt` at the repository root.
##
## If host is 'shared', encrypt to all host public keys.  The secret is saved to
## 'nixosConfigurations/shared/secrets/${secret_name}.age'.
##
## If input-file is given, then use it as input.  Otherwise create an empty file and open it with
## $EDITOR.
##
## @arg hostname!
## name of host, or 'shared' for a secret shared across all hosts
##
## @arg secret_name!
## name of the secret to encrypt, do not include an '.age' suffix
##
## @arg input_file
## instead of editing a file use this file as input
##
## @option --age-identity $$
## private key used to decrypt secrets
secret() {
  [[ -e ${argc_nixfiles_path} ]] ||
    die "nixfiles path does not exist: ${argc_nixfiles_path}"
  [[ -d ${argc_nixfiles_path} ]] ||
    die "nixfiles path is not a directory: ${argc_nixfiles_path}"
  argc_age_identity=${argc_age_identity:-${argc_nixfiles_path}/master-identities.txt}
  [[ -e ${argc_age_identity} ]] ||
    die "age identity does not exist: ${argc_age_identity}"
  [[ -r ${argc_age_identity} ]] ||
    die "age identity is not readable: ${argc_age_identity}"
  master_recipients="${argc_nixfiles_path}/master-recipients.txt"
  [[ -e ${master_recipients} ]] ||
    die "master keys file does not exist: ${master_recipients}"
  [[ -r ${master_recipients} ]] ||
    die "master keys file is not readable: ${master_recipients}"
  host_path="${argc_nixfiles_path}/nixosConfigurations/${argc_hostname}"
  secrets_path="${host_path}/secrets"
  mkdir -p "${secrets_path}" ||
    die "Could not create secrets directory: ${secrets_path}"
  secret_path="${secrets_path}/${argc_secret_name}.age"
  input_file="${TMPDIR}/${argc_secret_name}"
  before_file="${input_file}.before"
  touch "${before_file}"
  if [[ ! -v argc_input_file ]]; then
    if [[ -r ${secret_path} ]]; then
      log "Writing unencrypted value to ${before_file}"
      age-decrypt "${argc_secret_name}" >"${before_file}"
      log "Copying unencrypted value from ${before_file} to ${input_file}"
      cp "${before_file}" "${input_file}"
    fi
    log "Editing ${input_file}"
    "${EDITOR:-nano -w}" "${input_file}"
  else
    input_file="${argc_input_file}"
  fi
  [[ -e ${input_file} ]] ||
    die "input file is missing: ${input_file}"
  [[ -r ${input_file} ]] ||
    die "input file is unreadable: ${input_file}"
  [[ ! -v argc_input_file ]] && diff -q "${before_file}" "${input_file}" >/dev/null &&
    die "file unchanged"
  age-encrypt "${argc_secret_name}" "${input_file}"
}

## @cmd Re-encrypt age secrets in repository (presumably for key changes)
##
## For the given host (or all hosts if host is unspecified), re-encrypt its secrets using as
## recipients its ssh host public key and the keys in 'master-recipients.txt` at the repository
## root.
##
## Shared secrets in 'nixosConfigurations/shared/secrets' are always rekeyed as well, since they
## are encrypted to all host keys.
##
## @arg hostname
## name of host
##
## @option --age-identity $$
## private key used to decrypt secrets
rekey() {
  [[ -e ${argc_nixfiles_path} ]] ||
    die "nixfiles path does not exist: ${argc_nixfiles_path}"
  [[ -d ${argc_nixfiles_path} ]] ||
    die "nixfiles path is not a directory: ${argc_nixfiles_path}"
  argc_age_identity=${argc_age_identity:-${argc_nixfiles_path}/master-identities.txt}
  [[ -e ${argc_age_identity} ]] ||
    die "age identity does not exist: ${argc_age_identity}"
  [[ -r ${argc_age_identity} ]] ||
    die "age identity is not readable: ${argc_age_identity}"
  master_recipients="${argc_nixfiles_path}/master-recipients.txt"
  [[ -e ${master_recipients} ]] ||
    die "master keys file does not exist: ${master_recipients}"
  [[ -r ${master_recipients} ]] ||
    die "master keys file is not readable: ${master_recipients}"
  nixos_configs_path="${argc_nixfiles_path}/nixosConfigurations"
  local -a hosts
  if [[ -z ${argc_hostname} ]]; then
    hosts=("${nixos_configs_path}"/*)
  else
    hosts=("${nixos_configs_path}/${argc_hostname}")
    shared_path="${nixos_configs_path}/shared"
    # Rekey shared secrets whenever any specific host is rekeyed, since shared
    # secrets are encrypted to all host keys.  Skip if already rekeying shared.
    if [[ -d "${shared_path}" ]] && [[ "${argc_hostname}" != "shared" ]]; then
      hosts+=("${shared_path}")
    fi
  fi
  tmpfile=$(mktemp)
  checkfile=$(mktemp)
  for host_path in "${hosts[@]}"; do
    log "Rekeying $(realpath --relative-base "${nixos_configs_path}" "${host_path}")"
    secrets_path="${host_path}/secrets"
    for secret_path in "${secrets_path}"/*.age; do
      log "Rekeying $(realpath --relative-base "${nixos_configs_path}" "${secret_path}")"
      secret_name=$(basename "${secret_path}" ".age")
      cp "${secret_path}" "${secrets_path}/${secret_name}.bak.age"
      tmpfile=$(mktemp)
      age-decrypt "${secret_name}.bak" >"${tmpfile}"
      age-encrypt "${secret_name}" "${tmpfile}"
      age-decrypt "${secret_name}" >"${checkfile}"
      if [[ "$(cat "${tmpfile}")" != "$(cat "${checkfile}")" ]]; then
        rm "${secrets_path}/${secret_name}.age" &&
          mv "${secrets_path}/${secret_name}.bak.age" "${secrets_path}/${secret_name}.age" &&
          die "Re-encrypted value does not match original"
      else
        rm "${secrets_path}/${secret_name}.bak.age"
      fi
    done
  done
}

_default-hostname() {
  hostname -s
}

age() {
  @age@ "$@"
}

git() {
  @git@ "${git_opts[@]}" "$@"
}

gpg() {
  @gpg@ "$@"
}

phraze() {
  @phraze@ -t
}
