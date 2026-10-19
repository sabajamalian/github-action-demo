#!/usr/bin/env bash
# One-time bootstrap for the OctoCAT Supply deployment. Safe to re-run: existing
# resources are reused and settings are reapplied.
#
# Azure (one resource group):
#   - Container registry (Basic, admin user disabled)
#   - Pull identity with AcrPull, used by the container apps to pull images
#   - Deploy identity for GitHub Actions OIDC: Contributor on the resource group,
#     AcrPush on the registry, and a federated credential for the deploy environment
#   - Container Apps environment (no Log Analytics, in ACA_LOCATION) with the api and
#     web apps, running a placeholder image until the first deploy
# GitHub:
#   - Secrets AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID and variable ACR_NAME
#   - The deploy environment limited to main (skipped with SKIP_GITHUB_ENVIRONMENT=true,
#     because branch policies need a public repo on the GitHub Free plan)
#
# Prerequisites: az logged in with rights to create resources and role assignments
# in SUBSCRIPTION_ID, and gh authenticated as an admin of GITHUB_REPO.
# Every setting below can be overridden with an environment variable.
#
# Usage: bash infra/setup-azure.sh

set -euo pipefail

SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-0827a0cd-7ceb-4cc8-be0b-19d909be7fa3}"
LOCATION="${LOCATION:-centralus}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-octacat}"
GITHUB_REPO="${GITHUB_REPO:-sabajamalian/github-action-demo}"
ACA_ENV="${ACA_ENV:-cae-octacat-westus3}"
# The Container Apps environment and both apps can live in a different region than
# the registry and identities. centralus rejected new environments with
# AKSCapacityHeavyUsage during the initial setup, so they default to westus3.
ACA_LOCATION="${ACA_LOCATION:-westus3}"
API_APP="${API_APP:-octacat-api}"
WEB_APP="${WEB_APP:-octacat-web}"
PULL_IDENTITY="${PULL_IDENTITY:-id-octacat-acrpull}"
DEPLOY_IDENTITY="${DEPLOY_IDENTITY:-id-octacat-github}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-production}"
SKIP_GITHUB_ENVIRONMENT="${SKIP_GITHUB_ENVIRONMENT:-false}"

FEDERATED_CREDENTIAL_NAME="github-$ENVIRONMENT_NAME"
OIDC_ISSUER="https://token.actions.githubusercontent.com"
OIDC_AUDIENCE="api://AzureADTokenExchange"
PLACEHOLDER_IMAGE="mcr.microsoft.com/k8se/quickstart:latest"

log() { printf '\n==> %s\n' "$*"; }
fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

short_hash() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum | cut -c1-6
  else
    printf '%s' "$1" | sha1sum | cut -c1-6
  fi
}

# Registry names are global, so derive a stable suffix that reruns reproduce.
ACR_NAME="${ACR_NAME:-acroctacat$(short_hash "$SUBSCRIPTION_ID/$RESOURCE_GROUP")}"

# Succeeds when the given az show command finds a resource.
exists() {
  [ -n "$("$@" --query id -o tsv 2>/dev/null || true)" ]
}

ensure_identity() {
  local name="$1"
  if exists az identity show --name "$name" --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID"; then
    echo "Identity $name already exists"
  else
    az identity create --name "$name" --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none
    echo "Created identity $name"
  fi
}

identity_field() {
  az identity show --name "$1" --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" --query "$2" -o tsv
}

# Uses the principal ID directly so no Microsoft Graph lookup is needed, and retries
# because a brand-new identity can take a moment to replicate.
ensure_role() {
  local principal_id="$1" role="$2" scope="$3" label="$4" count attempt
  count="$(az role assignment list --scope "$scope" --role "$role" \
    --fill-principal-name false --subscription "$SUBSCRIPTION_ID" \
    --query "length([?principalId=='$principal_id'])" -o tsv)"
  if [ "$count" != "0" ]; then
    echo "$label already has $role"
    return 0
  fi
  for attempt in 1 2 3 4 5 6; do
    if az role assignment create --assignee-object-id "$principal_id" \
      --assignee-principal-type ServicePrincipal --role "$role" --scope "$scope" \
      --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none; then
      echo "Assigned $role to $label"
      return 0
    fi
    echo "Assigning $role to $label failed (attempt $attempt), retrying in 15 seconds"
    sleep 15
  done
  fail "Could not assign $role to $label on $scope"
}

