ALTER TABLE channel_invites
ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ NULL,
ADD COLUMN IF NOT EXISTS revoked_by UUID NULL REFERENCES users(id);

CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID NULL REFERENCES users(id),
    action TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
