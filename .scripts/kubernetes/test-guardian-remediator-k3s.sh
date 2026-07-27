#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" != "--execute" ]]; then
  printf "Usage: K3S_TEST_CONTEXT=<context> REMEDIATOR_IMAGE=<image@sha256:digest> %s --execute\n" "$0" >&2
  exit 2
fi

context="${K3S_TEST_CONTEXT:-}"
image="${REMEDIATOR_IMAGE:-}"
[[ -n "${context}" ]] || {
  printf "K3S_TEST_CONTEXT is required\n" >&2
  exit 1
}
[[ "${image}" =~ @sha256:[a-f0-9]{64}$ ]] || {
  printf "REMEDIATOR_IMAGE must be pinned by sha256 digest\n" >&2
  exit 1
}

current_context="$(kubectl config current-context)"
[[ "${current_context}" == "${context}" ]] || {
  printf "current context %s does not match explicit k3s test context %s\n" \
    "${current_context}" "${context}" >&2
  exit 1
}

namespace="guardian-remediator-test-$(date +%s)"
cleanup() {
  kubectl --context "${context}" delete namespace "${namespace}" \
    --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl --context "${context}" create namespace "${namespace}"
kubectl --context "${context}" -n "${namespace}" apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: guardian-remediator
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: guardian-remediator
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    resourceNames: ["guardian"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: guardian-remediator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: guardian-remediator
subjects:
  - kind: ServiceAccount
    name: guardian-remediator
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: guardian-startup-config
data:
  value: present-for-initial-start
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: guardian
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: guardian
  template:
    metadata:
      labels:
        app: guardian
    spec:
      containers:
        - name: guardian
          image: ${image}
          command: ["/bin/sh", "-ec", "sleep 60; exit 1"]
          env:
            - name: REQUIRED_STARTUP_CONFIG
              valueFrom:
                configMapKeyRef:
                  name: guardian-startup-config
                  key: value
---
apiVersion: v1
kind: Pod
metadata:
  name: unrelated-sentinel
  labels:
    app: unrelated
spec:
  restartPolicy: Never
  containers:
    - name: sentinel
      image: ${image}
      command: ["/bin/sh", "-c", "sleep 600"]
YAML

for _ in $(seq 1 60); do
  pod_uid="$(kubectl --context "${context}" -n "${namespace}" get pods \
    -l app=guardian -o jsonpath='{.items[0].metadata.uid}' 2>/dev/null || true)"
  ready="$(kubectl --context "${context}" -n "${namespace}" get deployment guardian \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  available="$(kubectl --context "${context}" -n "${namespace}" get deployment guardian \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
  progressing_reason="$(kubectl --context "${context}" -n "${namespace}" get deployment guardian \
    -o 'jsonpath={.status.conditions[?(@.type=="Progressing")].reason}' 2>/dev/null || true)"
  if [[ -n "${pod_uid}" && "${ready}" == "1" && "${available}" == "1" &&
    "${progressing_reason}" == "NewReplicaSetAvailable" ]]; then
    break
  fi
  sleep 2
done
[[ -n "${pod_uid:-}" && "${ready:-}" == "1" && "${available:-}" == "1" ]] || {
  printf "guardian test deployment did not complete its initial healthy rollout\n" >&2
  exit 1
}

kubectl --context "${context}" -n "${namespace}" delete configmap guardian-startup-config

for _ in $(seq 1 60); do
  create_reason="$(kubectl --context "${context}" -n "${namespace}" get pods \
    -l app=guardian -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' \
    2>/dev/null || true)"
  generation="$(kubectl --context "${context}" -n "${namespace}" get deployment guardian \
    -o jsonpath='{.metadata.generation}' 2>/dev/null || true)"
  observed="$(kubectl --context "${context}" -n "${namespace}" get deployment guardian \
    -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)"
  updated="$(kubectl --context "${context}" -n "${namespace}" get deployment guardian \
    -o jsonpath='{.status.updatedReplicas}' 2>/dev/null || true)"
  progressing_reason="$(kubectl --context "${context}" -n "${namespace}" get deployment guardian \
    -o 'jsonpath={.status.conditions[?(@.type=="Progressing")].reason}' 2>/dev/null || true)"
  if [[ -n "${pod_uid}" && "${create_reason}" == "CreateContainerConfigError" &&
    "${generation}" == "${observed}" && "${updated}" == "1" &&
    "${progressing_reason}" == "NewReplicaSetAvailable" ]]; then
    break
  fi
  sleep 2
done
[[ -n "${pod_uid:-}" && "${create_reason:-}" == "CreateContainerConfigError" &&
  "${progressing_reason:-}" == "NewReplicaSetAvailable" ]] || {
  printf "guardian test pod did not reach the expected post-rollout create error\n" >&2
  exit 1
}

sentinel_uid="$(kubectl --context "${context}" -n "${namespace}" get pod unrelated-sentinel \
  -o jsonpath='{.metadata.uid}')"
first_seen="$(date -u --date='6 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
kubectl --context "${context}" -n "${namespace}" annotate deployment guardian \
  "guardian.switchboard.xyz/create-error-first-seen=${pod_uid}|${first_seen}"

kubectl --context "${context}" -n "${namespace}" apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: guardian-remediator-test
spec:
  backoffLimit: 0
  template:
    spec:
      serviceAccountName: guardian-remediator
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
      containers:
        - name: remediator
          image: ${image}
          command: ["/app/guardian-remediator"]
          env:
            - name: K8S_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: GUARDIAN_DEPLOYMENT
              value: guardian
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
YAML

if ! kubectl --context "${context}" -n "${namespace}" wait \
  --for=condition=complete job/guardian-remediator-test --timeout=2m; then
  kubectl --context "${context}" -n "${namespace}" logs job/guardian-remediator-test >&2 || true
  exit 1
fi

replacement_uid=""
for _ in $(seq 1 60); do
  replacement_uid="$(kubectl --context "${context}" -n "${namespace}" get pods \
    -l app=guardian -o jsonpath='{.items[0].metadata.uid}' 2>/dev/null || true)"
  [[ -n "${replacement_uid}" && "${replacement_uid}" != "${pod_uid}" ]] && break
  sleep 2
done
[[ -n "${replacement_uid}" && "${replacement_uid}" != "${pod_uid}" ]] || {
  printf "remediator did not produce a replacement guardian-test Pod UID\n" >&2
  exit 1
}

current_sentinel_uid="$(kubectl --context "${context}" -n "${namespace}" \
  get pod unrelated-sentinel -o jsonpath='{.metadata.uid}')"
[[ "${current_sentinel_uid}" == "${sentinel_uid}" ]] || {
  printf "remediator changed an unrelated pod\n" >&2
  exit 1
}

printf "guardian remediator k3s integration test passed\n"
