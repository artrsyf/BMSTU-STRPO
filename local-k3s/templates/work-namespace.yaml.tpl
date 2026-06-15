apiVersion: v1
kind: Namespace
metadata:
  name: __KUBE_NAMESPACE__
  labels:
    simodo.local/work: __WORK_NAME__
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota
  namespace: __KUBE_NAMESPACE__
spec:
  hard:
    requests.cpu: "500m"
    requests.memory: "512Mi"
    limits.cpu: "1"
    limits.memory: "1Gi"
    pods: "10"
    services: "10"
    secrets: "10"
    configmaps: "20"
    persistentvolumeclaims: "3"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: __KUBE_NAMESPACE__
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: "50m"
        memory: "64Mi"
      default:
        cpu: "250m"
        memory: "256Mi"

