# WalkieTalkie Platform

Production-oriented monorepo blueprint for a cross-platform walkie-talkie application.

## Stack

- Mobile: Flutter + WebRTC
- Backend: Go + Gin + WebSocket
- Database: PostgreSQL
- Coordination: Redis
- SFU: LiveKit
- TURN: coturn
- Push: FCM + APNs

## Repository Layout

- `docs/architecture.md`: full system architecture
- `docs/api-spec.md`: REST and WebSocket contracts
- `docs/deployment.md`: infrastructure, scaling, cost, operations
- `docs/repository-plan.md`: file and module responsibilities
- `backend/`: Go API and signaling service starter
- `mobile/`: Flutter mobile application starter
- `mobile/docs/native-push-setup.md`: Android/iOS Firebase push setup checklist
- `infra/docker-compose.yml`: local development stack

## What is included

- Production-ready architecture and implementation plan
- Backend service skeleton for channel join and PTT lock flow
- PostgreSQL-backed user and channel repositories
- automatic SQL migrations on backend boot
- Redis-based single-speaker lock design
- LiveKit room token generation for join bootstrap
- PostgreSQL initial migration
- Flutter client module scaffold for auth, channels, and PTT
- Mobile API, WebSocket, and PTT controller foundation
- Realtime speaker event broadcasting across channel subscribers
- Preliminary mobile LiveKit room connection support
- Invite acceptance UI and backend push abstraction foundation
- Startup invite handoff flow and push provider-ready domain model
- Persisted mobile auth session restore with refresh-token-based bootstrap
- Automatic mobile `401` refresh, retry, and login fallback handling
- Native mobile push bootstrap and invite-open routing foundation
- Mobile channel administration UI for role, membership, and invite management
- Mobile owner-facing admin polish for invite copy and audit visibility
- Backend-to-mobile channel role exposure for correct admin/owner UI gating
- Final mobile admin UX polish for confirmations and readable audit history
- Safer destructive admin flows with confirmation prompts and formatted timestamps
- Local infrastructure stack for PostgreSQL, Redis, LiveKit, and coturn
- Dockerized backend runtime with migrations included in the image
- GitHub Actions workflows for backend, mobile, and Docker validation

## What is not fully implemented yet

- Real Flutter networking and WebRTC integration
- Push notifications
- Kubernetes manifests / Helm charts

These areas are documented so a professional team can continue implementation from a clean base.

## Quick Start

1. Install Go 1.23+
2. Install Docker and Docker Compose
3. On fresh Windows setups, Docker Desktop may require `WSL` installation and a full system reboot before the Linux engine becomes healthy
4. Copy environment variables from `.env.example` once created for your environment
5. Start the full local stack:

```bash
docker compose -f infra/docker-compose.yml up -d
```

6. Backend is available at `http://localhost:8080` once the compose stack is healthy.

7. If you want to run backend outside Docker instead:

```bash
cd backend
go mod tidy
go run ./cmd/api
```

8. Run the local API smoke test:

```powershell
powershell -ExecutionPolicy Bypass -File .\infra\smoke-test.ps1
```

The smoke script now checks:

- demo owner login
- invitee register/login
- channel list
- invite create and accept
- invite revoke negative case
- member removal visibility enforcement

## CI

- `backend-ci`: runs `go test ./...` and builds the API binary
- `mobile-ci`: runs `flutter analyze` and `flutter test`
- `docker-ci`: builds the backend container image and validates compose config

## Delivery Notes

This repository is structured as a serious implementation starter. The docs define the target production system and the code provides a backend foundation plus a mobile app shell that a professional team can extend safely.