ensure_container_app() {
  local name="$1" port="$2"
  if exists az containerapp show --name "$name" --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID"; then
    echo "Container app $name already exists, keeping its image and scale settings"
    return 0
  fi
  echo "Creating container app $name (a 'Role assignment failed' message from az is harmless, AcrPull is already assigned)"
  az containerapp create --name "$name" --resource-group "$RESOURCE_GROUP" \
    --environment "$ACA_ENV" --image "$PLACEHOLDER_IMAGE" \
    --ingress external --target-port "$port" \
    --min-replicas 0 --max-replicas 1 --cpu 0.25 --memory 0.5Gi \
    --user-assigned "$PULL_IDENTITY_ID" \
    --registry-server "$ACR_LOGIN_SERVER" --registry-identity "$PULL_IDENTITY_ID" \
    --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none
  echo "Created container app $name"
}

app_fqdn() {
  az containerapp show --name "$1" --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" --query properties.configuration.ingress.fqdn \
    --only-show-errors -o tsv
}

log "Checking prerequisites"
command -v az >/dev/null 2>&1 || fail "Azure CLI (az) is not installed"
command -v gh >/dev/null 2>&1 || fail "GitHub CLI (gh) is not installed"
TENANT_ID="$(az account show --subscription "$SUBSCRIPTION_ID" --query tenantId -o tsv)" ||
  fail "az cannot access subscription $SUBSCRIPTION_ID, run 'az login' first"
gh auth status --hostname github.com >/dev/null 2>&1 ||
  fail "gh is not authenticated, run 'gh auth login' first"
[ "$(gh api "repos/$GITHUB_REPO" --jq '.permissions.admin' 2>/dev/null || true)" = "true" ] ||
  fail "The gh user needs admin access to $GITHUB_REPO"
echo "Subscription $SUBSCRIPTION_ID (tenant $TENANT_ID), repo $GITHUB_REPO"

log "Ensuring the containerapp az extension"
az extension add --name containerapp --upgrade --only-show-errors

log "Resource group $RESOURCE_GROUP in $LOCATION"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" \
  --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none

log "Container registry $ACR_NAME"
if exists az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID"; then
  echo "Registry $ACR_NAME already exists"
else
  [ "$(az acr check-name --name "$ACR_NAME" --subscription "$SUBSCRIPTION_ID" \
    --query nameAvailable -o tsv)" = "true" ] ||
    fail "Registry name $ACR_NAME is taken, set ACR_NAME to another globally unique name"
  az acr create --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
    --sku Basic --admin-enabled false --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none
  echo "Created registry $ACR_NAME"
fi
ACR_ID="$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID" --query id -o tsv)"
ACR_LOGIN_SERVER="$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID" --query loginServer -o tsv)"
RESOURCE_GROUP_ID="$(az group show --name "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID" --query id -o tsv)"

log "Managed identities and role assignments"
ensure_identity "$PULL_IDENTITY"
ensure_identity "$DEPLOY_IDENTITY"
PULL_IDENTITY_ID="$(identity_field "$PULL_IDENTITY" id)"
PULL_PRINCIPAL_ID="$(identity_field "$PULL_IDENTITY" principalId)"
DEPLOY_PRINCIPAL_ID="$(identity_field "$DEPLOY_IDENTITY" principalId)"
DEPLOY_CLIENT_ID="$(identity_field "$DEPLOY_IDENTITY" clientId)"
ensure_role "$PULL_PRINCIPAL_ID" AcrPull "$ACR_ID" "$PULL_IDENTITY"
ensure_role "$DEPLOY_PRINCIPAL_ID" Contributor "$RESOURCE_GROUP_ID" "$DEPLOY_IDENTITY"
ensure_role "$DEPLOY_PRINCIPAL_ID" AcrPush "$ACR_ID" "$DEPLOY_IDENTITY"

log "Federated credential $FEDERATED_CREDENTIAL_NAME on $DEPLOY_IDENTITY"
# Repos that use immutable OIDC subjects report their prefix here, for example
# repo:owner@<owner id>/name@<repo id>. Older repos fall back to repo:owner/name.
SUB_PREFIX="$(gh api "repos/$GITHUB_REPO/actions/oidc/customization/sub" \
  --jq '.sub_claim_prefix // empty' 2>/dev/null || true)"
[ -n "$SUB_PREFIX" ] || SUB_PREFIX="repo:$GITHUB_REPO"
FEDERATED_SUBJECT="$SUB_PREFIX:environment:$ENVIRONMENT_NAME"
if exists az identity federated-credential show --name "$FEDERATED_CREDENTIAL_NAME" \
  --identity-name "$DEPLOY_IDENTITY" --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION_ID"; then
  FIC_ACTION=update
else
  FIC_ACTION=create
fi
az identity federated-credential "$FIC_ACTION" --name "$FEDERATED_CREDENTIAL_NAME" \
  --identity-name "$DEPLOY_IDENTITY" --resource-group "$RESOURCE_GROUP" \
  --issuer "$OIDC_ISSUER" --subject "$FEDERATED_SUBJECT" --audiences "$OIDC_AUDIENCE" \
  --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none
echo "Federated credential ${FIC_ACTION}d with subject $FEDERATED_SUBJECT"

