{ pkgs, ... }:
let
  replaceVarsString = import ./system/replace-vars-string.nix { inherit pkgs; };
  writeArgcScript = import ./system/write-argc-script { inherit pkgs; };
  writeFile = import ./system/write-file.nix { inherit pkgs; };
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
in
{
  inherit
    replaceVarsString
    writeArgcScript
    writeFile
    writeFileScript
    writeFileScriptBin
    ;
}
