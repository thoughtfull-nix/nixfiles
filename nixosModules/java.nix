{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) java;
  inherit (lib) mkDefault mkIf;
  inherit (pkgs) visualvm;
in
{
  environment = mkIf java.enable {
    sessionVariables = {
      _JAVA_AWT_WM_NONREPARENTING = 1;
      JDK_JAVA_OPTIONS =
        "-Dswing.defaultlaf=com.sun.java.swing.plaf.gtk.GTKLookAndFeel"
        + " -Dswing.aatext=true"
        + " -Dawt.useSystemAAFontSettingbs=lcd"
        # may need to disable this if things get weird
        + " -Dsun.java2d.opengl=true";
    };
    systemPackages = [ visualvm ];
  };
  programs.java.enable = mkDefault true;
}
