#!/usr/bin/env sh
set -eu

HOST_IP="${1:-}"

if [ -z "$HOST_IP" ]; then
  HOST_IP="$(ip route show default | awk 'NR == 1 {print $3}')"
fi

if [ -z "$HOST_IP" ]; then
  echo "Cannot detect host IP. Pass it explicitly: sh configure-coredns-local-hosts.sh <ip>"
  exit 1
fi

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"

if [ -z "$NODE_IP" ]; then
  echo "Cannot detect k3s node InternalIP"
  exit 1
fi

current="$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.NodeHosts}')"
filtered="$(printf '%s\n' "$current" | grep -vE '[[:space:]](gitlab\.local|registry\.local|labs\.local)([[:space:]]|$)' || true)"
node_hosts="$(printf '%s\n%s gitlab.local registry.local\n%s labs.local\n' "$filtered" "$HOST_IP" "$NODE_IP")"

kubectl -n kube-system patch configmap coredns \
  --type merge \
  -p "$(printf '{"data":{"NodeHosts":"%s"}}' "$(printf '%s' "$node_hosts" | sed ':a;N;$!ba;s/\n/\\n/g')")"

kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns --timeout=120s

echo "CoreDNS configured: GitLab/Registry -> $HOST_IP, Labs -> $NODE_IP"
