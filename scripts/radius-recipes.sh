#!/usr/bin/env bash
set -euo pipefail

# Configure the Radius 'default' environment for StepUp: ensure the group + env
# exist, register the portable-resource Recipes, and (on Azure) give the env the
# Workload Identity + Azure provider scope. Idempotent; safe to re-run.
#
# ONE app.bicep, two targets: locally the recipes provision containers; on Azure
# (AZ_SUB + AZ_RG set) the env carries Entra Workload Identity so container
# `connections { iam }` can reach managed services passwordlessly.
#
# Env vars for the Azure target (set by aks-up.sh / the Deploy workflow; unset locally):
#   AZ_SUB        Azure subscription id
#   AZ_RG         Azure resource group for the provider scope + managed resources
#   OIDC_ISSUER   AKS OIDC issuer URL (az aks show ... --query oidcIssuerProfile.issuerURL)
#
# Recipe sources (all public OCI, pulled anonymously by the in-cluster engine):
#   RECIPE_PREFIX (default ghcr.io/radius-project/recipes/local-dev) — built-in pack
#   OWN_RECIPES   (default ghcr.io/willvelida/stepup-recipes)        — our recipes
#   RECIPE_TAG    (default latest)

GROUP=default
ENV=default
NS=default
RECIPE_PREFIX="${RECIPE_PREFIX:-ghcr.io/radius-project/recipes/local-dev}"
OWN_RECIPES="${OWN_RECIPES:-ghcr.io/willvelida/stepup-recipes}"
RECIPE_TAG="${RECIPE_TAG:-latest}"

# Recipe source per portable type. Defaults = local/container recipes; the Azure
# branch overrides the ones ported to managed services. Both live on public GHCR.
REDIS_RECIPE="$OWN_RECIPES/redis:$RECIPE_TAG"
SECRETS_RECIPE="$RECIPE_PREFIX/secretstores:$RECIPE_TAG"
POSTGRES_RECIPE="$OWN_RECIPES/postgres:$RECIPE_TAG"

if [ -n "${AZ_SUB:-}" ] && [ -n "${AZ_RG:-}" ]; then
  REDIS_RECIPE="$OWN_RECIPES/redis-azure:$RECIPE_TAG"    # Azure Cache for Redis
  # SECRETS_RECIPE + POSTGRES_RECIPE go Azure in later PR6 chunks.
fi

# 0. Pin a BARE CLI workspace (UCP plane + connection to the current cluster).
#    Do NOT pass --group/--environment here: rad validates they already exist and
#    fails on a cluster where they don't yet. The group + env are created in step
#    1; the flags go on the re-pin in 1b once they exist.
rad workspace create kubernetes "$ENV" --force

# 1. Ensure the Radius resource group + environment exist (idempotent).
rad group show "$GROUP" >/dev/null 2>&1 || rad group create "$GROUP"
rad env show "$ENV" --group "$GROUP" >/dev/null 2>&1 \
  || rad env create "$ENV" --group "$GROUP" --namespace "$NS"

# 1b. Re-pin the workspace with the now-existing group + env as its defaults, so a
#     bare `rad deploy` (cluster-up.sh / aks-up.sh) resolves them without flags.
rad workspace create kubernetes "$ENV" --group "$GROUP" --environment "$ENV" --force

# 1c. On Azure, layer Workload Identity (compute.identity) + the Azure provider
#     scope onto the env via Bicep — there is no CLI flag for compute.identity.
#     Runs BEFORE recipe registration so the declarative env deploy can't drop the
#     recipes registered in step 2. Skipped locally.
if [ -n "${AZ_SUB:-}" ] && [ -n "${AZ_RG:-}" ]; then
  [ -n "${OIDC_ISSUER:-}" ] || { echo "OIDC_ISSUER required on Azure (az aks show ... --query oidcIssuerProfile.issuerURL)" >&2; exit 1; }
  rad deploy infra/env.bicep --group "$GROUP" \
    --parameters oidcIssuer="$OIDC_ISSUER" \
    --parameters azureSubscriptionId="$AZ_SUB" \
    --parameters azureResourceGroup="$AZ_RG"
fi

# 2. Register the portable-resource Recipes (paths chosen per environment above).
rad recipe register default \
  --environment "$ENV" --group "$GROUP" \
  --resource-type Applications.Datastores/redisCaches \
  --template-kind bicep \
  --template-path "$REDIS_RECIPE"

rad recipe register default \
  --environment "$ENV" --group "$GROUP" \
  --resource-type Applications.Dapr/secretStores \
  --template-kind bicep \
  --template-path "$SECRETS_RECIPE"

rad recipe register default \
  --environment "$ENV" --group "$GROUP" \
  --resource-type Applications.Core/extenders \
  --template-kind bicep \
  --template-path "$POSTGRES_RECIPE"

echo "Radius environment '$ENV' configured. Recipes:"
rad recipe list --environment "$ENV" --group "$GROUP"