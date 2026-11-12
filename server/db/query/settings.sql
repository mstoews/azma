-- name: GetSettings :one
SELECT * FROM site_settings WHERE id;

-- name: UpdateSettings :one
UPDATE site_settings
SET site_name = @site_name,
    tagline = @tagline,
    home_description = @home_description,
    home_header_image = @home_header_image,
    logo = @logo,
    updated_at = now(),
    updated_by = @updated_by
WHERE id
RETURNING *;
