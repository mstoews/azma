-- name: CreateUser :one
INSERT INTO users (email, name, password_hash)
VALUES (@email, @name, @password_hash)
RETURNING *;

-- name: GetUserByEmail :one
SELECT * FROM users WHERE lower(email) = lower(@email);

-- name: GetUser :one
SELECT * FROM users WHERE id = @id;

-- name: ListUsers :many
SELECT * FROM users ORDER BY lower(email);

-- name: UpdateUser :one
UPDATE users
SET name = @name, disabled = @disabled, updated_at = now()
WHERE id = @id
RETURNING *;

-- name: SetUserPassword :exec
UPDATE users
SET password_hash = @password_hash, failed_logins = 0, locked_until = NULL, updated_at = now()
WHERE id = @id;

-- name: RecordLoginFailure :one
-- Increments the failure counter and, once it reaches the threshold, locks the
-- account until now() + window. Returns the new counter.
UPDATE users
SET failed_logins = failed_logins + 1,
    locked_until = CASE
        WHEN failed_logins + 1 >= @threshold::int THEN now() + make_interval(secs => @window_seconds::double precision)
        ELSE locked_until
    END
WHERE id = @id
RETURNING failed_logins;

-- name: RecordLoginSuccess :exec
UPDATE users
SET failed_logins = 0, locked_until = NULL, last_login_at = now()
WHERE id = @id;

-- name: DeleteUser :exec
DELETE FROM users WHERE id = @id;

-- name: CountActiveAdmins :one
SELECT count(*) FROM users WHERE role = 'admin' AND NOT disabled;
