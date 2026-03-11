_: arg:
let
  inherit (builtins)
    attrNames
    elem
    filter
    isAttrs
    readDir
    ;
  dir = if isAttrs arg then arg.dir else arg;
  excludes = if isAttrs arg && arg ? excludes then arg.excludes else [ ];
  entries = readDir dir;
in
filter (name: entries.${name} == "regular" && !(elem name excludes)) (attrNames entries)
