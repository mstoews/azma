-- name: ListMedia :many
SELECT * FROM media ORDER BY created_at DESC, id DESC;

-- name: GetMedia :one
SELECT * FROM media WHERE id = @id;

-- name: CreateMedia :one
INSERT INTO media (url, filename, storage_path, mime_type, size_bytes, width, height, alt, source, created_by)
VALUES (@url, @filename, sqlc.narg(storage_path), @mime_type, @size_bytes, sqlc.narg(width), sqlc.narg(height), @alt, @source, @created_by)
ON CONFLICT (url) DO NOTHING
RETURNING *;

-- name: UpdateMediaAlt :one
UPDATE media SET alt = @alt WHERE id = @id RETURNING *;

-- name: DeleteMedia :exec
DELETE FROM media WHERE id = @id;

-- name: CountMediaUsage :one
-- How many pages, profiles and settings reference a URL. Used to warn before
-- deleting a file that is still on the site.
SELECT (
    (SELECT count(*) FROM pages    p WHERE p.hero = @url::text OR strpos(p.content, @url::text) > 0) +
    (SELECT count(*) FROM profiles r WHERE r.hero = @url::text OR r.thumb = @url::text OR strpos(r.content, @url::text) > 0) +
    (SELECT count(*) FROM site_settings s WHERE s.logo = @url::text OR s.home_header_image = @url::text)
    )::int AS usage;
