extension radius
extension kubernetes with {
  kubeConfig: ''
  namespace: 'default'
}

@description('Radius-supplied environment ID.')
param environment string

@description('Image tag for the StepUp service images (built + kind-loaded locally).')
param imageTag string = 'local'

@description('Registry/prefix for the service images. Local default "stepup"; for ACR set your login server, e.g. "myregistry.azurecr.io".')
param imageRegistry string = 'stepup'

// The Radius application. Containers (added next) will reference app.id.
resource app 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'stepup'
  properties: {
    environment: environment
  }
}

// ---------------------------------------------------------------------------
// Portable Redis via a Radius recipe. The 'default' recipe (registered by
// scripts/radius-recipes.sh) runs a Redis container in THIS app's namespace and
// outputs an FQDN host, so the drasi-system reaction can reach the SAME broker.
// ---------------------------------------------------------------------------
resource cache 'Applications.Datastores/redisCaches@2023-10-01-preview' = {
  name: 'stepup-redis'
  properties: {
    environment: environment
    application: app.id
    // no recipe.name => uses the 'default' recipe registered for redisCaches
  }
}

// ---------------------------------------------------------------------------
// Postgres via a portable extenders recipe (infra/recipes/postgres.bicep).
// The recipe pins Service `postgres` in namespace `default`, so the Drasi
// source host `postgres.default.svc.cluster.local` stays unchanged.
// ---------------------------------------------------------------------------
resource postgres 'Applications.Core/extenders@2023-10-01-preview' = {
  name: 'stepup-postgres'
  properties: {
    environment: environment
    application: app.id
  }
}

// ---------------------------------------------------------------------------
// Simulator: generates random step data on each /ticker call. Reaches the
// Radius-managed Postgres cross-namespace via its service FQDN.
// imagePullPolicy IfNotPresent so the kind-loaded local image is used.
// ---------------------------------------------------------------------------
resource simulator 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'simulator'
  properties: {
    application: app.id
    container: {
      image: '${imageRegistry}/simulator:${imageTag}'
      imagePullPolicy: 'IfNotPresent'
      ports: {
        http: {
          containerPort: 8080
        }
      }
      env: {
        PG_DSN: {
          value: 'Host=${postgres.properties.host};Port=${postgres.properties.port};Username=postgres;Password=postgres;Database=${postgres.properties.database}'
        }
      }
    }
    extensions: [
      { kind: 'daprSidecar', appId: 'simulator', appPort: 8080 }
    ]
  }
}

// ---------------------------------------------------------------------------
// Dapr cron binding: posts to the simulator's /ticker every 5s, so steps
// generate automatically. Must live in the simulator's namespace so its
// sidecar loads it. Validates the dapr.io/Component-via-Bicep pattern.
// ---------------------------------------------------------------------------
resource ticker 'dapr.io/Component@v1alpha1' = {
  metadata: {
    name: 'ticker'
    namespace: 'default-stepup'
  }
  spec: {
    type: 'bindings.cron'
    version: 'v1'
    metadata: [
      { name: 'schedule', value: '@every 5s' }
      { name: 'direction', value: 'input' }
    ]
  }
  scopes: [ 'simulator' ]
}

// ---------------------------------------------------------------------------
// Dapr pub/sub over the recipe — the same broker the
// Drasi PostDaprPubSub reaction publishes to, so the notifier sees those events.
// ---------------------------------------------------------------------------
resource pubsub 'dapr.io/Component@v1alpha1' = {
  metadata: {
    name: 'stepup-pubsub'
    namespace: 'default-stepup'
  }
  spec: {
    type: 'pubsub.redis'
    version: 'v1'
    metadata: [
      { name: 'redisHost', value: '${cache.properties.host}:${cache.properties.port}' }
      { name: 'redisPassword', value: '' }
    ]
  }
  scopes: [ 'notifier' ]
}

