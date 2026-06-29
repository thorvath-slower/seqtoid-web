#!/usr/bin/env bash
# CZID-13 — self-hosted (k3s) appliance installer (scaffold).
#
# Installs the seqtoid platform onto an EXISTING k3s cluster, air-gap-capable: app (seqtoid-web,
# k3s profile) + pipeline engine (seqtoid-pipeline-runner, miniwdl-on-k8s) + in-cluster MySQL 8 +
# MinIO, from a pre-built offline image bundle. No AWS. See K3S-PACKAGING-DESIGN-2026-06-29.md.
#
# This is the Bucket-A scaffold: prereq checks, license verify, image import, helm installs, and a
# health check are wired; the steps marked [BUCKET-B] need the real image bundle (#10/#205),
# reference-data staging (#334), and a live cluster to actually run (the e2e smoke is #11).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${HERE}/../charts"
VALUES="${APPLIANCE_VALUES:-${HERE}/appliance-values.yaml}"
NAMESPACE="${SEQTOID_NAMESPACE:-seqtoid}"
IMAGE_BUNDLE="${IMAGE_BUNDLE:-${HERE}/images.tar}"     # [BUCKET-B] produced by the offline-mirror build (#10/#205)
LICENSE_FILE="${LICENSE_FILE:-${HERE}/license.jwt}"
MIN_DISK_GB="${MIN_DISK_GB:-200}"                       # reference DBs are large; appliance sizing (#13 §6)
MIN_MEM_GB="${MIN_MEM_GB:-32}"

log() { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[install:ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "missing prerequisite: $1"; }

check_prereqs() {
  log "checking prerequisites…"
  require kubectl
  require helm
  kubectl cluster-info >/dev/null 2>&1 || die "no reachable kubernetes cluster (is k3s up + KUBECONFIG set?)"
  # resource minimums (the heavy WDL pipelines need real CPU/RAM/disk — see #72/#13)
  local mem_gb disk_gb
  mem_gb="$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.capacity.memory}{"\n"}{end}' 2>/dev/null \
            | sed 's/Ki$//' | awk '{s+=$1} END{printf "%d", s/1024/1024}')" || mem_gb=0
  [ "${mem_gb:-0}" -ge "$MIN_MEM_GB" ] || log "WARN: cluster memory ${mem_gb}Gi < recommended ${MIN_MEM_GB}Gi"
  log "prereqs ok (mem ~${mem_gb}Gi; ensure >= ${MIN_DISK_GB}Gi free disk for reference data)"
}

verify_license() {
  log "verifying license…"
  [ -f "$LICENSE_FILE" ] || die "license file not found: $LICENSE_FILE (set LICENSE_FILE=)"
  "${HERE}/license-verify.sh" "$LICENSE_FILE" || die "license verification failed (expired / bad signature)"
  log "license ok"
}

import_images() {
  log "importing offline image bundle…"
  if [ -f "$IMAGE_BUNDLE" ]; then
    # k3s ships containerd; import the bundle so pulls are local/air-gapped
    sudo k3s ctr images import "$IMAGE_BUNDLE"
  else
    log "WARN: image bundle $IMAGE_BUNDLE not found — [BUCKET-B] build it via the offline mirror (#10/#205);"
    log "      continuing assuming images are already present in the cluster's registry."
  fi
}

helm_install() {
  log "installing helm releases into namespace '${NAMESPACE}'…"
  kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
  # 1) storage + db (MinIO + MySQL) — documented prereqs/subcharts; install if bundled
  #    [BUCKET-B] bundle MinIO + MySQL charts or point at customer-supplied endpoints in appliance-values.yaml
  # 2) the app, k3s profile
  helm upgrade --install seqtoid-web "${CHART_DIR}/seqtoid-web" \
    -n "$NAMESPACE" -f "${CHART_DIR}/seqtoid-web/values-k3s.yaml" -f "$VALUES" --wait
  # 3) the pipeline runner (miniwdl-on-k8s) — chart lives in seqtoid-workflows; vendored into the bundle
  if [ -d "${CHART_DIR}/seqtoid-pipeline-runner" ]; then
    helm upgrade --install seqtoid-pipeline-runner "${CHART_DIR}/seqtoid-pipeline-runner" \
      -n "$NAMESPACE" -f "$VALUES" --wait
  else
    log "WARN: pipeline-runner chart not in this bundle — add seqtoid-workflows' chart (#72) to the appliance bundle."
  fi
}

stage_reference_data() {
  log "[BUCKET-B] staging reference data into MinIO (#334/#10) — skipped in scaffold."
  # the WDL pipelines need NCBI/alignment reference DBs pre-staged into the MinIO bucket; large, offline.
}

health_check() {
  log "health check…"
  kubectl -n "$NAMESPACE" rollout status deploy/seqtoid-web --timeout=300s || die "seqtoid-web not ready"
  log "appliance install complete. Reach the app via the Traefik ingress host in appliance-values.yaml."
}

main() {
  check_prereqs
  verify_license
  import_images
  helm_install
  stage_reference_data
  health_check
}
main "$@"
