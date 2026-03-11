#!@bash@
set -euo pipefail

echo "Clearing sudo"
/run/wrappers/bin/sudo -K
echo "Clearing gpg-agent"
@gpgconf@ --kill gpg-agent
