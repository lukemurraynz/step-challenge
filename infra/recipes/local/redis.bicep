// Local recipe for Applications.Datastores/redisCaches: a Redis container in the
// app namespace. Mirrors the Radius local-dev pack recipe but ALSO outputs `tls`
// plus an (empty) password/connectionString, so it shares one output contract with
// infra/recipes/azure/redis.bicep — letting a single app.bicep read
// cache.properties.tls + cache.listSecrets().password on BOTH environments.
// Publish: rad bicep publish --file infra/recipes/local/redis.bicep \
//            --target br:ghcr.io/willvelida/stepup-recipes/redis:latest
@description('Injected by Radius: the calling resource + environment context.')
param context object

extension kubernetes with {
  kubeConfig: ''
  namespace: context.runtime.kubernetes.namespace
} as kubernetes

resource redis 'apps/Deployment@v1' = {
  metadata: {
    name: 'redis-${uniqueString(context.resource.id)}'
  }
  spec: {
    selector: {
      matchLabels: {
        app: 'redis'
        resource: context.resource.name
      }
    }
    template: {
      metadata: {
        labels: {
          app: 'redis'
          resource: context.resource.name
          'radapp.io/application': context.application == null ? '' : context.application.name
        }
      }
      spec: {
        containers: [
          {
            name: 'redis'
            image: 'redis:7-alpine'
            ports: [
              { containerPort: 6379 }
            ]
          }
        ]
      }
    }
  }
}

resource svc 'core/Service@v1' = {
  metadata: {
    name: 'redis-${uniqueString(context.resource.id)}'
  }
  spec: {
    type: 'ClusterIP'
    selector: {
      app: 'redis'
      resource: context.resource.name
    }
    ports: [
      { port: 6379 }
    ]
  }
}

output result object = {
  // Lets Radius clean up the k8s resources on delete (the DE omits them otherwise).
  resources: [
    '/planes/kubernetes/local/namespaces/${svc.metadata.namespace}/providers/core/Service/${svc.metadata.name}'
    '/planes/kubernetes/local/namespaces/${redis.metadata.namespace}/providers/apps/Deployment/${redis.metadata.name}'
  ]
  values: {
    host: '${svc.metadata.name}.${svc.metadata.namespace}.svc.cluster.local'
    port: 6379
    tls: false
  }
  secrets: {
    password: ''
    connectionString: '${svc.metadata.name}.${svc.metadata.namespace}.svc.cluster.local:6379'
  }
}
