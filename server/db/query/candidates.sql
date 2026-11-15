-- name: GetCandidateProfile :one
SELECT * FROM candidate_profiles WHERE user_id = @user_id;

-- name: UpsertCandidateProfile :one
INSERT INTO candidate_profiles (
    user_id, full_name, headline, summary, location, phone, linkedin_url,
    current_employer, current_title, years_experience, sectors, desired_roles,
    languages, work_authorization, salary_expectation, open_to_offers
) VALUES (
    @user_id, @full_name, @headline, @summary, @location, @phone, @linkedin_url,
    @current_employer, @current_title, @years_experience, @sectors, @desired_roles,
    @languages, @work_authorization, @salary_expectation, @open_to_offers
)
ON CONFLICT (user_id) DO UPDATE SET
    full_name = @full_name, headline = @headline, summary = @summary,
    location = @location, phone = @phone, linkedin_url = @linkedin_url,
    current_employer = @current_employer, current_title = @current_title,
    years_experience = @years_experience, sectors = @sectors,
    desired_roles = @desired_roles, languages = @languages,
    work_authorization = @work_authorization, salary_expectation = @salary_expectation,
    open_to_offers = @open_to_offers, updated_at = now()
RETURNING *;

-- name: SubmitCandidateProfile :one
-- Asking us to represent them. submitted_at keeps the first submission date.
UPDATE candidate_profiles
SET submitted = @submitted,
    submitted_at = CASE WHEN @submitted::boolean AND submitted_at IS NULL THEN now() ELSE submitted_at END,
    updated_at = now()
WHERE user_id = @user_id
RETURNING *;

-- name: ListCandidatesForAdmin :many
SELECT sqlc.embed(cp),
    u.email,
    (SELECT count(*) FROM resumes r WHERE r.user_id = cp.user_id)::bigint AS resume_count,
    COALESCE((SELECT r.id FROM resumes r WHERE r.user_id = cp.user_id ORDER BY r.created_at DESC LIMIT 1), 0)::bigint AS latest_resume_id,
    COALESCE((SELECT r.filename FROM resumes r WHERE r.user_id = cp.user_id ORDER BY r.created_at DESC LIMIT 1), '')::text AS latest_resume_filename,
    (SELECT count(*) FROM job_applications a WHERE a.candidate_id = cp.user_id)::bigint AS application_count
FROM candidate_profiles cp
JOIN users u ON u.id = cp.user_id
WHERE (@submitted_only::boolean = false OR cp.submitted)
  AND (
    @q::text = ''
    OR cp.full_name ILIKE '%' || @q || '%'
    OR cp.headline ILIKE '%' || @q || '%'
    OR cp.current_employer ILIKE '%' || @q || '%'
    OR u.email ILIKE '%' || @q || '%'
  )
ORDER BY cp.submitted DESC, cp.updated_at DESC
LIMIT @lim OFFSET @off;

-- name: GetCandidateForAdmin :one
SELECT sqlc.embed(cp), u.email
FROM candidate_profiles cp
JOIN users u ON u.id = cp.user_id
WHERE cp.user_id = @user_id;