// ---------------------------------------------------------------------------
// Dapr HTTP output binding to the Discord webhook. URL read from the
// 'notifier-webhook' k8s secret (key 'url') via the portable 'stepup-secrets'
// Dapr secret store — secretstores.kubernetes locally, Key Vault on Azure.
// ---------------------------------------------------------------------------
resource discord 'dapr.io/Component@v1alpha1' = {
  metadata: {
    name: 'discord'
    namespace: 'default-stepup'
  }
  spec: {
    type: 'bindings.http'
    version: 'v1'
    metadata: [
      {
        name: 'url'
        secretKeyRef: {
          name: 'notifier-webhook'
          key: 'url'
        }
      }
    ]
  }
  auth: {
    secretStore: 'stepup-secrets'
  }
  scopes: [ 'notifier' ]
  dependsOn: [ secrets ] 
}

// Portable Dapr secret store. Local recipe = secretstores.kubernetes (reads the
// notifier-webhook k8s Secret); the Azure recipe swaps it for Key Vault. The
// recipe names the Dapr component after this resource ('stepup-secrets').
resource secrets 'Applications.Dapr/secretStores@2023-10-01-preview' = {
  name: 'stepup-secrets'
  properties: {
    environment: environment
    application: app.id
  }
}

// The Drasi PostDaprPubSub reaction publishes to the SAME broker + topic the
// notifier subscribes to. It gets its own stepup-pubsub component, pointed at
// the recipe's Redis by FQDN. Needs the drasi-system namespace to exist at deploy
// time — drasi init runs before rad deploy in every real flow; the CI smoke job
// creates an empty drasi-system namespace.
resource pubsubDrasi 'dapr.io/Component@v1alpha1' = {
  metadata: {
    name: 'stepup-pubsub'
    namespace: 'drasi-system'
  }
  spec: {
    type: 'pubsub.redis'
    version: 'v1'
    metadata: [
      { name: 'redisHost', value: '${cache.properties.host}:${cache.properties.port}' }
      { name: 'redisPassword', value: '' }
    ]
  }
}

// ---------------------------------------------------------------------------
// Notifier: subscribes to stepup-pubsub/stepup-events and posts contest
// notifications to Discord. Event-driven only (no Postgres connection).
// ---------------------------------------------------------------------------
resource notifier 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'notifier'
  properties: {
    application: app.id
    container: {
      image: '${imageRegistry}/notifier:${imageTag}'
      imagePullPolicy: 'IfNotPresent'
    }
    extensions: [
      {
        kind: 'daprSidecar'
        appId: 'notifier'
        appPort: 8080
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Clock: advances challenge_state.today on each /clock-cron call (accelerated
// mode by default, ~1 simulated day per tick). Writes to Postgres.
// ---------------------------------------------------------------------------
resource clock 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'clock'
  properties: {
    application: app.id
    container: {
      image: '${imageRegistry}/clock:${imageTag}'
      imagePullPolicy: 'IfNotPresent'
      env: {
        PG_DSN: {
          value: 'Host=${postgres.properties.host};Port=${postgres.properties.port};Username=postgres;Password=postgres;Database=${postgres.properties.database}'
        }
      }
    }
    extensions: [
      {
        kind: 'daprSidecar'
        appId: 'clock'
        appPort: 8080
      }
    ]
  }
}

// Dapr cron: posts to the clock's /clock-cron every 60s, advancing the day.
resource clockCron 'dapr.io/Component@v1alpha1' = {
  metadata: {
    name: 'clock-cron'
    namespace: 'default-stepup'
  }
  spec: {
    type: 'bindings.cron'
    version: 'v1'
    metadata: [
      { name: 'schedule', value: '@every 60s' }
      { name: 'direction', value: 'input' }
    ]
  }
  scopes: [ 'clock' ]
}

// ---------------------------------------------------------------------------
// Dashboard: static Vue app (nginx). No Dapr sidecar — it's a browser client
// that connects to the Drasi SignalR reaction hub via a relative `/hub` URL;
// nginx reverse-proxies /hub to dashboard-reaction-svc.drasi-system.svc.cluster.local:8080,
// so the browser reaches the hub through the dashboard (no `drasi tunnel` needed).
// ---------------------------------------------------------------------------
resource dashboard 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'dashboard'
  properties: {
    application: app.id
    container: {
      image: '${imageRegistry}/dashboard:${imageTag}'
      imagePullPolicy: 'IfNotPresent'
      ports: {
        web: {
          containerPort: 80
        }
      }
    }
  }
}
