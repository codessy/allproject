# PTT Quality Test Plan

This plan focuses on practical voice quality and reconnect behavior in real networks.

## Test matrix

- Network: Wi-Fi (good), Wi-Fi (packet loss), LTE/5G, network handover (Wi-Fi <-> LTE).
- Device roles: speaker + listener, multiple listeners.
- Session state: fresh join, reconnect after temporary disconnect, long-running session (10+ min).

## Measurements

- Time to speak:
  - press-to-grant latency (`request` -> `granted`).
- Speech continuity:
  - dropouts per minute.
- Reconnect behavior:
  - time from disconnect to `listening/speaking` restored.
- Error UX:
  - reconnect warning shown only when needed and cleared when recovered.

## Procedure

1. Start backend + LiveKit stack.
2. Join same channel from two devices.
3. Hold PTT in 10-second windows and rotate speaker/listener roles.
4. Introduce network impairment (toggle Wi-Fi, enable throttling/loss where possible).
5. Record:
   - app state labels
   - perceived audio quality
   - reconnect timing.

## Acceptance targets

- Press-to-grant: typically < 500 ms on local/stage networks.
- Reconnect recovery: < 5 s for transient outages.
- No app crash, no permanent stuck `reconnecting` without user signal.
- Clear user-facing status for permission-denied and reconnect-delay scenarios.
