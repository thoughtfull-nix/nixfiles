# Nixfiles for NixOS

## Secrecy

I make heavy use of my Yubikeys.  I find they provide a good balance of security and convenience.  I
like that a PIN (which need not be numeric but can be a passphrase) can be shorter since the Yubikey
will lock after a number of failed attempts.  I also like requiring a touch as a second factor for
operations.

I have a primary key and a backup key and have configured (if possible) all security credentials to
allow for either.  If my primary key is not available, I should be able to authorize operations with
my backup key.  This should be a smooth experience, but sometimes it is a bit bumpy.  Even if it is
bumpy, it is necessary in case I should lose a key.

## Confidentiality

I keep sensitive information out of my nix configuration.  Anything truly sensitive should also be
kept out of the nix store.  Values that just need to be kept out of the public configuration are in
my kryptonix project, which is a private git repository used as a flake input.

Anything that needs to be kept out of the nix store (which is locally readable) is configured not as
a nix value, but as a file placed on disk and loaded at runtime.  These values may also be encrypted
using age and committed to git.

## SSH keys

SSH FIDO private keys are never accessible outside the Yubikey in plain text.  When a private key is
loaded into ssh-agent, it stores a handle with some information about the key.  Sometimes the handle
could include a wrapped private key (the private key encrypted with the Yubikey's master key),
especially if it is a non-resident key.  A resident key is really just that private key handle
stored in a slot on the Yubikey, which can be loaded from the Yubikey.

All SSH resident key handles can be loaded into the ssh-agent using `ssh-add -K`.  This requires a
PIN because the Yubikey requires a PIN to enumerate the resident keys, whether the keys themselves
require a PIN or not.

Resident key handles (and public keys) can be copied to the file system using `ssh-keygen -K`.  SSH
will load a key handle configured as an identity even if it isn't already in the agent.  A resident
key with no handle configured will not be automatically loaded, it must be loaded using `ssh-add
-K`.

Once a key handle is loaded into the agent, its use is governed by the flags used to generate it.  A
touch is required by default unless `-O no-touch-required` is given.  If `-O verify-required` is
given, then a PIN will be required for every use of the key.

A resident key can be generated with:

```
ssh-keygen -t ed25519-sk -O resident -O verify-required -O application=ssh:auth -O user=technosophist -C "auth for technosophist on ypa766"
```

Resident signing key:

```
ssh-keygen -t ed25519-sk -O resident -O application=ssh:sign -O user=technosophist -C "sign for technosophist on ypa766"
```

The `application` must start with `ssh:`.  I use `ssh:auth` for my authentication key and
`ssh:sign` for my git commit signing key.

### Touch or PIN+touch?

My auth key requires a PIN.  My signing key requires only touch.  Why?  The flags apply to each
operation, but auth can reuse an existing authorization.  SSH uses `ControlMaster` to reuse a
connection to, say, Github, so the auth key is needed only to open that connection.  sudo caches
authentication temporarily, so the auth key is needed only for the first sudo operation until the
authentication expires.

When it comes to signing, I don't want to enter a PIN for each git commit, and there isn't a way to
reuse a connection or cache a PIN.  So that key requires only a touch per operation.

## PAM login

I prefer resident keys, so I have a better idea about all the places I'm using my Yubikey.  If I
have to replace a key I can go through the list to switch to a new key.  However, when it comes to
resident keys, PAM must try each key with each device in order.  If I have only my backup key
plugged in, then it will try the first key with the backup key, which fails, then the second key
with the backup key.  Since both attempts require a PIN, I end up having to enter a PIN twice when
using my backup key, but only once with my primary key.  (See:
https://github.com/Yubico/pam-u2f/issues/247)

Though I prefer resident keys, for PAM I use non-resident keys to make the fallback less annoying.

For each Yubikey, generate a credential using:

```
pamu2fcfg -N -u technosophist -o pam://auth -i pam://auth
```

When creating a key for PAM, the origin is all that really matters (the `-o` option), but for
historical compatibility the application ID should be the same as the origin (the `-i` option).  The
value that is used doesn't matter much.  The same value should be used when generating the key as
what PAM uses.  In this case, I just use `pam://auth` as a generic origin.  PAM defaults to
`pam://$HOSTNAME` which is not portable (and, according to official guidance, not even a good idea
for a single host with DHCP).  The `-N` option adds a PIN requirement.

## sudo

Locally, sudo authenticates using PAM which uses the FIDO auth key.  When I ssh into a remote
machine, I cannot plugin my Yubikey, nor can I touch it, so I use `pam_rssh`.  PAM will use the
ssh-agent over the ssh connection to find the FIDO key configured for sudo.

I used to have a separate SSH key for sudo because I wanted it to require a PIN every time, but I
wanted the SSH auth key to only require a touch.  I was wary for sudo to only require a touch, and I
didn't want to be annoyed to enter my PIN every time I pushed commits.  However, I realized that I
can require a PIN for SSH auth and just use `ControlMaster` to cache the connection for 10 minutes,
then I don't have to enter the PIN every push.  There's no longer a need to have separate SSH sudo
key.

## LUKS

For LUKS, I had to enroll with this command

```
systemd-cryptenroll --fido2-device=auto
```

I tried turning on `--with-user-verification=yes`, but it printed a message that it was going to
turn it off because by device didn't support it.

I tried turning off `--with-user-presence=no`, but it printed a message that it was going to turn it
on because the device required it.

So there are really only two ways to setup my yubikeys: 1) `--with-client-pin=yes` which requires a
PIN and a touch, or 2) `--with-client-pin=no` which requires only a touch.

