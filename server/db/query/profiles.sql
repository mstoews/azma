-- name: ListProfiles :many
SELECT * FROM profiles ORDER BY sort_order, id;

-- name: ListPublishedProfiles :many
SELECT * FROM profiles WHERE published ORDER BY sort_order, id;

-- name: GetProfile :one
SELECT * FROM profiles WHERE id = @id;

-- name: CreateProfile :one
INSERT INTO profiles (slug, title, excerpt, thumb, hero, content, published, sort_order, legacy_wp_id, updated_by)
VALUES (@slug, @title, @excerpt::text[], @thumb, @hero, @content, @published, @sort_order, sqlc.narg(legacy_wp_id), @updated_by)
RETURNING *;

-- name: UpdateProfile :one
UPDATE profiles
SET slug = @slug, title = @title, excerpt = @excerpt::text[], thumb = @thumb, hero = @hero, content = @content, published = @published, sort_order = @sort_order,
    updated_at = now(),
    updated_by = @updated_by
WHERE id = @id
RETURNING *;

-- name: DeleteProfile :exec
DELETE FROM profiles WHERE id = @id;

-- name: SetProfileSortOrder :exec
UPDATE profiles SET sort_order = @sort_order WHERE id = @id;

-- name: GetProfileByLegacyID :one
SELECT * FROM profiles WHERE legacy_wp_id = @legacy_wp_id;
