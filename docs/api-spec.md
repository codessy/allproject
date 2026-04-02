# API Specification

## REST Endpoints

### Auth

- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `GET /v1/me`

### Health

- `GET /healthz`
- `GET /healthz/push`
- `GET /healthz/diagnostics`

### Channels

- `GET /v1/channels`
- `POST /v1/channels`
- `GET /v1/channels/:id`
- `PATCH /v1/channels/:id`
- `POST /v1/channels/:id/join`
- `GET /v1/channels/:id/members`
- `PUT /v1/channels/:id/members/:userId`
- `DELETE /v1/channels/:id/members/:userId`
- `GET /v1/channels/:id/invites`
- `POST /v1/channels/:id/invites`
- `GET /v1/channels/:id/audit-events`

### Invites

- `POST /v1/invites/:token/accept`
- `POST /v1/channels/:id/invites/:inviteId/revoke`

## Create Channel Request

```json
{
  "name": "Team Room",
  "type": "private"
}
```

## Update Channel Request

```json
{
  "name": "Ops Room",
  "type": "private"
}
```

`name` is updatable by channel `owner` or `admin`. `type` is updatable only by channel `owner`.

## Update Channel Member Request

```json
{
  "role": "member"
}
```

Allowed membership roles: `owner`, `admin`, `member`.

Setting `role` to `owner` performs an ownership transfer: the target user becomes the primary channel owner and the previous owner is downgraded to `admin`.

## List Channel Members Response

```json
{
  "members": [
    {
      "channelId": "uuid",
      "userId": "uuid",
      "role": "member",
      "joinedAt": "2026-01-01T00:00:00Z"
    }
  ]
}
```

## Create Invite Response

```json
{
  "invite": {
    "id": "uuid",
    "channelId": "uuid",
    "expiresAt": "2026-01-01T00:00:00Z",
    "maxUses": 10,
    "revokedAt": null
  },
  "inviteToken": "opaque-token",
  "pushQueued": true
}
```

## Create Invite Request

```json
{
  "targetUserId": "uuid-optional",
  "maxUses": 10,
  "expiresInHours": 24
}
```

`targetUserId` is optional. When provided, the backend attempts to queue a push notification job for the target user's registered devices.

## Revoke Invite Response

```json
{
  "revoked": true,
  "invite": {
    "id": "uuid",
    "channelId": "uuid",
    "revokedAt": "2026-01-01T00:00:00Z",
    "revokedBy": "uuid"
  }
}
```

## List Invites Response

```json
{
  "invites": [
    {
      "id": "uuid",
      "channelId": "uuid",
      "createdBy": "uuid",
      "expiresAt": "2026-01-01T00:00:00Z",
      "maxUses": 10,
      "usedCount": 1,
      "createdAt": "2026-01-01T00:00:00Z",
      "revokedAt": null
    }
  ]
}
```

## List Audit Events Response

```json
{
  "events": [
    {
      "id": "uuid",
      "actorUserId": "uuid",
      "action": "invite.created",
      "resourceType": "channel_invite",
      "resourceId": "uuid",
      "metadata": {
        "channelId": "uuid",
        "maxUses": 10
      },
      "createdAt": "2026-01-01T00:00:00Z"
    }
  ]
}
```

`GET /v1/channels/:id/invites` and `GET /v1/channels/:id/audit-events` accept optional `limit` query parameter with range `1-200`.

Invite management permissions:

- `PATCH /v1/channels/:id` allows `name` updates for `owner/admin` and `type` updates only for `owner`
- `GET /v1/channels/:id/members` requires channel role `owner` or `admin`
- `PUT /v1/channels/:id/members/:userId` allows `owner` to assign `owner/admin/member`, while `admin` may assign only `member`
- `DELETE /v1/channels/:id/members/:userId` allows `owner` and `admin`, but `admin` may remove only `member`
- the last remaining `owner` cannot be removed
- assigning `owner` updates both membership role state and `channels.owner_user_id` atomically
- `POST /v1/channels/:id/invites` requires channel role `owner` or `admin`
- `GET /v1/channels/:id/invites` requires channel role `owner` or `admin`
- `POST /v1/channels/:id/invites/:inviteId/revoke` requires channel role `owner` or `admin`
- `GET /v1/channels/:id/audit-events` requires channel role `owner` or `admin`

