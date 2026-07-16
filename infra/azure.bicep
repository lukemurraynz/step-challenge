// Azure-only managed resources for StepUp (Key Vault now; the Postgres Flexible
// Server joins here in PR7). Referenced `= if (isAzure)` from app.bicep so
// app.bicep's top-level template carries NO Microsoft.* Azure types — otherwise
// Radius demands an Azure provider on the env even when the resources are
// conditionally skipped, which breaks the local kind CI smoke.
@description('Discord webhook URL to seed the Key Vault secret.')
@secure()
param discordWebhookUrl string

@description('Azure region for the managed resources.')
param azLocation string

resource keyvault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'stepup-${uniqueString(resourceGroup().id)}'
  location: azLocation
  properties: {
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
  resource discordSecret 'secrets' = {
    name: 'discord-webhook'
    properties: {
      value: discordWebhookUrl
    }
  }
}

output keyVaultId string = keyvault.id
output keyVaultName string = keyvault.name
