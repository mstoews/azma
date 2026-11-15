-- name: CreateApplication :one
INSERT INTO job_applications (job_id, candidate_id, resume_id, cover_note)
VALUES (@job_id, @candidate_id, sqlc.narg(resume_id), @cover_note)
RETURNING *;

-- name: GetApplication :one
SELECT * FROM job_applications WHERE id = @id;

-- name: WithdrawApplication :one
UPDATE job_applications
SET status = 'withdrawn', updated_at = now()
WHERE id = @id AND candidate_id = @candidate_id AND status <> 'withdrawn'
RETURNING *;

-- name: SetApplicationStatus :one
UPDATE job_applications SET status = @status, updated_at = now()
WHERE id = @id
RETURNING *;

-- name: ListApplicationsForCandidate :many
SELECT sqlc.embed(a),
    j.title AS job_title,
    j.company AS job_company,
    j.confidential AS job_confidential,
    j.location AS job_location,
    j.status AS job_status,
    COALESCE(r.filename, '') AS resume_filename
FROM job_applications a
JOIN jobs j ON j.id = a.job_id
LEFT JOIN resumes r ON r.id = a.resume_id
WHERE a.candidate_id = @candidate_id
ORDER BY a.created_at DESC, a.id DESC;

-- name: ListApplicationsForJob :many
SELECT sqlc.embed(a),
    u.email AS candidate_email,
    COALESCE(cp.full_name, '') AS candidate_name,
    COALESCE(cp.headline, '') AS candidate_headline,
    COALESCE(cp.location, '') AS candidate_location,
    COALESCE(cp.current_employer, '') AS candidate_employer,
    COALESCE(cp.current_title, '') AS candidate_title,
    COALESCE(cp.years_experience, 0) AS candidate_years,
    COALESCE(r.filename, '') AS resume_filename
FROM job_applications a
JOIN users u ON u.id = a.candidate_id
LEFT JOIN candidate_profiles cp ON cp.user_id = a.candidate_id
LEFT JOIN resumes r ON r.id = a.resume_id
WHERE a.job_id = @job_id
ORDER BY a.created_at DESC, a.id DESC;

-- name: SaveJob :exec
INSERT INTO saved_jobs (candidate_id, job_id) VALUES (@candidate_id, @job_id)
ON CONFLICT DO NOTHING;

-- name: UnsaveJob :exec
DELETE FROM saved_jobs WHERE candidate_id = @candidate_id AND job_id = @job_id;

-- name: ListSavedJobs :many
SELECT sqlc.embed(j) FROM saved_jobs s
JOIN jobs j ON j.id = s.job_id
WHERE s.candidate_id = @candidate_id
ORDER BY s.created_at DESC;
