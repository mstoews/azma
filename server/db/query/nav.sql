-- name: ListNavItems :many
SELECT n.id, n.label, n.page_id, n.href, n.sort_order,
       p.slug AS page_slug, p.published AS page_published
FROM nav_items n
LEFT JOIN pages p ON p.id = n.page_id
ORDER BY n.sort_order, n.id;

-- name: DeleteAllNavItems :exec
DELETE FROM nav_items;

-- name: CreateNavItem :one
INSERT INTO nav_items (label, page_id, href, sort_order)
VALUES (@label, sqlc.narg(page_id), sqlc.narg(href), @sort_order)
RETURNING *;

-- name: CountNavItems :one
SELECT count(*) FROM nav_items;
