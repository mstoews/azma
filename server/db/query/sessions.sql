-- name: CreateSession :one
INSERT INTO sessions (user_id, token_hash, expires_at, user_agent, ip)
VALUES (@user_id, @token_hash, @expires_at, @user_agent, @ip)
RETURNING *;

-- name: GetSessionUser :one
-- Resolves a live session to its user in one round trip. Revoked, expired and
-- disabled-user sessions are filtered out here rather than in Go.
SELECT sqlc.embed(s), sqlc.embed(u)
FROM sessions s
JOIN users u ON u.id = s.user_id
WHERE s.token_hash = @token_hash
  AND s.revoked_at IS NULL
  AND s.expires_at > now()
  AND NOT u.disabled;

-- name: TouchSession :exec
UPDATE sessions SET last_used_at = now() WHERE id = @id;

-- name: RevokeSession :exec
UPDATE sessions SET revoked_at = now() WHERE id = @id AND revoked_at IS NULL;

-- name: RevokeUserSessions :exec
UPDATE sessions SET revoked_at = now() WHERE user_id = @user_id AND revoked_at IS NULL;

-- name: DeleteExpiredSessions :exec
DELETE FROM sessions WHERE expires_at < now() - interval '7 days';

-- name: RevokeOtherUserSessions :exec
UPDATE sessions SET revoked_at = now()
WHERE user_id = @user_id AND id <> @keep_id AND revoked_at IS NULL;
