# Backend

This service is the control plane for the walkie-talkie platform.

## Responsibilities

- auth register and login
- refresh token rotation and logout revoke
- channel listing
- channel join bootstrap
- invite creation, acceptance, and revocation
- channel invite and audit event read endpoints
- role-based invite management for channel owners and admins
- role-based channel metadata updates with owner-only type changes
- role-based channel membership administration with audit logging
- safe member removal with last-owner protection
- atomic ownership transfer that keeps `owner_user_id` aligned with membership roles
- WebSocket signaling
- Redis-based single-speaker arbitration
- PostgreSQL migrations on boot
- configurable push provider integration for channel invites
- audit event persistence for invite lifecycle actions

## Planned Next Steps

- add distributed broadcast via Redis pub/sub or NATS
- add persistent mobile session storage
- add end-to-end integration tests
- add retry backoff, dead-letter handling, and stale processing recovery for Redis push jobs

## Push Configuration

- `PUSH_PROVIDER=noop` disables delivery but keeps invite flow active
- `PUSH_PROVIDER=fcm` enables Firebase Cloud Messaging delivery
- `FCM_PROJECT_ID` must match the Firebase project
- `FCM_CREDENTIALS_JSON` must contain the full service-account JSON payload
- `PUSH_QUEUE_SIZE` controls Redis queue backpressure before enqueue rejection
- `PUSH_WORKERS` controls concurrent Redis queue consumers per API instance
- `PUSH_QUEUE_NAME` controls the Redis list key used for pending push jobs
- `PUSH_MAX_ATTEMPTS` controls how many delivery attempts are allowed before DLQ
- `PUSH_RETRY_BASE_MS` controls exponential retry backoff base duration
- `PUSH_PROCESSING_TIMEOUT_SEC` controls stale processing lease expiry
- `PUSH_DLQ_NAME` controls the Redis list key used for dead-lettered jobs

## Local Run

```bash
go mod tidy
go run ./cmd/api
```

## Docker Run

From the repository root:

```bash
docker compose -f infra/docker-compose.yml up -d api
```

## Local Smoke Test

From the repository root, once the API is reachable on `http://localhost:8080`:

```powershell
powershell -ExecutionPolicy Bypass -File .\infra\smoke-test.ps1
```

This validates the local happy path for:

- demo owner login
- invitee registration and login
- channel listing
- invite creation
- invite acceptance and membership verification
- invite revoke negative path
- member removal and post-removal visibility check

## Example Calls

Push queue health:

```bash
curl http://localhost:8080/healthz/push
```

Unified diagnostics:

```bash
curl http://localhost:8080/healthz/diagnostics
```

List channels:

```bash
curl -H "Authorization: Bearer <token>" http://localhost:8080/v1/channels
```

Join channel:

```bash
curl -X POST -H "Authorization: Bearer <token>" http://localhost:8080/v1/channels/alpha/join
```

Register:

```bash
curl -X POST http://localhost:8080/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","displayName":"User","password":"password"}'
```

Login:

```bash
curl -X POST http://localhost:8080/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"password"}'
```

WebSocket example:

Connect to:

```text
ws://localhost:8080/v1/ws?userId=user-1
```

Then send:

```json
{"type":"speaker.request","channelId":"alpha"}
```
