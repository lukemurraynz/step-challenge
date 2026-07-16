// Azure recipe for Applications.Datastores/redisCaches: Azure Cache for Redis (Basic C0).
// Registered on the Azure environment only (radius-recipes.sh when AZ_SUB/AZ_RG are set);
// kind keeps the local-dev container recipe.
// Publish: rad bicep publish --file infra/recipes/azure/redis.bicep \
//            --target br:stepupacr2026.azurecr.io/recipes/redis:latest
@description('Injected by Radius: the calling resource + environment context.')
param context object

@description('Azure region. Defaults to the target resource group location.')
param location string = resourceGroup().location

// Basic C0 = smallest/cheapest (no SLA, ~250MB) — fine for this app's pub/sub.
resource redis 'Microsoft.Cache/redis@2024-03-01' = {
  name: 'stepup-${uniqueString(context.resource.id)}'
  location: location
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
  }
}

output result object = {
  values: {
    host: redis.properties.hostName
    port: redis.properties.sslPort
    tls: true
  }
  secrets: {
    password: redis.listKeys().primaryKey
    connectionString: '${redis.properties.hostName}:${redis.properties.sslPort},password=${redis.listKeys().primaryKey},ssl=True,abortConnect=False'
  }
}
