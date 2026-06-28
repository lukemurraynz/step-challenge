#!/usr/bin/env bash
set -euo pipefail

# StepUp cloud teardown — companion to aks-up.sh.
#   (default)         STOP the AKS cluster — halts node billing, preserves
#                     everything (deployments, data, images). Resume with aks-up.sh.
#   --destroy | --all DELETE the whole resource group (AKS + ACR + images + all).
#                     Irreversible; you'd re-provision from scratch.

RG=stepup-rg
AKS=stepup-aks

MODE="stop"
case "${1:-}" in
  --destroy|--all) MODE="destroy" ;;
  "")              ;;
  *)               echo "Usage: $0 [--destroy]" >&2; exit 1 ;;
esac

az account show >/dev/null 2>&1 || { echo "Run 'az login' first." >&2; exit 1; }

if [ "$MODE" = "destroy" ]; then
  read -rp "This DELETES resource group '$RG' (AKS + ACR + images — everything). Type 'delete' to confirm: " confirm
  [ "$confirm" = "delete" ] || { echo "Aborted."; exit 1; }
  echo "Deleting resource group '$RG'..."
  az group delete -n "$RG" --yes
  echo "Done — all StepUp Azure resources removed."
  exit 0
fi

# Default: stop the cluster (halt node billing, keep everything)
echo "Stopping AKS '$AKS' to halt node billing..."
az aks stop -g "$RG" -n "$AKS"
echo "Stopped. Resume with ./scripts/aks-up.sh (or 'az aks start -g $RG -n $AKS')."
echo "Note: Basic ACR + managed disks still cost a few cents/day; run with --destroy to remove everything."