## Push Health Response

```json
{
  "status": "ok",
  "pushObserved": true,
  "pushQueue": {
    "pendingDepth": 0,
    "processingDepth": 0,
    "deadLetterDepth": 0,
    "enqueuedTotal": 12,
    "successTotal": 11,
    "retryTotal": 2,
    "deadLetterTotal": 1,
    "recoveryTotal": 0,
    "failureTotal": 3,
    "maxAttempts": 5,
    "retryBaseMs": 500,
    "processingTimeoutSec": 30,
    "queueName": "push:invite:pending",
    "processingQueueName": "push:invite:pending:processing",
    "deadLetterQueueName": "push:invite:dead"
  }
}
```

## Diagnostics Health Response

```json
{
  "status": "ok",
  "dependencies": {
    "database": "ok",
    "redis": "ok"
  },
  "pushObserved": true,
  "pushQueue": {
    "pendingDepth": 0,
    "processingDepth": 0,
    "deadLetterDepth": 0
  }
}
```

### Devices

- `POST /v1/devices`

## Device Registration Request

```json
{
  "platform": "android",
  "pushToken": "push-token",
  "appVersion": "0.1.0"
}
```

## Join Channel Response

```json
{
  "channelId": "channel-1",
  "livekitUrl": "wss://livekit.example.com",
  "livekitToken": "livekit-room-jwt",
  "iceServers": [
    "stun:turn.example.com:3478",
    "turn:turn.example.com:3478?transport=udp",
    "turns:turn.example.com:5349?transport=tcp"
  ],
  "webSocketUrl": "wss://api.example.com/v1/ws",
  "activeSpeaker": "user-123"
}
```

## List Channels Response

```json
{
  "channels": [
    {
      "id": "uuid",
      "name": "Alpha",
      "type": "private",
      "ownerUserId": "uuid",
      "role": "admin",
      "createdAt": "2026-01-01T00:00:00Z"
    }
  ]
}
```

## WebSocket Events

### Client -> Server

- `channel.subscribe`
- `speaker.request`
- `speaker.renew`
- `speaker.release`
- `presence.ping`
- `session.resume`

### Server -> Client

- `channel.state`
- `speaker.granted`
- `speaker.denied`
- `speaker.changed`
- `participant.joined`
- `participant.left`
- `session.resync`
- `network.degraded`

## Example Speaker Request

```json
{
  "type": "speaker.request",
  "channelId": "channel-1"
}
```

## Example Speaker Granted

```json
{
  "type": "speaker.granted",
  "channelId": "channel-1",
  "grantedTo": "user-123",
  "leaseMs": 3000
}
```

## Speaker Lock Rules

- request is successful only if Redis `SET NX EX` succeeds
- lock renew must be sent every second while speaking
- lock expires automatically after 3 seconds without renew
- lock owner can release explicitly
- stale clients lose speaker status after timeout

## Register Request

```json
{
  "email": "user@example.com",
  "displayName": "User",
  "password": "password"
}
```

## Login Request

```json
{
  "email": "demo@example.com",
  "password": "password"
}
```

## Auth Response

```json
{
  "user": {
    "id": "uuid",
    "email": "demo@example.com",
    "displayName": "Demo User",
    "createdAt": "2026-01-01T00:00:00Z"
  },
  "accessToken": "jwt",
  "refreshToken": "opaque-token"
}
```

## Logout Request

```json
{
  "refreshToken": "opaque-token",
  "allDevices": false
}
```
