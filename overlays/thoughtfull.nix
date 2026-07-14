self: final: prev:
let
  inherit (prev)
    age
    argc
    bash
    git
    gnupg
    netcat
    openssh
    phraze
    pinentry-tty
    qemu
    replaceVars
    runCommandLocal
    ;
  inherit (prev.lib) getExe;
  inherit (self.inputs.disko.packages.${prev.stdenv.hostPlatform.system}) disko;

  # System-dependent lib functions from lib/system/
  replaceVarsString =
    src: replacements:
    let
      inherit (builtins) readFile;
    in
    (readFile (replaceVars src replacements));

  writeFile =
    options@{ name, src, ... }:
    let
      mkdest = if options ? directory then "mkdir -p $out${options.directory}" else "";
      replacedSrc = if options ? replacements then replaceVars src options.replacements else src;
      chmod = if options ? executable then "chmod +x ${name}" else "";
      dest = if options ? directory then "$out${options.directory}/${name}" else "$out";
    in
    runCommandLocal name { } ''
      ${mkdest}
      cp ${replacedSrc} ${name}
      ${chmod}
      cp ${name} ${dest}
    '';

  writeFileScript = options: writeFile ({ executable = true; } // options);

  writeFileScriptBin =
    options:
    writeFile (
      {
        directory = "/bin";
        executable = true;
      }
      // options
    );

  writeArgcScript =
    name: src: replacements:
    let
      # `builtins.path` forces an independent, content-addressed copy of just this file. Without
      # it, this path literal instead resolves to a subpath of the flake's own whole-source
      # checkout, which is never registered as a declared input anywhere it gets substituted in
      # as text -- so the built script's `source` line ends up pointing at a path that's absent
      # from the package's actual runtime closure on any machine that doesn't separately already
      # have this flake's source in its store.
      bashlib = builtins.path {
        path = ./write-argc-script/bashlib.bash;
        name = "bashlib.bash";
      };
      prefix = replaceVars ./write-argc-script/prefix.bash {
        bash = getExe bash;
        bashlib = bashlib;
      };
      outFile = "$out/bin/${name}";
      manDir = "$out/share/man/man1";
      # `/share/zsh` is already in `environment.pathsToLink`'s default, so files placed here get
      # merged into the system profile with no further NixOS config needed. Not named `_${name}`
      # / placed under `site-functions`: argc's generated completer isn't a normal
      # fpath-autoloadable completion function (it has no `#compdef` tag and calls `compdef`
      # itself), so it must be `source`d directly by absolute path rather than autoloaded.
      zshCompletionsDir = "$out/share/zsh/argc-completions";
    in
    runCommandLocal name { } ''
      mkdir -p $(dirname "${outFile}")
      cat "${prefix}" >"${name}"
      cat "${replaceVars src replacements}" >>"${name}"
      ${argc}/bin/argc --argc-build "${name}" "${outFile}"

      mkdir -p "${manDir}"
      ${argc}/bin/argc --argc-mangen "${name}" "${manDir}"

      mkdir -p "${zshCompletionsDir}"
      ${argc}/bin/argc --argc-completions zsh "${name}" >"${zshCompletionsDir}/${name}"
    '';
in
{
  thoughtfull = {
    # System-dependent lib functions
    inherit
      replaceVarsString
      writeArgcScript
      writeFile
      writeFileScript
      writeFileScriptBin
      ;

    # Custom packages (keep alphabetized)
    attach-yubikey = writeArgcScript "attach-yubikey" ../packages/attach-yubikey.bash {
      nc = "${netcat}/bin/nc";
    };
    brightness = import ../packages/brightness.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    detach-yubikey = writeArgcScript "detach-yubikey" ../packages/detach-yubikey.bash {
      nc = "${netcat}/bin/nc";
    };
    dictation = import ../packages/dictation.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    mic = import ../packages/mic.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    nixfiles = writeArgcScript "nixfiles" ../packages/nixfiles.bash (
      {
        age = "${age}/bin/age";
        disko = "${disko}/bin/disko";
        git = "${git}/bin/git";
        gpg = "${gnupg}/bin/gpg";
        gpgconf = "${gnupg}/bin/gpgconf";
        phraze = "${phraze}/bin/phraze";
        pinentry = "${pinentry-tty}/bin/pinentry-tty";
        raspberrypi-firmware = "";
        ssh-add = "${openssh}/bin/ssh-add";
        ssh-agent = "${openssh}/bin/ssh-agent";
        uboot-rpi4 = "";
      }
      // prev.lib.optionalAttrs prev.stdenv.hostPlatform.isAarch64 {
        raspberrypi-firmware = "${prev.raspberrypifw}/share/raspberrypi/boot";
        uboot-rpi4 = "${prev.ubootRaspberryPi4_64bit}/u-boot.bin";
      }
    );
    options-doc = import ../packages/options-doc (self // { pkgs = final; });
    pins = import ../packages/pins.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    power-menu = import ../packages/power-menu.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    run-vm = writeArgcScript "run-vm" ../packages/run-vm.bash {
      ovmf-firmware = prev.OVMF.firmware;
      ovmf-variables = prev.OVMF.variables;
      qemu = "${qemu}/bin/qemu-system-x86_64";
      qemu-img = "${qemu}/bin/qemu-img";
    };
    speaker = import ../packages/speaker.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    ssh-askpass = import ../packages/ssh-askpass.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    system-pull = import ../packages/system-pull.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    theme-toggle = import ../packages/theme-toggle.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    uns = import ../packages/uns.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    usb-menu = import ../packages/usb-menu.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    waybar-weather = import ../packages/waybar-weather.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
    waybar-yubikey = writeFileScriptBin {
      name = "waybar-yubikey";
      replacements = {
        bash = "${bash}/bin/bash";
        nc = "${netcat}/bin/nc";
      };
      src = ../packages/waybar-yubikey.bash;
    };
    yubikey-totp = import ../packages/yubikey-totp.nix {
      lib = {
        inherit writeFileScriptBin;
      };
      pkgs = final;
    };
  };
}
