{
  description = "Thoughtfull Systems nixfiles";
  nixConfig = {
    extra-substituters = [
      "https://cache.numtide.com"
      "https://devenv.cachix.org"
    ];
    extra-trusted-public-keys = [
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
  inputs = {
    agenix = {
      inputs = {
        darwin.follows = "";
        home-manager.follows = "";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
      url = "github:ryantm/agenix";
    };
    claude-desktop = {
      inputs.nixpkgs.follows = "unstable";
      url = "github:aaddrick/claude-desktop-debian";
    };
    devenv = {
      inputs = {
        crate2nix.inputs = {
          cachix.inputs.nixpkgs.follows = "nixpkgs";
          crate2nix_stable.inputs = {
            cachix.inputs.nixpkgs.follows = "nixpkgs";
            nixpkgs.follows = "nixpkgs";
          };
        };
        nixpkgs.follows = "nixpkgs";
      };
      url = "github:cachix/devenv";
    };
    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko";
    };
    flake-utils = {
      inputs.systems.follows = "systems";
      url = "github:numtide/flake-utils";
    };
    impermanence = {
      inputs = {
        nixpkgs.follows = "";
        home-manager.follows = "";
      };
      url = "github:nix-community/impermanence";
    };
    kryptonix.url = "github:technosophist/kryptonix";
    llm-agents = {
      inputs.nixpkgs.follows = "unstable";
      url = "github:numtide/llm-agents.nix";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    systems.url = "github:nix-systems/default";
    unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs =
    inputs@{
      self,
      devenv,
      nixpkgs,
      ...
    }:
    let
      # Import custom lib functions
      customLib = import ./lib.nix self;
      # Extend nixpkgs lib with thoughtfull namespace
      lib = nixpkgs.lib.extend (
        _final: _prev: {
          thoughtfull = {
            inherit (customLib)
              dirFiles
              dirPaths
              githubKeys
              types
              ;
          };
        }
      );
      inherit (customLib) forEachSystem;
    in
    {
      checks = import ./tests.nix self;
      emacsPackages = import ./emacsPackages.nix self;
      inherit lib;
      nixosConfigurations = import ./nixosConfigurations.nix self;
      nixosModules.default = import ./nixosModules/default.nix;
      overlays = import ./overlays.nix self;
      packages = forEachSystem (
        system:
        let
          pkgs = import nixpkgs {
            config.allowUnfree = true;
            inherit system;
            overlays = [ self.overlays.thoughtfull ];
          };
        in
        {
          inherit (pkgs.thoughtfull)
            attach-yubikey
            brightness
            detach-yubikey
            dictation
            mic
            nixfiles
            options-doc
            pins
            power-menu
            run-vm
            speaker
            ssh-askpass
            theme-toggle
            uns
            usb-menu
            waybar-weather
            waybar-yubikey
            yubikey-totp
            ;
        }
      );
      devShells = forEachSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [ ./devenv.nix ];
          };
        }
      );
    };
}
