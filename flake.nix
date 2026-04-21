{
  description = "Thoughtfull Systems nixfiles";
  nixConfig = {
    extra-substituters = "https://devenv.cachix.org";
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
  };
  inputs = {
    devenv = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:cachix/devenv";
    };
    agenix = {
      inputs = {
        darwin.follows = "";
        home-manager.follows = "";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
      };
      url = "github:ryantm/agenix";
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
    kryptonix.url = "git+ssh://git@github.com/technosophist/kryptonix?ref=sedna";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    systems.url = "github:nix-systems/default";
  };
  outputs =
    inputs@{
      self,
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
          default = inputs.devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [ ./devenv.nix ];
          };
        }
      );
    };
}
