DROP TABLE IF EXISTS inquiries;
DROP TABLE IF EXISTS saved_jobs;
DROP TABLE IF EXISTS job_applications;
DROP TABLE IF EXISTS jobs;
DROP TABLE IF EXISTS employer_profiles;
DROP TABLE IF EXISTS candidate_profiles;
DROP TABLE IF EXISTS resumes;

-- Accounts that are no longer representable must go before the constraint is
-- narrowed back to administrators only.
DELETE FROM users WHERE role <> 'admin';
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('admin'));
