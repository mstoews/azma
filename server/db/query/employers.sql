-- name: GetEmployerProfile :one
SELECT * FROM employer_profiles WHERE user_id = @user_id;

-- name: UpsertEmployerProfile :one
INSERT INTO employer_profiles (
    user_id, company, contact_name, contact_role, phone, website, location, about
) VALUES (
    @user_id, @company, @contact_name, @contact_role, @phone, @website, @location, @about
)
ON CONFLICT (user_id) DO UPDATE SET
    company = @company, contact_name = @contact_name, contact_role = @contact_role,
    phone = @phone, website = @website, location = @location, about = @about,
    updated_at = now()
RETURNING *;