If there is no FIDO2 device plugged in on boot, then it still asks for a PIN (twice actually). If I
just press enter it keeps asking, and I cannot hit Control-c to skip, so I have to enter an invalid
PIN and wait, then after about 20-30 seconds it will fallback to asking for a password. I'd prefer
if this experience was smoother, but I don't expect I will be using it much, if at all.

To wipe the fido2 slots use

```
systemd-cryptenroll --wipe-slot=fido2 /dev/sda2
```

## Age

age doesn't support FIDO keys, so I'm using PIV on my Yubikey.

## Master key

If I use an ssh key, then I have to put the private key on to the machine I'm bootstrapping. I also prefer FIDO2 SSH keys, but age doesn't support that. age doesn't support ssh-agent.

If I were to use a PIV key with my yubikey, then I have to have PCSCD setup on the bootstrapping machine, but that requires a rebuild, and isn't convenient for bootstrapping.

I had considered jettisoning GPG and using SSH for signing commits, but I still can't use a FIDO2 ssh key with age and I'd still have to have PCSCD setup on the bootstrapping machine to use a PIV master key.

The simplest thing is to just use a password protected age or ssh key. I settled on just using an age key that is password protected, because they are extremely simple to create.

Create a key:

```
age-keygen | age -p -o master-identity.key
```

If you leave the passphrase empty, then age generates a passphrase. The public key is printed, and can be copied and pasted into `master-keys.txt`.

On my bootstrapping machine, I can just use this master key with the passphrase. I can also add a PIV key that I can use on a bootstrapped machine.

### PIV setup

Configure the number of PIN and PUK retries (3 for both) this resets the PINs to the factory default (123456) and (12345678), respectively

```
ykman piv access set-retries 3 3
```

Setup the device by changing the pin

```
ykman piv access change-pin
```

The PUK pin (used to unblock if the regular pin is entered incorrectly)

```
ykman piv access change-puk
```

Generate a management key protected by the PIN (TDES is required by age-yubikey-plugin until this issue is resolved https://github.com/str4d/age-plugin-yubikey/issues/92)

```
ykman piv access change-management-key -a TDES --protect
```

Following https://developers.yubico.com/PIV/Guides/Generating_keys_using_OpenSSL.html to generate a P-256 key. I generated a keypair in my ctmg vault.

```
openssl ecparam -name prime256v1 -genkey -noout -out authentication-private.pem
```

`prime256v1` is the OpenSSL name for what is also known as the `secp256r1` curve.

The public key is extracted using

```
openssl ec -in authentication-private.pem -pubout -out authentication-public.pem
```

Import the private key:

```
ykman piv keys import 9a authentication-private.pem
```

Generate a self-signed certificate using:

```
ykman piv certificates generate -s "CN=PIV authentication key" -d 36500 9a authentication-public.pem
```

This process should be repeated for slots `9a`, `9c`, and `9d`, which are for authentication, signing, and encryption, respectively.

```
openssl ecparam -name prime256v1 -genkey -noout -out signing-private.pem
openssl ec -in signing-private.pem -pubout -out signing-public.pem
ykman piv keys import 9c signing-private.pem
ykman piv certificates generate -s "CN=signing key" -d 36500 9c signing-public.pem
openssl ecparam -name prime256v1 -genkey -noout -out encrypting-private.pem
openssl ec -in encrypting-private.pem -pubout -out encrypting-public.pem
ykman piv keys import 9d encrypting-private.pem
ykman piv certificates generate -s "CN=encryption key" -d 36500 9d encrypting-public.pem
```

I setup age-plugin-yubikey on each yubikey using:

```
age-plugin-yubikey -g --slot 1 --pin-policy once --touch-policy cached --force
```

## git hooks

To install git hooks run:

```
devenv tasks run devenv:git-hooks:install
```

If `flake-checker` is stale and complains about the `nixpkgs` version (e.g.
rejecting a release branch it doesn't recognize yet), run:

```
devenv update
devenv tasks run devenv:git-hooks:install
```

## nixos

An installation/rescue ISO file based on the NixOS installation ISO file, but preconfigured with my
user accounts and modules.

It has all the tools I need to provision a new machine, reprovision, or rescue an existing machine.

The `run-vm` script will boot the ISO on a qemu VM.

## LICENSE

```
© 2025 technosophist

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.

This Source Code Form is "Incompatible With Secondary Licenses", as
defined by the Mozilla Public License, v. 2.0.
```
