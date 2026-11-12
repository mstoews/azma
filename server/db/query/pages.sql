-- name: ListPages :many
SELECT * FROM pages ORDER BY sort_order, id;

-- name: ListPublishedPages :many
SELECT * FROM pages WHERE published ORDER BY sort_order, id;

-- name: GetPage :one
SELECT * FROM pages WHERE id = @id;

-- name: CreatePage :one
INSERT INTO pages (slug, title, hero, content, published, sort_order, legacy_wp_id, updated_by)
VALUES (@slug, @title, @hero, @content, @published, @sort_order, sqlc.narg(legacy_wp_id), @updated_by)
RETURNING *;

-- name: UpdatePage :one
UPDATE pages
SET slug = @slug, title = @title, hero = @hero, content = @content, published = @published, sort_order = @sort_order,
    updated_at = now(),
    updated_by = @updated_by
WHERE id = @id
RETURNING *;

-- name: DeletePage :exec
DELETE FROM pages WHERE id = @id;

-- name: SetPageSortOrder :exec
UPDATE pages SET sort_order = @sort_order WHERE id = @id;

-- name: GetPageByLegacyID :one
SELECT * FROM pages WHERE legacy_wp_id = @legacy_wp_id;
