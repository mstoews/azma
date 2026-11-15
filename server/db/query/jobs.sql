-- name: CreateJob :one
INSERT INTO jobs (
    employer_id, title, company, confidential, location, remote, sector,
    employment_type, description, requirements, salary_min, salary_max,
    salary_currency, status, published_at
) VALUES (
    @employer_id, @title, @company, @confidential, @location, @remote, @sector,
    @employment_type, @description, @requirements, sqlc.narg(salary_min), sqlc.narg(salary_max),
    @salary_currency, @status, CASE WHEN @status::text = 'published' THEN now() ELSE NULL END
)
RETURNING *;

-- name: UpdateJob :one
-- Scoped to the owner. A posting that was already live goes back to review
-- when it is edited, so a published job cannot be rewritten after approval.
UPDATE jobs SET
    title = @title, company = @company, confidential = @confidential,
    location = @location, remote = @remote, sector = @sector,
    employment_type = @employment_type, description = @description,
    requirements = @requirements, salary_min = sqlc.narg(salary_min),
    salary_max = sqlc.narg(salary_max), salary_currency = @salary_currency,
    status = @status,
    published_at = CASE WHEN @status::text = 'published' THEN published_at ELSE NULL END,
    review_note = CASE WHEN @status::text = 'pending' THEN '' ELSE review_note END,
    updated_at = now()
WHERE id = @id AND employer_id = @employer_id
RETURNING *;

-- name: SetJobStatus :one
-- A consultant's decision on a posting.
UPDATE jobs SET
    status = @status,
    review_note = @review_note,
    reviewed_by = @reviewed_by,
    reviewed_at = now(),
    published_at = CASE
        WHEN @status::text = 'published' AND published_at IS NULL THEN now()
        WHEN @status::text = 'published' THEN published_at
        ELSE published_at
    END,
    updated_at = now()
WHERE id = @id
RETURNING *;

-- name: DeleteJob :one
DELETE FROM jobs WHERE id = @id AND employer_id = @employer_id RETURNING *;

-- name: GetJob :one
SELECT * FROM jobs WHERE id = @id;

-- name: GetPublishedJob :one
SELECT * FROM jobs WHERE id = @id AND status = 'published';

-- name: ListJobsForEmployer :many
SELECT sqlc.embed(j),
    (SELECT count(*) FROM job_applications a WHERE a.job_id = j.id AND a.status <> 'withdrawn')::bigint AS application_count
FROM jobs j
WHERE j.employer_id = @employer_id
ORDER BY j.created_at DESC, j.id DESC;

-- name: ListPublishedJobs :many
-- The public board. Empty filter values mean "no filter", which keeps one
-- query (and one plan) for every combination the app sends.
SELECT * FROM jobs
WHERE status = 'published'
  AND (@sector::text = '' OR sector = @sector)
  AND (@employment_type::text = '' OR employment_type = @employment_type)
  AND (@remote_only::boolean = false OR remote)
  AND (
    @q::text = ''
    OR title ILIKE '%' || @q || '%'
    OR company ILIKE '%' || @q || '%'
    OR location ILIKE '%' || @q || '%'
    OR sector ILIKE '%' || @q || '%'
    OR description ILIKE '%' || @q || '%'
  )
ORDER BY published_at DESC NULLS LAST, id DESC
LIMIT @lim OFFSET @off;

-- name: CountPublishedJobs :one
SELECT count(*) FROM jobs
WHERE status = 'published'
  AND (@sector::text = '' OR sector = @sector)
  AND (@employment_type::text = '' OR employment_type = @employment_type)
  AND (@remote_only::boolean = false OR remote)
  AND (
    @q::text = ''
    OR title ILIKE '%' || @q || '%'
    OR company ILIKE '%' || @q || '%'
    OR location ILIKE '%' || @q || '%'
    OR sector ILIKE '%' || @q || '%'
    OR description ILIKE '%' || @q || '%'
  );

-- name: ListJobsForAdmin :many
SELECT sqlc.embed(j),
    u.email AS employer_email,
    COALESCE(ep.company, '') AS employer_company,
    (SELECT count(*) FROM job_applications a WHERE a.job_id = j.id AND a.status <> 'withdrawn')::bigint AS application_count
FROM jobs j
JOIN users u ON u.id = j.employer_id
LEFT JOIN employer_profiles ep ON ep.user_id = j.employer_id
WHERE (@status::text = '' OR j.status = @status)
ORDER BY
    CASE WHEN j.status = 'pending' THEN 0 ELSE 1 END,
    j.created_at DESC
LIMIT @lim OFFSET @off;

-- name: CountJobsByStatus :many
SELECT status, count(*) AS total FROM jobs GROUP BY status;

-- name: SetJobStatusForEmployer :one
-- The employer's own transitions: withdraw to a draft, resubmit for review,
-- or mark a live position filled or closed. published_at is kept for a
-- position that was live, so "filled" still shows when it ran.
UPDATE jobs SET
    status = @status,
    published_at = CASE WHEN @status::text IN ('filled', 'closed') THEN published_at ELSE NULL END,
    updated_at = now()
WHERE id = @id AND employer_id = @employer_id
RETURNING *;
