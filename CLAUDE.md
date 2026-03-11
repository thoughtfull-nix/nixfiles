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

# Format Nix files (runs automatically via pre-commit)
nixfmt-rfc-style <file.nix>
```

Pre-commit hooks run automatically on commit, including: `nixfmt-rfc-style`, `deadnix`, `statix`, `shellcheck`, `shfmt`, `eclint`, `gitlint`, and others configured in `devenv.nix`.

## Architecture Overview

This is a NixOS flake-based system configuration framework using nixpkgs 25.11 with these key integrations:
- **agenix**: Secret management (encrypted files in repo)
- **disko**: Declarative disk partitioning
- **impermanence**: Stateless root filesystem with persistent `/persistent` mount

### Module System

All modules in `nixosModules/` are auto-imported via `lib.dirPaths`. Modules use NixOS options to conditionally enable features rather than conditional imports.

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

**Custom namespace:** All custom options live under `config.thoughtfull.*`:
- `thoughtfull.user` - User account configuration
- `thoughtfull.impermanence` - Stateless root configuration
- `thoughtfull.graphical` - Graphical environment toggle
- `thoughtfull.programs.*` - Program-specific options

### Key Library Functions (lib.nix)

- `dirPaths`: Import all .nix files in a directory as modules
- `dirFiles`: List .nix files in a directory
- `nixosConfiguration`: Helper wrapping `nixpkgs.lib.nixosSystem` with dependency injection
- `githubKeys`: Fetch SSH public keys from GitHub by username

### Package System

Custom packages in `packages/` use template substitution via `replaceVars` to inject tool paths at build time. Scripts use `@meta` argc annotations for CLI argument parsing (see `packages/nixfiles.bash`).

### Host Configurations

- `nixosConfigurations/bootstrap.nix`: Template for provisioning new systems with `BOOTSTRAP` replaced with the name of the provisioned system.
- `nixosConfigurations/nixos.nix`: Minimal ISO environment for initial provisioning

## Conventions

- Use `mkDefault` for all option values to allow overrides in host configurations
- Use `inherit (lib) ...` pattern for importing library functions
- Place supporting files in a directory matching the module name
- Custom options go under `thoughtfull.*` namespace to avoid conflicts with nixpkgs
- When creating PRs, do not include a "Test plan" section.
- Shell scripts should use the bash interpreter and `set -euo pipefail`.
