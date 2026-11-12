-- name: InsertAudit :exec
INSERT INTO audit_log (user_id, user_email, action, entity, entity_id, details)
VALUES (@user_id, @user_email, @action, @entity, @entity_id, @details);

-- name: ListAudit :many
SELECT * FROM audit_log
ORDER BY created_at DESC, id DESC
LIMIT @lim OFFSET @off;
