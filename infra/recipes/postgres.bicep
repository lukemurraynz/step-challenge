// Custom recipe for Applications.Core/extenders: StepUp Postgres with logical
// replication + init SQL + the drasi role. Pinned to Service `postgres` in
// namespace `default` so the Drasi source host stays postgres.default.svc.cluster.local.
// Publish: rad bicep publish --file infra/recipes/postgres.bicep \
//            --target br:ghcr.io/willvelida/stepup-recipes/postgres:latest
@description('Injected by Radius.')
#disable-next-line no-unused-params
param context object

extension kubernetes with {
  kubeConfig: ''
  namespace: 'default'
} as kubernetes

// Init SQL, verbatim from data/*.sql. Keys are numbered so Postgres runs them
// in order on first init: schema -> seed -> drasi role.
resource initdb 'core/ConfigMap@v1' = {
  metadata: {
    name: 'stepup-initdb'
    namespace: 'default'
  }
  data: {
    '01-schema.sql': '''
CREATE TABLE IF NOT EXISTS participants (
    id TEXT PRIMARY KEY CHECK (id ~ '^[a-z][a-z0-9-]{1,20}$'),
    name TEXT NOT NULL,
    team TEXT,
    target INTEGER NOT NULL,
    challenge BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS step_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    participant_id TEXT NOT NULL REFERENCES participants(id),
    steps INTEGER NOT NULL CHECK (steps >= 0),
    log_date DATE NOT NULL,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_step_logs_participant ON step_logs (participant_id);

CREATE TABLE IF NOT EXISTS daily_targets (
    day_number INTEGER PRIMARY KEY,
    date DATE NOT NULL UNIQUE,
    daily_target INTEGER NOT NULL CHECK (daily_target >= 0),
    cumulative_target INTEGER NOT NULL CHECK (cumulative_target >= 0)
);

CREATE TABLE IF NOT EXISTS challenge_state (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    today DATE NOT NULL,
    day_number INTEGER NOT NULL,
    daily_target INTEGER NOT NULL,
    cumulative_target INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS contest_state (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    participant_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'idle' CHECK (status IN ('idle', 'running', 'finished')),
    started_at TIMESTAMPTZ
);

-- REPLICA IDENTITY FULL makes Postgres include every column (not just the
-- primary key) in the logical-replication record for UPDATEs and DELETEs.
-- Drasi/Debezium requires non-null values for NOT NULL columns (e.g.
-- step_logs.log_date) on DELETE; without FULL, a delete sends nulls and the
-- source connector crashes. Every table the Drasi source reads needs this.
ALTER TABLE participants REPLICA IDENTITY FULL;
ALTER TABLE step_logs REPLICA IDENTITY FULL;
ALTER TABLE daily_targets REPLICA IDENTITY FULL;
ALTER TABLE challenge_state REPLICA IDENTITY FULL;
ALTER TABLE contest_state REPLICA IDENTITY FULL;
'''
    '02-seed.sql': '''
INSERT INTO daily_targets (day_number, date, daily_target, cumulative_target)
SELECT
    d AS day_number,
    DATE '2026-01-01' + (d - 1) AS date,
    10000 AS daily_target,
    10000 * d AS cumulative_target
FROM generate_series(1, 30) AS d
ON CONFLICT (day_number) DO UPDATE
    SET date = EXCLUDED.date,
        daily_target = EXCLUDED.daily_target,
        cumulative_target = EXCLUDED.cumulative_target;

INSERT INTO challenge_state (id, today, day_number, daily_target, cumulative_target)
SELECT TRUE, date, day_number, daily_target, cumulative_target
FROM daily_targets
WHERE day_number = 1
ON CONFLICT (id) DO UPDATE
    SET today = EXCLUDED.today,
        day_number = EXCLUDED.day_number,
        daily_target = EXCLUDED.daily_target,
        cumulative_target = EXCLUDED.cumulative_target;

INSERT INTO contest_state (id, participant_count, status, started_at)
VALUES (TRUE, 0, 'idle', NULL) ON CONFLICT (id) DO NOTHING;
'''
    '03-drasi.sql': '''
CREATE ROLE drasi WITH REPLICATION LOGIN SUPERUSER PASSWORD 'drasi';
'''
  }
}

// Persistent data so the replication slot survives pod restarts. Init scripts
// run only on first init -> `kubectl delete pvc postgres-data` to re-seed.
resource pgData 'core/PersistentVolumeClaim@v1' = {
  metadata: {
    name: 'postgres-data'
    namespace: 'default'
  }
  spec: {
    accessModes: [ 'ReadWriteOnce' ]
    resources: {
      requests: {
        storage: '1Gi'
      }
    }
  }
}

resource postgres 'apps/Deployment@v1' = {
  metadata: {
    name: 'postgres'
    namespace: 'default'
    labels: {
      app: 'postgres'
    }
  }
  spec: {
    replicas: 1
    selector: {
      matchLabels: {
        app: 'postgres'
      }
    }
    template: {
      metadata: {
        labels: {
          app: 'postgres'
        }
      }
      spec: {
        containers: [
          {
            name: 'postgres'
            image: 'postgres:16'
            args: [ '-c', 'wal_level=logical', '-c', 'max_replication_slots=10', '-c', 'max_wal_senders=10' ]
            env: [
              { name: 'POSTGRES_PASSWORD', value: 'postgres' }
              { name: 'POSTGRES_DB', value: 'stepup' }
              { name: 'PGDATA', value: '/var/lib/postgresql/data/pgdata' }
            ]
            ports: [
              { containerPort: 5432 }
            ]
            volumeMounts: [
              { name: 'initdb', mountPath: '/docker-entrypoint-initdb.d' }
              { name: 'data', mountPath: '/var/lib/postgresql/data' }
            ]
          }
        ]
        volumes: [
          {
            name: 'initdb'
            configMap: {
              name: 'stepup-initdb'
            }
          }
          {
            name: 'data'
            persistentVolumeClaim: {
              claimName: 'postgres-data'
            }
          }
        ]
      }
    }
  }
}

resource postgresSvc 'core/Service@v1' = {
  metadata: {
    name: 'postgres'
    namespace: 'default'
    labels: {
      app: 'postgres'
    }
  }
  spec: {
    selector: {
      app: 'postgres'
    }
    ports: [
      { port: 5432 }
    ]
  }
}

output result object = {
  // lets Radius track + clean up the k8s resources on delete
  resources: [
    '/planes/kubernetes/local/namespaces/${initdb.metadata.namespace}/providers/core/ConfigMap/${initdb.metadata.name}'
    '/planes/kubernetes/local/namespaces/${pgData.metadata.namespace}/providers/core/PersistentVolumeClaim/${pgData.metadata.name}'
    '/planes/kubernetes/local/namespaces/${postgres.metadata.namespace}/providers/apps/Deployment/${postgres.metadata.name}'
    '/planes/kubernetes/local/namespaces/${postgresSvc.metadata.namespace}/providers/core/Service/${postgresSvc.metadata.name}'
  ]
  values: {
    host: '${postgresSvc.metadata.name}.${postgresSvc.metadata.namespace}.svc.cluster.local'
    port: 5432
    database: 'stepup'
  }
}
