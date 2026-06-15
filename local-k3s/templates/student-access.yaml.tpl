apiVersion: v1
kind: ServiceAccount
metadata:
  name: student-__STUDENT_NAME__
  namespace: __KUBE_NAMESPACE__
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: student-operator
  namespace: __KUBE_NAMESPACE__
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - services
      - endpoints
      - events
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - replicasets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
    verbs: ["patch"]
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: student-__STUDENT_NAME__-operator
  namespace: __KUBE_NAMESPACE__
subjects:
  - kind: ServiceAccount
    name: student-__STUDENT_NAME__
    namespace: __KUBE_NAMESPACE__
roleRef:
  kind: Role
  name: student-operator
  apiGroup: rbac.authorization.k8s.io

