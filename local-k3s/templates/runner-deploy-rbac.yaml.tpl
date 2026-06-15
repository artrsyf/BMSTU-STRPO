apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ci-deployer
  namespace: __KUBE_NAMESPACE__
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - configmaps
      - secrets
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["traefik.io"]
    resources:
      - middlewares
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer-gitlab-runner-default
  namespace: __KUBE_NAMESPACE__
subjects:
  - kind: ServiceAccount
    name: default
    namespace: __RUNNER_NAMESPACE__
roleRef:
  kind: Role
  name: ci-deployer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer-gitlab-runner
  namespace: __KUBE_NAMESPACE__
subjects:
  - kind: ServiceAccount
    name: gitlab-runner
    namespace: __RUNNER_NAMESPACE__
roleRef:
  kind: Role
  name: ci-deployer
  apiGroup: rbac.authorization.k8s.io
