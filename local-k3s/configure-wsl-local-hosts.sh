#!/usr/bin/env sh
set -eu

HOST_IP="${1:-}"

if [ -z "$HOST_IP" ]; then
  HOST_IP="$(ip route show default | awk 'NR == 1 {print $3}')"
fi

if [ -z "$HOST_IP" ]; then
  echo "Cannot detect Windows host IP. Pass it explicitly."
  exit 1
fi

tmp="$(mktemp)"

grep -vE '[[:space:]](gitlab\.local|registry\.local|labs\.local)([[:space:]]|$)' /etc/hosts > "$tmp" || true
printf '%s gitlab.local registry.local\n' "$HOST_IP" >> "$tmp"
printf '127.0.0.1 labs.local\n' >> "$tmp"

sudo cp "$tmp" /etc/hosts
rm -f "$tmp"

echo "WSL local hosts configured to $HOST_IP"
getent hosts gitlab.local registry.local labs.local
