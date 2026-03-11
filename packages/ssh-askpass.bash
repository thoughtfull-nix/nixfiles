#!@bash@

prompt="${1:-}"

# Only show dialog for PIN prompts
if [[ $prompt =~ [Pp][Ii][Nn] ]]; then
  @x11_ssh_askpass@ "$prompt"
else
  # Touch-only prompts - exit silently (user has other notifications)
  exit 1
fi
