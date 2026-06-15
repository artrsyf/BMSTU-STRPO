#!/usr/bin/env sh
set -eu

WORK_NAME="${WORK_NAME:-driving-school}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-$WORK_NAME}"
STUDENT_NAME="${STUDENT_NAME:-}"
TOKEN_DURATION="${TOKEN_DURATION:-8h}"
ADMIN_KUBECONFIG="${KUBECONFIG:-$HOME/.kube/k3s.yaml}"
OUTPUT="${OUTPUT:-.generated/access/$WORK_NAME-$STUDENT_NAME.kubeconfig}"
API_SERVER="${API_SERVER:-}"

if [ -z "$STUDENT_NAME" ]; then
  echo "STUDENT_NAME is required"
  exit 1
fi

case "$STUDENT_NAME" in
  *[!a-z0-9-]*)
    echo "STUDENT_NAME must contain only lowercase letters, digits and hyphens"
    exit 1
    ;;
esac

mkdir -p "$(dirname "$OUTPUT")"

sed \
  -e "s|__STUDENT_NAME__|$STUDENT_NAME|g" \
  -e "s|__KUBE_NAMESPACE__|$KUBE_NAMESPACE|g" \
  templates/student-access.yaml.tpl |
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" apply -f -

token="$(
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" \
    -n "$KUBE_NAMESPACE" create token "student-$STUDENT_NAME" \
    --duration "$TOKEN_DURATION"
)"
server="$(
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" \
    config view --raw -o jsonpath='{.clusters[0].cluster.server}'
)"

if [ -n "$API_SERVER" ]; then
  server="$API_SERVER"
fi
ca="$(
  kubectl --kubeconfig "$ADMIN_KUBECONFIG" \
    config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
)"

cat > "$OUTPUT" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: local-k3s
    cluster:
      server: $server
      certificate-authority-data: $ca
users:
  - name: student-$STUDENT_NAME
    user:
      token: $token
contexts:
  - name: $WORK_NAME-$STUDENT_NAME
    context:
      cluster: local-k3s
      user: student-$STUDENT_NAME
      namespace: $KUBE_NAMESPACE
current-context: $WORK_NAME-$STUDENT_NAME
EOF

chmod 600 "$OUTPUT"
echo "Student kubeconfig created: $OUTPUT"
echo "Context: $WORK_NAME-$STUDENT_NAME"
echo "Token duration: $TOKEN_DURATION"
echo "API server: $server"
