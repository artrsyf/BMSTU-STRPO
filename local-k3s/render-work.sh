#!/usr/bin/env sh
set -eu

WORK_NAME="${WORK_NAME:-driving-school}"
KUBE_NAMESPACE="${KUBE_NAMESPACE:-$WORK_NAME}"
K8S_OUT="${K8S_OUT:-.generated/$WORK_NAME}"
RUNNER_NAMESPACE="${RUNNER_NAMESPACE:-gitlab-runner}"

mkdir -p "$K8S_OUT"

render() {
  src="$1"
  dst="$2"

  sed \
    -e "s|__WORK_NAME__|$WORK_NAME|g" \
    -e "s|__KUBE_NAMESPACE__|$KUBE_NAMESPACE|g" \
    -e "s|__RUNNER_NAMESPACE__|$RUNNER_NAMESPACE|g" \
    "$src" > "$dst"
}

render templates/work-namespace.yaml.tpl "$K8S_OUT/00-namespace.yaml"
render templates/runner-deploy-rbac.yaml.tpl "$K8S_OUT/01-runner-deploy-rbac.yaml"

echo "Rendered work infrastructure manifests to $K8S_OUT"
echo "  WORK_NAME=$WORK_NAME"
echo "  KUBE_NAMESPACE=$KUBE_NAMESPACE"

