#!@bash@
set -euo pipefail

# Exit 0 when running on AC (a Mains power supply is online), non-zero when on
# battery (or when there is no AC adapter at all). Pure bash -- reads /sys with
# the `read` builtin so it has no runtime dependencies beyond the interpreter.
#
# Used by the laptop idle policy (nixosModules/laptop.nix) to make each swayidle
# timeout decide lock/blank/suspend by power state *at fire time*. POWER_SUPPLY_ROOT
# is overridable so tests can point it at a fixture instead of the real /sys.
root="${POWER_SUPPLY_ROOT:-/sys/class/power_supply}"

shopt -s nullglob
for supply in "$root"/*; do
  read -r type <"$supply/type" 2>/dev/null || continue
  [[ $type == Mains ]] || continue
  read -r online <"$supply/online" 2>/dev/null || continue
  [[ $online == 1 ]] && exit 0
done
exit 1
