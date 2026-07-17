// Azure recipe for Applications.Core/extenders: StepUp Postgres on Azure Database
// for PostgreSQL Flexible Server (Burstable B1ms, PG 16) with logical replication
// enabled for Drasi CDC. Registered on the Azure environment only (radius-recipes.sh
// POSTGRES_RECIPE override). Schema/seed/roles are applied out-of-band by the
// postgres-init Job — Flexible Server has no /docker-entrypoint-initdb.d.
// Publish: rad bicep publish --file infra/recipes/azure/postgres.bicep \
//            --target br:ghcr.io/willvelida/stepup-recipes/postgres-azure:latest
@description('Injected by Radius: the calling resource + environment context.')
param context object

@description('Azure region. Defaults to the target resource group location.')
param location string = resourceGroup().location

@description('Administrator login for the Flexible Server (cannot be changed later).')
param administratorLogin string = 'stepupadmin'

@description('Administrator password — passed at recipe-register time from a gh secret.')
@secure()
param administratorLoginPassword string

@description('Database the app + Drasi use.')
param databaseName string = 'stepup'

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: 'stepup-${uniqueString(context.resource.id)}'
  location: location
  sku: {
    name: 'Standard_B1ms'   // Burstable, cheapest — 1 vCPU / 2 GB
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    storage: { storageSizeGB: 32 }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
    // Password auth for now (Drasi/Debezium can't use Entra); the passwordless PR
    // flips activeDirectoryAuth on + adds an Entra admin for the app connection.
    authConfig: { passwordAuth: 'Enabled', activeDirectoryAuth: 'Disabled' }
    network: { publicNetworkAccess: 'Enabled' }
  }
}

// Logical replication for Drasi CDC. wal_level + max_worker_processes are server
// parameters (each triggers a restart) — serialize them so the restarts don't race.
resource walLevel 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: pg
  name: 'wal_level'
  properties: { value: 'logical', source: 'user-override' }
}

resource maxWorkers 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: pg
  name: 'max_worker_processes'
  properties: { value: '16', source: 'user-override' }
  dependsOn: [ walLevel ]
}

// Let the AKS-hosted app + Drasi (other Azure services) reach the server.
resource allowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pg
  name: 'AllowAllAzureServices'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
  dependsOn: [ maxWorkers ]
}

resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: databaseName
  properties: { charset: 'UTF8', collation: 'en_US.utf8' }
  dependsOn: [ allowAzure ]
}

// Deterministic public FQDN (avoids a reference() call in the output).
var fqdn = '${pg.name}.postgres.database.azure.com'

output result object = {
  values: {
    host: fqdn
    port: 5432
    database: databaseName
    username: administratorLogin
    sslMode: 'Require'
  }
  secrets: {
    #disable-next-line outputs-should-not-contain-secrets
    password: administratorLoginPassword
    #disable-next-line outputs-should-not-contain-secrets
    connectionString: 'Host=${fqdn};Port=5432;Username=${administratorLogin};Password=${administratorLoginPassword};Database=${databaseName};SSL Mode=Require;Trust Server Certificate=true'
  }
}
