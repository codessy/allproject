# Architecture

## Recommended Production Stack

- Mobile client: Flutter + `flutter_webrtc`
- Control plane: Go + Gin + Gorilla WebSocket
- Data plane: LiveKit SFU
- Database: PostgreSQL
- Distributed coordination: Redis
- NAT traversal: coturn
- Push: Firebase Cloud Messaging and Apple Push Notification service

## High-Level Diagram

```text
Mobile App
  -> API Gateway / Load Balancer
  -> Go Backend (REST + WebSocket signaling)
  -> Redis (speaker lock, presence, reconnect state)
  -> PostgreSQL (users, channels, memberships, invites, devices)
  -> LiveKit SFU Cluster (audio forwarding)
  -> coturn (STUN/TURN fallback)
  -> FCM / APNs (notifications)
```

## Core Design Decisions

### 1. Control plane and media plane are separate

- Backend owns authentication, authorization, channel state, invite links, and speaker arbitration.
- LiveKit only handles low-latency media forwarding.

### 2. One active speaker per channel

- Users join a channel as listeners.
- Speaking requires acquiring a distributed lock in Redis.
- Only the lock holder gets permission to publish audio.

### 3. Redis lock with TTL

- Key format: `channel:{channelId}:speaker_lock`
- Value: `{userId}:{sessionId}`
- TTL: 3 seconds
- Client renews lock every 1 second while the PTT button is held.

This allows quick recovery if a speaker disconnects unexpectedly.

### 4. Room pinning

- One app channel maps to one LiveKit room.
- All room participants stay on the same SFU node.
- New rooms are assigned to the least-loaded SFU node.

## Logical Components

### Mobile

- Authentication UI
- Channel list and membership flows
- Invite acceptance deep link flow
- PTT button state machine
- LiveKit room connection
- Reconnect logic

### Backend

- Auth service
- Channel service
- Invite service
- Session service
- WebSocket gateway
- Push service

### Infrastructure

- PostgreSQL primary + replica
- Redis primary + replica
- LiveKit cluster
- coturn pair
- Metrics, logs, tracing

## Scale Target

Designed for:

- 100 active channels
- 5000 concurrent users
- audio-only Opus at 64 kbps
- one speaker per room
- sub-300 ms target latency

## Production Node Recommendation

### API Nodes

- 3 nodes
- 4 vCPU
- 8 GB RAM

### PostgreSQL

- 1 primary + 1 standby
- 8 vCPU
- 32 GB RAM

### Redis

- 1 primary + 1 replica
- 2 to 4 vCPU
- 8 GB RAM

### LiveKit

- Start with 4 nodes
- 8 vCPU
- 16 GB RAM
- 1 Gbps network

### coturn

- 2 nodes
- 4 vCPU
- 8 GB RAM

## Reliability

- WebSocket reconnect with exponential backoff
- LiveKit reconnect and ICE restart
- Speaker lock auto-expiry
- Session warm resume window of 10 to 15 seconds
- Presence timeout cleanup after 15 seconds

## Security

- JWT access tokens
- refresh token rotation
- invite links with signed, hashed, expiring tokens
- DTLS-SRTP media encryption
- rate limiting on auth and speaker requests
- secrets in a managed secret store

## App Store and Play Store Considerations

- microphone permission must be explained clearly
- background audio use must be explicitly justified
- privacy policy must disclose audio handling
- no hidden recording behavior
