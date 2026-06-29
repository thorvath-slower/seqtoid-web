# Self-Hosted Appliance (k3s) — CZID-13

Installs the seqtoid platform onto an **existing k3s** cluster, air-gap-capable. Assembles the
`#12` app chart (`values-k3s.yaml`) + the `#72` `seqtoid-pipeline-runner` chart (miniwdl-on-k8s) +
in-cluster MySQL 8 + MinIO, from an offline image bundle. No AWS at run time.

## Quick start
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml      # the target k3s
export LICENSE_FILE=./license.jwt                 # your signed license
export IMAGE_BUNDLE=./images.tar                  # the offline image bundle (#10/#205)
./install.sh                                      # prereqs → license → images → helm → health check
```

## Contents
- `install.sh` — the installer (prereq checks · license verify · image import · helm installs · health).
- `appliance-values.yaml` — the single config for all releases (the self-hosted "local-state").
- `license-verify.sh` — offline signed-license verification (fail-closed; no phone-home).

## Status (Bucket A scaffold)
The flow, license-verify contract, and helm wiring are authored + lint-clean. The steps marked
`[BUCKET-B]` need a real cluster + build artifacts: the **offline image bundle** (`#10`/`#205`), the
**reference-data staging** (`#334`), the **signed-license issuance** pipeline, and the **e2e smoke**
(`#11`). Design: `K3S-PACKAGING-DESIGN-2026-06-29.md` · `MINIWDL-ON-K8S-SPIKE-2026-06-29.md` ·
`DEPLOYMENT-PROFILES-DESIGN-2026-06-29.md`.
</content>
