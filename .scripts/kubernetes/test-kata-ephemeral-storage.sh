#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" != "--execute" ]]; then
  printf "Usage: KATA_TEST_CONTEXT=<context> KATA_STORAGE_TEST_IMAGE=<image@sha256:digest> %s --execute\n" "$0" >&2
  printf "Creates and removes an isolated Kata namespace and writes 192 MiB in one test container.\n" >&2
  exit 64
fi

context="$(kubectl config current-context)"
expected_context="${KATA_TEST_CONTEXT:-}"
test_image="${KATA_STORAGE_TEST_IMAGE:-}"
[[ -n "${expected_context}" && "${context}" == "${expected_context}" ]] || {
  printf "current context must match explicit KATA_TEST_CONTEXT\n" >&2
  exit 1
}
[[ "${test_image}" =~ @sha256:[a-f0-9]{64}$ ]] || {
  printf "KATA_STORAGE_TEST_IMAGE must be pinned by sha256 digest\n" >&2
  exit 1
}
kubectl get runtimeclass kata-qemu-snp >/dev/null

namespace="guardian-kata-storage-test-$(date +%s)"
cleanup() {
  kubectl delete namespace "${namespace}" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl create namespace "${namespace}"
kubectl apply -n "${namespace}" -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: writable-layer-probe
spec:
  runtimeClassName: kata-qemu-snp
  restartPolicy: Never
  containers:
    - name: writer
      image: ${test_image}
      command:
        - sh
        - -ec
        - |
          dd if=/dev/zero of=/rootfs-probe bs=1M count=192
          sync
          sleep 600
      resources:
        requests:
          ephemeral-storage: 64Mi
        limits:
          ephemeral-storage: 128Mi
YAML

deadline=$((SECONDS + 300))
while ((SECONDS < deadline)); do
  phase="$(kubectl get pod writable-layer-probe -n "${namespace}" -o jsonpath='{.status.phase}')"
  reason="$(kubectl get pod writable-layer-probe -n "${namespace}" -o jsonpath='{.status.reason}')"
  message="$(kubectl get pod writable-layer-probe -n "${namespace}" -o jsonpath='{.status.message}')"
  waiting_reason="$(kubectl get pod writable-layer-probe -n "${namespace}" \
    -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}')"

  if [[ "${reason}" == "Evicted" && "${message}" == *ephemeral-storage* ]]; then
    printf "Kata writable-layer accounting appears enforced in context %s.\n" "${context}"
    printf "It is safe to test guardian ephemeral-storage request=1Gi and limit=8Gi in canary values.\n"
    exit 0
  fi
  if [[ "${phase}" == "Running" ]] &&
    kubectl exec -n "${namespace}" writable-layer-probe -- test -f /rootfs-probe; then
    sleep 15
  elif [[ "${waiting_reason}" == "ErrImagePull" || "${waiting_reason}" == "ImagePullBackOff" ]]; then
    printf "Kata storage test image could not be pulled\n" >&2
    exit 1
  else
    sleep 5
  fi
done

printf "Kata writable-layer accounting was not demonstrated within five minutes.\n" >&2
printf "Leave components.guardian.ephemeralStorage.enabled=false and rely on in-guest metrics/remediation.\n" >&2
exit 2
