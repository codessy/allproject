# Repository Plan

## Top-Level Layout

- `backend/`: Go control-plane service
- `mobile/`: Flutter mobile application
- `infra/`: local infrastructure and future deployment files
- `docs/`: architecture, API, deployment, repository plan

## Backend Plan

- `cmd/api/`: process entrypoint
- `internal/config/`: environment loading
- `internal/auth/`: token validation and auth flows
- `internal/channel/`: speaker lock orchestration
- `internal/httpapi/`: router, middleware, WebSocket handlers
- `internal/models/`: domain models
- `migrations/`: PostgreSQL schema changes

## Mobile Plan

- `lib/src/features/auth/`
- `lib/src/features/channels/`
- `lib/src/features/ptt/`
- `lib/src/core/` for networking, websocket, webrtc, storage

## Recommended Next Implementation Order

1. Real JWT auth and refresh tokens
2. PostgreSQL repositories and SQL migrations runner
3. Real LiveKit token generation
4. Mobile API client and WebSocket service
5. flutter_webrtc or LiveKit client integration
6. Invite flow and push notifications
7. CI/CD and Kubernetes manifests