log "Container Apps environment $ACA_ENV"
env_state() {
  az containerapp env show --name "$ACA_ENV" --resource-group "$RESOURCE_GROUP" \
    --subscription "$SUBSCRIPTION_ID" --query properties.provisioningState -o tsv 2>/dev/null || true
}
ENV_STATE="$(env_state)"
if [ "$ENV_STATE" = "Failed" ]; then
  # A failed environment can't host apps, and it blocks a retry in another region.
  echo "Deleting environment $ACA_ENV left in a Failed state by an earlier run"
  az containerapp env delete --name "$ACA_ENV" --resource-group "$RESOURCE_GROUP" --yes \
    --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none
  ENV_STATE="$(env_state)"
fi
while [ "$ENV_STATE" = "ScheduledForDelete" ] || [ "$ENV_STATE" = "Deleting" ]; do
  echo "Waiting for environment $ACA_ENV to finish deleting"
  sleep 20
  ENV_STATE="$(env_state)"
done
if [ -n "$ENV_STATE" ]; then
  echo "Environment $ACA_ENV already exists ($ENV_STATE)"
else
  az containerapp env create --name "$ACA_ENV" --resource-group "$RESOURCE_GROUP" \
    --location "$ACA_LOCATION" --logs-destination none \
    --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none ||
    fail "Creating $ACA_ENV in $ACA_LOCATION failed. For capacity errors, re-run with ACA_LOCATION set to another region."
  echo "Created environment $ACA_ENV in $ACA_LOCATION"
fi

log "Container apps $API_APP and $WEB_APP"
# The api placeholder listens on 80, not 3000, so it reports unhealthy until the
# first real deploy replaces the image.
ensure_container_app "$API_APP" 3000
ensure_container_app "$WEB_APP" 80
API_FQDN="$(app_fqdn "$API_APP")"
WEB_FQDN="$(app_fqdn "$WEB_APP")"
[ -n "$API_FQDN" ] && [ -n "$WEB_FQDN" ] || fail "Could not read the container app FQDNs"

az containerapp update --name "$API_APP" --resource-group "$RESOURCE_GROUP" \
  --set-env-vars "API_CORS_ORIGINS=https://$WEB_FQDN" \
  --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none
echo "Set API_CORS_ORIGINS on $API_APP"
az containerapp update --name "$WEB_APP" --resource-group "$RESOURCE_GROUP" \
  --set-env-vars "API_HOST=$API_FQDN" "API_PORT=443" "API_PROTOCOL=https" \
  --subscription "$SUBSCRIPTION_ID" --only-show-errors -o none
echo "Set API_HOST, API_PORT, and API_PROTOCOL on $WEB_APP"

log "GitHub secrets and variables on $GITHUB_REPO"
gh secret set AZURE_CLIENT_ID --repo "$GITHUB_REPO" --body "$DEPLOY_CLIENT_ID"
gh secret set AZURE_TENANT_ID --repo "$GITHUB_REPO" --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$GITHUB_REPO" --body "$SUBSCRIPTION_ID"
gh variable set ACR_NAME --repo "$GITHUB_REPO" --body "$ACR_NAME"
echo "Set secrets AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID and variable ACR_NAME"

if [ "$SKIP_GITHUB_ENVIRONMENT" = "true" ]; then
  log "Skipping the $ENVIRONMENT_NAME environment (SKIP_GITHUB_ENVIRONMENT=true)"
  echo "Re-run without SKIP_GITHUB_ENVIRONMENT once the repo is public to create it"
else
  log "GitHub environment $ENVIRONMENT_NAME limited to main"
  gh api --method PUT "repos/$GITHUB_REPO/environments/$ENVIRONMENT_NAME" \
    -F "deployment_branch_policy[protected_branches]=false" \
    -F "deployment_branch_policy[custom_branch_policies]=true" --silent
  MAIN_POLICIES="$(gh api "repos/$GITHUB_REPO/environments/$ENVIRONMENT_NAME/deployment-branch-policies" \
    --jq '[.branch_policies[] | select(.name == "main" and (.type // "branch") == "branch")] | length')"
  if [ "$MAIN_POLICIES" = "0" ]; then
    gh api --method POST "repos/$GITHUB_REPO/environments/$ENVIRONMENT_NAME/deployment-branch-policies" \
      -f name=main -f type=branch --silent
    echo "Limited $ENVIRONMENT_NAME to the main branch"
  else
    echo "Branch policy for main already exists"
  fi
fi

log "Summary"
cat <<EOF
ACR login server:          $ACR_LOGIN_SERVER
API URL:                   https://$API_FQDN
Web URL:                   https://$WEB_FQDN
Deploy identity client ID: $DEPLOY_CLIENT_ID
Federated subject:         $FEDERATED_SUBJECT
EOF
