# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

```bash
# Enter development shell (auto-activates via direnv)
direnv allow

# Check flake validity
nix flake check

# Build ISO image for nixos
nix build .#nixosConfigurations.nixos.config.system.build.isoImage

# Verify changes by running pre-commit hooks
devenv tasks run devenv:git-hooks:run

# Format Nix files
nixfmt-rfc-style <file.nix>
```

**Verifying Changes:** Always run `devenv tasks run devenv:git-hooks:run` to verify changes before committing. This runs all configured hooks including: `nixfmt-rfc-style`, `deadnix`, `statix`, `shellcheck`, `shfmt`, `eclint`, `gitlint`, and others configured in `devenv.nix`.

## Architecture Overview

This is a NixOS flake-based system configuration framework using nixpkgs 25.11 with these key integrations:
- **agenix**: Secret management (encrypted files in repo)
- **disko**: Declarative disk partitioning
- **impermanence**: Stateless root filesystem with persistent `/persistent` mount

### Module System

All modules in `nixosModules/` are imported unconditionally. Modules use NixOS options to conditionally enable features rather than conditional imports.  New modules are manually added to `nixosModules/default.nix` (using `lib.dirPaths` prevented the options documentation from linking to the correct file).

**Module patterns:**
- Simple module: Single `.nix` file (for example, `git.nix`)
- Complex module: Parent `.nix` file + directory with same name containing supporting files (for example, `sway.nix` + `sway/`)

**Standard module structure:**
```nix
{ config, lib, pkgs, thoughtfull, ... }:
let
  inherit (lib) mkDefault mkIf mkOption;
  cfg = config.thoughtfull.programs.modulename;
in
{
  config = mkIf cfg.enable { ... };
  options.thoughtfull.programs.modulename = {
    enable = mkEnableOption "modulename";
  };
}
```

**Custom namespace:** Modules for new programs and services or global options or "category" modules that configure across multiple programs/services (for example, `rust.nix` installs system packages, emacs packages, configures environment variables, etc.) live under `config.thoughtfull.*`:
- `thoughtfull.user` - User account configuration
- `thoughtfull.impermanence` - Stateless root configuration
- `thoughtfull.graphical` - Graphical environment toggle
- `thoughtfull.programs.*` - Program-specific options
- `thoughtfull.rust` - Category module

**Extending upstream modules:** Usually upstream modules are configured with reasonable defaults and only enabled if they're a dependency of a category module or some other module, or if the user enables it in a nixosConfiguration.  Sometimes extensions to upstream NixOS modules add a `thoughtfull` option to the upstream options.  For example for `services.syncthing` there's `services.syncthing.thoughtfull.keyFile` etc.

**Scripts:** Scripts in modules should assume the programs they need exist on the path.  They should avoid binding directly to specific binaries in the nix store.  This allows for a rebuild switch without breaking things or having to restart a bunch of things so they see new versions of executables.  In particular, scripts using, say, bash should use `#!/usr/bin/env bash` and ensure that `programs.bash.enable` is true, and similarly for other programs.

### Key Library Functions (lib.nix)

- `dirFiles`: List .nix files in a directory
- `githubKeys`: Fetch SSH public keys from GitHub by username
- `writeArgcScript`: Write bash script using Argc framework

### Package System

Custom packages in `packages/` use template substitution via `replaceVars` to inject tool paths at build time. Packages should be overridable so the NixOS modules can pass in customized versions of dependent packages.  Simple scripts can be written simply.  Scripts meant for user interaction or needing to take arguments, should use `lib.writeArgcScript` and use the Argc Bash framework.

### Host Configurations

- `nixosConfigurations/bootstrap.nix`: Template for provisioning new systems with `BOOTSTRAP` replaced with the name of the provisioned system.
- `nixosConfigurations/nixos.nix`: Minimal ISO environment for initial provisioning

## Testing

Tests are located in the `tests/` directory. Each module should have a corresponding test file (e.g., `tests/avahi.nix` for `nixosModules/avahi.nix`).

### Running Tests

```bash
# Run all tests
nix flake check

# Run a specific test (e.g., avahi)
nix build .#checks.x86_64-linux.avahi

# Run test in interactive mode for debugging
nix build .#checks.x86_64-linux.avahi.driverInteractive
./result/bin/nixos-test-driver
```

### Test-Driven Development Workflow

When modifying a module, follow this workflow:

1. **Update test expectations first** - Modify the test in `tests/` to reflect the desired behavior
2. **Wait for user review** - Present the test changes to the user and wait for approval before proceeding
3. **Verify the test fails** - After approval, run the specific test to confirm it fails as expected
4. **Update the module** - Make changes to the module in `nixosModules/`
5. **Verify the test passes** - Run the test again to confirm it now passes

**IMPORTANT: Always wait for user review and approval of test changes before running tests or modifying modules.** This ensures the user understands what behavior is being tested and agrees with the approach before implementation begins.

### Test Structure

Tests use NixOS VM testing framework (`nixpkgs.testers.nixosTest`). A typical test:
- Imports the module being tested
- Sets up one or more test VMs
- Runs commands to verify expected behavior
- Tests default values (use module's `mkDefault` settings without overriding)

## Git and Version Control

**IMPORTANT: Never commit or push changes automatically. Always present changes for user review and approval before committing.**

When the user requests commits:
- Present a summary of changes
- Wait for explicit user approval
- Only create commits after approval is given

**Never push commits to remote repositories unless explicitly instructed by the user.** After creating commits, inform the user that changes are ready to push but wait for their explicit instruction to do so.

## Conventions

- Use `mkDefault` for all option values to allow overrides in host configurations
- Use `inherit (lib) ...` pattern for importing library functions
- Place supporting files in a directory matching the module name
- Custom options go under `thoughtfull.*` namespace to avoid conflicts with nixpkgs
- When creating PRs, do not include a "Test plan" section.
- Shell scripts should use the bash interpreter and `set -euo pipefail`.
