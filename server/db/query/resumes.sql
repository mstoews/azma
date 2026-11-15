-- name: CreateResume :one
INSERT INTO resumes (user_id, filename, storage_path, mime_type, size_bytes)
VALUES (@user_id, @filename, @storage_path, @mime_type, @size_bytes)
RETURNING *;

-- name: ListResumes :many
SELECT * FROM resumes WHERE user_id = @user_id ORDER BY created_at DESC, id DESC;

-- name: GetResume :one
SELECT * FROM resumes WHERE id = @id;

-- name: CountResumes :one
SELECT count(*) FROM resumes WHERE user_id = @user_id;

-- name: DeleteResume :one
-- Scoped to the owner: another user's id simply matches no row.
DELETE FROM resumes WHERE id = @id AND user_id = @user_id RETURNING *;
