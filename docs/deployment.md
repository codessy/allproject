# Deployment Plan

## Current Delivery Assets

- local Docker Compose stack for PostgreSQL, Redis, LiveKit, coturn, and API
- backend Docker image that includes SQL migrations at runtime
- GitHub Actions workflows for backend tests, mobile validation, and Docker build checks
- root `.env.example` for baseline backend configuration
- Redis-backed async push queue with configurable workers and queue key

## CI/CD Baseline

### GitHub Actions

- `backend-ci`: dependency restore, `go test ./...`, and API build validation
- `mobile-ci`: `flutter pub get`, `flutter analyze`, and `flutter test`
- `docker-ci`: backend image build and `docker compose config` validation

### Recommended Promotion Flow

1. Open feature branch and run the relevant GitHub Actions checks.
2. Merge into `main` only after backend, mobile, and Docker jobs pass.
3. Build and tag immutable backend container images per commit SHA.
4. Deploy first to staging and run smoke tests for auth, channel join, and WebSocket connectivity.
5. Promote the same image to production after staging verification.

## Local Deployment

From the repository root:

```bash
docker compose -f infra/docker-compose.yml up -d --build
```

Exposed local endpoints:

- API: `http://localhost:8080`
- PostgreSQL: `localhost:5432`
- Redis: `localhost:6379`
- LiveKit: `ws://localhost:7880`
- TURN: `localhost:3478` and `localhost:5349`

## Secrets and Configuration

- store JWT, LiveKit, database, and push credentials in a secret manager
- never commit production `.env` files
- separate values for local, staging, and production
- rotate `JWT_SECRET`, `LIVEKIT_API_SECRET`, and refresh token signing material on a planned schedule
- keep mobile app environment selection outside source control where possible
- for FCM, store `FCM_PROJECT_ID` and the full `FCM_CREDENTIALS_JSON` service account payload as secrets
- default to `PUSH_PROVIDER=noop` in environments where push credentials are not yet provisioned
- tune `PUSH_QUEUE_SIZE`, `PUSH_WORKERS`, and `PUSH_QUEUE_NAME` per environment to absorb short invite bursts without blocking API latency
- tune `PUSH_MAX_ATTEMPTS`, `PUSH_RETRY_BASE_MS`, `PUSH_PROCESSING_TIMEOUT_SEC`, and `PUSH_DLQ_NAME` for delivery reliability and operational recovery

## Recommended Cloud

Primary recommendation: AWS

- Compute: ECS or EKS
- Database: RDS PostgreSQL
- Redis: ElastiCache
- Load balancing: ALB and NLB
- Secrets: Secrets Manager
- Metrics and logs: CloudWatch, Prometheus, Grafana

Alternative options:

- GCP for strong networking and Kubernetes usage
- Hetzner plus Cloudflare for lower cost and higher ops involvement

## Environments

- local
- staging
- production

Staging should mirror production topology as closely as budget allows.

## Scaling Strategy

### API

- horizontally scale stateless API and WebSocket nodes
- keep session state in Redis
- run database migrations as part of deployment orchestration, not on every pod forever
- place API behind health-checked load balancing

### LiveKit

- room-aware scheduling
- assign each new room to the least-loaded node
- scale based on:
  - CPU
  - network throughput
  - packet loss
  - participant count

### TURN

- run at least two nodes
- use health-checked DNS or load balancing

## Operational Readiness Checklist

- add readiness and liveness probes for API, LiveKit, and TURN layers
- ship structured application logs to a centralized log platform
- create alerts for login failures, token refresh errors, Redis availability, packet loss, and room join failures
- add automated backups for PostgreSQL and retention policies for Redis-related recovery data where needed
- define incident runbooks for media degradation, region outage, and push delivery failure
- monitor pending, processing, and dead-letter queue depth in Redis
- alert on repeated push retry bursts and dead-letter growth
- poll `GET /healthz/push` from monitoring to expose queue counters without direct Redis inspection
- poll `GET /healthz/diagnostics` for one-shot API dependency status across PostgreSQL, Redis, and push instrumentation
- retain and review `audit_events` for invite creation, acceptance, and revocation investigations

## Cost Estimate

Approximate monthly range for 100 active channels and 5000 concurrent users:

- API and signaling: 300 to 700 USD
- PostgreSQL HA: 500 to 1500 USD
- Redis HA: 200 to 600 USD
- LiveKit nodes: 800 to 2500 USD
- coturn nodes: 150 to 400 USD
- monitoring and logs: 300 to 1200 USD
- egress bandwidth: 2000 to 8000+ USD

Estimated total:

- lean production: 4000 to 8000 USD
- safer enterprise setup: 8000 to 15000 USD

## Delivery Roadmap

1. Bootstrap repositories, CI, environments, monitoring
2. Implement auth and channel data model
3. Implement channel join and membership validation
4. Integrate LiveKit room tokens
5. Implement speaker lock with Redis
6. Add mobile reconnect logic
7. Add push notifications and deep links
8. Run load tests and packet loss simulations
9. Harden security and store compliance
10. Launch beta, observe, tune, then roll out gradually
