// Radius environment for the Azure target: Kubernetes compute with Microsoft Entra
// Workload Identity + the Azure provider scope, so container `connections { iam }`
// can provision managed identities + RBAC for passwordless access. Deployed by the
// pipeline / aks-up.sh with the AKS OIDC issuer URL. Local (kind) keeps the plain
// `rad env create` in radius-recipes.sh (no identity, no Azure provider).
extension radius

@description('AKS OIDC issuer URL (aks.outputs.oidcIssuerUrl / az aks show).')
param oidcIssuer string

@description('Azure subscription id for the provider scope + managed resources.')
param azureSubscriptionId string

@description('Azure resource group for the provider scope + managed resources.')
param azureResourceGroup string

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'default'
  properties: {
    compute: {
      kind: 'kubernetes'
      resourceId: 'self'
      namespace: 'default'
      identity: {
        kind: 'azure.com.workload'
        oidcIssuer: oidcIssuer
      }
    }
    providers: {
      azure: {
        scope: '/subscriptions/${azureSubscriptionId}/resourceGroups/${azureResourceGroup}'
      }
    }
  }
}
