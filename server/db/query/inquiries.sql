-- name: CreateInquiry :one
INSERT INTO inquiries (user_id, kind, name, email, phone, company, office, message)
VALUES (@user_id, @kind, @name, @email, @phone, @company, @office, @message)
RETURNING *;

-- name: ListInquiries :many
SELECT sqlc.embed(i), COALESCE(u.email, '') AS account_email
FROM inquiries i
LEFT JOIN users u ON u.id = i.user_id
WHERE (@status::text = '' OR i.status = @status)
ORDER BY
    CASE WHEN i.status = 'new' THEN 0 ELSE 1 END,
    i.created_at DESC
LIMIT @lim OFFSET @off;

-- name: ListInquiriesForUser :many
SELECT * FROM inquiries WHERE user_id = @user_id ORDER BY created_at DESC;

-- name: SetInquiryStatus :one
UPDATE inquiries
SET status = @status,
    handled_by = @handled_by,
    handled_at = CASE WHEN @status::text = 'new' THEN NULL ELSE now() END
WHERE id = @id
RETURNING *;

-- name: CountInquiriesByStatus :many
SELECT status, count(*) AS total FROM inquiries GROUP BY status;

-- name: CountRecentInquiriesFromIP :one
-- Crude per-sender throttle for the public form; see also middleware.RateLimit.
SELECT count(*) FROM inquiries
WHERE email = @email AND created_at > now() - interval '1 hour';
