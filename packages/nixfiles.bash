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

# `tty` fails (and, under `set -e`, would otherwise abort the whole script) when there's no
# controlling terminal, e.g. under non-interactive/scripted invocation.  GPG_TTY is only needed
# for interactive Yubikey/pinentry prompts, so leaving it empty in that case is harmless.
GPG_TTY=$(tty 2>/dev/null || true)
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
## A LUKS recovery code is generated, encrypted, and committed to the
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
    init-host-config-file
  fi
  # == Ensure hardware configuration
  ensure-hardware-config
  # == Ensure passphrases
  ensure-luks-recovery-passphrase-file
  ensure-hashed-user-passphrase
  # == Ensure partitions
  log "Ensure partitions"
  ensure-partitions
  ensure-fido2-enrollment
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
  commit-and-push
  ## - if persistent is empty (except for ssh key?), restore from restic
  run-nixos-install
}

## @cmd Provision a remote work machine from this (personal) laptop, over SSH.
##
## Runs entirely on this laptop, which is assumed to already have git, GPG, and a Yubikey signing
## key configured -- unlike `provision`, this never sets any of that up, and never sends a commit
## or push credential, or a GPG signing key, to the target.
##
## The target is SSHed into only for the handful of things that must run on its real hardware:
## generating an accurate hardware-configuration.nix, and delivering the target's new SSH host
## private key directly.  Everything else (secret generation, disk-option prompts, the commit and
## push) happens locally.
##
## Once this pushes, finish the install by running `finish-remote-provision` directly on the
## target's own console.
##
## @arg hostname!
## name of host to provision
##
## @arg target!
## user@host of the target machine, already booted and reachable over ssh
##
## @option --nixfiles-git-branch=main $$
## branch to commit and push to
##
## @option --age-identity $$
## private key used to decrypt secrets, needed to rekey shared secrets for the new host
##
## @option --disk-device $$
## block device to partition and encrypt on the target, e.g. /dev/nvme0n1 -- prompted for if unset
##
## @option --boot-size=1G $$
## size of the EFI boot partition
##
## @option --swap-size $$
## size of the swap file -- prompted for if unset
remote-provision() {
  argc_age_identity=${argc_age_identity:-${argc_nixfiles_path}/master-identities.txt}
  master_recipients="${argc_nixfiles_path}/master-recipients.txt"
  nixos_configs_path="${argc_nixfiles_path}/nixosConfigurations"
  host_path="${nixos_configs_path}/${argc_hostname}"
  secrets_path="${host_path}/secrets"
  git_opts=(-C "${argc_nixfiles_path}")

  [[ -d ${argc_nixfiles_path} ]] ||
    die "nixfiles path does not exist: ${argc_nixfiles_path}"

  log "Verifying ssh connectivity to ${argc_target}"
  remote true || die "Cannot SSH to ${argc_target}"

  log "Ensure correct branch is checked out"
  if ! git branch --show-current | grep -qx "${argc_nixfiles_git_branch}"; then
    git checkout "${argc_nixfiles_git_branch}" ||
      die "Failed to checkout git branch: ${argc_nixfiles_git_branch}"
  fi

  # == Ensure host configuration
  log "Ensure host configuration"
  if [[ ! -e "${host_path}.nix" ]]; then
    init-host-config-file
    log "Filling in disk configuration"
    disk_device=${argc_disk_device:-}
    if [[ -z ${disk_device} ]]; then
      log "Target disk layout:"
      remote lsblk -dno NAME,SIZE,TYPE || true
      ask "Boot disk device (e.g. /dev/nvme0n1): " disk_device
    fi
    swap_size=${argc_swap_size:-}
    if [[ -z ${swap_size} ]]; then
      ask "Swap size (e.g. 4G): " swap_size
    fi
    sed -i \
      -e "s|# boot.size = \"1G\";|boot.size = \"${argc_boot_size}\";|" \
      -e "s|# encrypted.device = \"/dev/nvme0n1\";|encrypted.device = \"${disk_device}\";|" \
      -e "s|# swap.size = \"4G\";|swap.size = \"${swap_size}\";|" \
      "${host_path}.nix" ||
      die "Failed to fill in disk configuration"
  fi

  # == Ensure hardware configuration, generated over ssh
  ensure-hardware-config remote

  # == Ensure SSH host keypair, generated locally and delivered directly to the target
  log "Ensure SSH host keypair"
  if [[ ! -r "${host_path}/ssh_host_ed25519_key.pub" ]]; then
    log "Generating SSH host keypair locally"
    host_key_tmpdir=$(mktemp -d)
    addtrap "rm -rf ${host_key_tmpdir}"
    ssh-keygen -f "${host_key_tmpdir}/ssh_host_ed25519_key" \
      -C "${argc_hostname} SSH host key" -N "" -t ed25519 ||
      die "Failed to generate SSH host key"
    cp "${host_key_tmpdir}/ssh_host_ed25519_key.pub" "${host_path}/ssh_host_ed25519_key.pub" ||
      die "Failed to copy host public key"
    log "Delivering private host key directly to target"
    remote 'umask 077 && cat >/tmp/ssh_host_ed25519_key' \
      <"${host_key_tmpdir}/ssh_host_ed25519_key" ||
      die "Failed to deliver ssh host key to target"
    rm -rf "${host_key_tmpdir}"
  fi

  # == Ensure passphrases (write-only for a brand-new host, no decryption needed)
  ensure-secret "LUKS recovery passphrase"
  unset luks_recovery_passphrase
  ensure-hashed-user-passphrase

  git add -- "${host_path}.nix" "${host_path}" ||
    die "Failed to stage generated host configuration"

  # == Extend shared secrets (e.g. the github access token) to include the new host
  log "Rekeying shared secrets for the new host"
  rekey "${argc_hostname}" ||
    die "Failed to rekey secrets"

  log "Evaluating NixOS configuration"
  nix eval --raw --no-write-lock-file \
    "${argc_nixfiles_path}#nixosConfigurations.${argc_hostname}.config.system.build.toplevel.drvPath" \
    >/dev/null ||
    die "Failed to evaluate NixOS configuration: ${argc_hostname}"

  commit-and-push

  # == Print the exact command to finish provisioning on the target's own console
  github_repo=$(git remote get-url origin |
    sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')
  finish_url="https://raw.githubusercontent.com/${github_repo}/refs/heads/${argc_nixfiles_git_branch}/bin/finish-remote-provision.bash"
  log "Next: on ${argc_target}'s own console, run:"
  cat <<EXAMPLE

  NIXFILES_GIT_BRANCH=${argc_nixfiles_git_branch} BOOTSTRAP_GIT_BRANCH=${argc_nixfiles_git_branch} \\
    bash <(curl -fsSL ${finish_url}) ${argc_hostname}

EXAMPLE
}

## @cmd Finish provisioning a remote work machine, run directly on the target's own console.
##
## Run this on the work machine itself (e.g. via `nix run
## github:thoughtfull-nix/nixfiles#nixfiles -- finish-remote-provision <hostname>`) after
## `remote-provision` has pushed its configuration and delivered this host's SSH private key to
## /tmp.  Clones the (public) nixfiles repository read-only, decrypts the shared github access
## token and this host's own secrets using that key, then formats disks, enrolls FIDO2, and
## installs NixOS.  Never needs git commit access, a GPG key, or the Yubikey master age identity.
##
## @arg hostname!
## name of host to finish provisioning
##
## @option --nixfiles-git-url=https://github.com/thoughtfull-nix/nixfiles.git $$
## URL to clone the nixfiles repository from (read-only -- no credentials needed for a public repo)
##
## @option --nixfiles-git-branch=main $$
## branch to clone
finish-remote-provision() {
  host_key_path=/tmp/ssh_host_ed25519_key
  sudo test -e "${host_key_path}" ||
    die "Missing ${host_key_path} -- run remote-provision from your personal laptop first"
  # remote-provision delivers this over ssh as whichever user it targeted (typically root), mode
  # 0600 -- reclaim it for the current user so age and everything else below can read it without
  # needing sudo on every single access.
  sudo chown "$(id -u):$(id -g)" "${host_key_path}" ||
    die "Failed to take ownership of ${host_key_path}"
  sudo chmod 600 "${host_key_path}" ||
    die "Failed to set permissions on ${host_key_path}"

  argc_nixfiles_path=$(mktemp -d)
  addtrap "rm -rf ${argc_nixfiles_path}"
  log "Cloning nixfiles repository"
  @git@ clone --branch "${argc_nixfiles_git_branch}" "${argc_nixfiles_git_url}" "${argc_nixfiles_path}" ||
    die "Failed to clone nixfiles repo: ${argc_nixfiles_git_url}"

  argc_age_identity=${host_key_path}
  master_recipients="${argc_nixfiles_path}/master-recipients.txt"
  nixos_configs_path="${argc_nixfiles_path}/nixosConfigurations"
  host_path="${nixos_configs_path}/${argc_hostname}"
  secrets_path="${host_path}/secrets"

  # == Fetch the github access token before evaluating the flake at all: nixosConfigurations.nix
  # references the private kryptonix flake input unconditionally, so even `disko --mode mount`
  # would otherwise fail to fetch it.  /etc/nix/nix.conf is a symlink into the (read-only) Nix
  # store on any standard NixOS system, so it can't be appended to.  Write it to root's own
  # writable per-user nix.conf instead (disko/nixos-install below all run as root via sudo) --
  # this is read directly by any nix invocation running as root, with no dependency on an
  # environment variable surviving sudo or whatever a tool like disko does internally.
  log "Fetching github access token"
  # This secret's decrypted content is already a complete nix.conf line (e.g.
  # "access-tokens = github.com=ghp_xxx"), matching how nixosModules/github-token.nix consumes
  # it via `!include` -- write it in as-is, don't re-wrap it in another access-tokens prefix.
  sudo mkdir -p /root/.config/nix ||
    die "Failed to create /root/.config/nix"
  age -d -i "${host_key_path}" \
    "${nixos_configs_path}/shared/secrets/github-access-token.age" |
    sudo tee /root/.config/nix/nix.conf >/dev/null ||
    die "Failed to write github access token to /root/.config/nix/nix.conf"

  # == Ensure partitions
  ensure-luks-recovery-passphrase-file
  ensure-partitions

  # == Install the ssh host key now that persistent is mounted
  log "Installing SSH host key"
  sudo install -D -m 600 "${host_key_path}" /mnt/persistent/etc/ssh/ssh_host_ed25519_key ||
    die "Failed to install ssh host key"
  sudo install -D -m 644 "${host_path}/ssh_host_ed25519_key.pub" \
    /mnt/persistent/etc/ssh/ssh_host_ed25519_key.pub ||
    die "Failed to install ssh host public key"

  ensure-fido2-enrollment

  run-nixos-install
}

## Initialize ${host_path}.nix from the bootstrap.nix template, with BOOTSTRAP replaced by
## ${argc_hostname}.  Caller is responsible for checking whether the file already exists.
init-host-config-file() {
  log "Initializing NixOS configuration"
  sed "s/BOOTSTRAP/${argc_hostname}/g" \
    <"${nixos_configs_path}/bootstrap.nix" \
    >"${host_path}.nix" ||
    die "Failed to initialize NixOS configuration"
}

## Ensure ${host_path}/hardware-configuration.nix exists, generating it with
## nixos-generate-config if missing.  If $1 is given, it's used as a command prefix to run the
## generator through (e.g. `remote`, to run it over ssh on the `remote-provision` target) instead
## of running it directly on this machine.
ensure-hardware-config() {
  log "Ensure hardware configuration"
  # shellcheck disable=SC2024
  if [[ ! -r "${host_path}/hardware-configuration.nix" ]]; then
    log "Generating hardware configuration${1:+ over ssh}"
    mkdir -p "${host_path}"
    ${1:+"$1"} sudo nixos-generate-config --no-filesystems --show-hardware-config \
      >"${host_path}/hardware-configuration.nix" ||
      die "Failed to generate hardware configuration"
  fi
}

## Ensure the hashed user login passphrase secret exists, generating and encrypting one if not.
ensure-hashed-user-passphrase() {
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
}

## Ensure the LUKS recovery passphrase secret exists, then stage it at
## /tmp/luks-recovery-passphrase.txt for disko to consume when formatting/mounting.
ensure-luks-recovery-passphrase-file() {
  ensure-secret "LUKS recovery passphrase"
  echo -n "${luks_recovery_passphrase}" >/tmp/luks-recovery-passphrase.txt ||
    die "Failed to write password file"
  unset luks_recovery_passphrase
}

## Mount the target's partitions, formatting them first (with confirmation) if they don't exist
## yet.  Expects /tmp/luks-recovery-passphrase.txt to already be in place, and
## ${argc_nixfiles_path}/${argc_hostname} to be set.
ensure-partitions() {
  if ! sudo @disko@ --mode mount --flake "${argc_nixfiles_path}#${argc_hostname}"; then
    log "Partitions not found"
    error "Formatting disks, data could be permanently lost!"
    confirm
    sudo @disko@ --mode destroy,format,mount \
      --flake "${argc_nixfiles_path}#${argc_hostname}" \
      --yes-wipe-all-disks ||
      die "Failed to format disks"
    # Install firmware for RPi4 (required for U-Boot/extlinux boot from USB)
    if [[ "$(uname -m)" == "aarch64" ]]; then
      install-rpi4-firmware
    fi
  fi
}

## Enroll the LUKS partition with FIDO2, prompting to swap primary/backup devices.  Skipped on
## aarch64/RPi4 (no FIDO2 enrollment there).
ensure-fido2-enrollment() {
  if [[ "$(uname -m)" != "aarch64" ]]; then
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
  fi
}

## Commit and push any staged changes in ${argc_nixfiles_path}, if there are any.
commit-and-push() {
  git add .
  if ! git diff-index --cached --quiet HEAD; then
    log "Commit and push changes"
    echo "The following changes are staged..."
    git status ||
      die "Failed to check git status"
    confirm
    commit_attempts=0
    while ! git commit -m "Provision ${argc_hostname}"; do
      commit_attempts=$((commit_attempts + 1))
      # A commit can fail because a pre-commit hook modified a file (e.g. a formatter fixup) --
      # re-stage before retrying so that fix actually gets included.  Cap retries so a
      # persistently failing hook (or a GPG card that never gets inserted) doesn't loop forever.
      ((commit_attempts < 5)) ||
        die "Failed to commit changes after ${commit_attempts} attempts"
      echo "Failed to commit changes.  Trying again"
      git add .
    done
    git push origin "${argc_nixfiles_git_branch}" ||
      die "Failed to push changes"
  fi
}

## Install NixOS onto the mounted target.
run-nixos-install() {
  log "Install NixOS"
  sudo nixos-install \
    --flake "${argc_nixfiles_path}#${argc_hostname}" --no-root-password ||
    die "Failed to install NixOS"
}

## Ensure a secret exists, either by decrypting it (if already encrypted for this host), prompting
## the user for it, or generating a random one -- then encrypting it.
##
## Arguments:
## name :: human-readable name of the secret, e.g. "LUKS recovery passphrase"
## mode :: "generate" (default) to generate a random value via phraze, or "prompt" to ask the
##         user to type/paste one in (e.g. for an AWS key)
ensure-secret() {
  name=$1
  mode=${2:-generate}
  secret_name=${1,,}
  secret_name=${secret_name// /-}
  local -n secret_value=${secret_name//-/_}
  if [[ -r "${secrets_path}/${secret_name}.age" ]]; then
    secret_value=$(age-decrypt "${secret_name}")
  elif [[ ${mode} == "prompt" ]]; then
    whisper "Enter value for ${name}: " secret_value
    [[ -n ${secret_value} ]] ||
      die "${name} is empty"
    age-encrypt "${secret_name}" <(printf '%s' "${secret_value}")
  else
    secret_value=$(phraze)
    age-encrypt "${secret_name}" <(echo -n "${secret_value}")
    printf "Generated ${name}: %s\n" "${secret_value}"
    pause "Press any key to continue (and clear the passphrase)"
    clear-lines 2
    printf "Generated ${name}: %s\n" "${secret_value//?/*}"
  fi
  [[ -n ${secret_value} ]] ||
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
      [[ ${host_dir_name} == "shared" ]] && continue
      host_pub_key="${host_dir}ssh_host_ed25519_key.pub"
      if [[ -r ${host_pub_key} ]]; then
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
    if [[ -d ${shared_path} ]] && [[ ${argc_hostname} != "shared" ]]; then
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

## Run a command over ssh on the `remote-provision` target.  StrictHostKeyChecking is
## `accept-new` (trust-on-first-use) rather than disabled outright, since the target is a
## freshly-booted, single-use machine but still worth pinning for the duration of the connection.
remote() {
  ssh -o StrictHostKeyChecking=accept-new "${argc_target}" "$@"
}

# Install Raspberry Pi 4 firmware and U-Boot for USB boot
# This enables the U-Boot/extlinux boot chain on RPi4 hardware
install-rpi4-firmware() {
  local boot_mount="/mnt/boot"
  local firmware_src="@raspberrypi-firmware@"
  local uboot_src="@uboot-rpi4@"

  log "Installing RPi4 firmware to ${boot_mount}"

  # Copy Broadcom GPU firmware
  sudo cp "${firmware_src}/start4.elf" "${boot_mount}/" ||
    die "Failed to copy start4.elf"
  sudo cp "${firmware_src}/fixup4.dat" "${boot_mount}/" ||
    die "Failed to copy fixup4.dat"
  sudo cp "${firmware_src}/bcm2711-rpi-4-b.dtb" "${boot_mount}/" ||
    die "Failed to copy device tree"

  # Copy device tree overlays
  sudo mkdir -p "${boot_mount}/overlays"
  sudo cp "${firmware_src}/overlays/"* "${boot_mount}/overlays/" ||
    die "Failed to copy device tree overlays"

  # Copy U-Boot binary
  sudo cp "${uboot_src}" "${boot_mount}/u-boot.bin" ||
    die "Failed to copy U-Boot"

  # Create config.txt for RPi4 boot
  sudo tee "${boot_mount}/config.txt" >/dev/null <<'CONFIGTXT'
arm_64bit=1
enable_uart=1
kernel=u-boot.bin
CONFIGTXT

  log "RPi4 firmware installed successfully"
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
  @phraze@ -s ' '
}
