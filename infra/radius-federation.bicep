// infra/radius-federation.bicep — deployed into the identity RG, after AKS exists
targetScope = 'resourceGroup'

@description('Existing OIDC managed identity to federate to the Radius control plane.')
param identityName string

@description('AKS OIDC issuer URL.')
param aksOidcIssuer string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: identityName
}

@batchSize(1) // Azure rejects concurrent federated-credential writes on one identity
resource radiusFeds 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = [
  for sa in ['applications-rp', 'bicep-de', 'ucp', 'dynamic-rp']: {
    parent: identity
    name: 'radius-${sa}'
    properties: {
      issuer: aksOidcIssuer
      subject: 'system:serviceaccount:radius-system:${sa}'
      audiences: [ 'api://AzureADTokenExchange' ]
    }
  }
]
