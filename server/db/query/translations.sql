-- ---- pages ----------------------------------------------------------------

-- name: ListPageTranslations :many
SELECT * FROM page_translations ORDER BY page_id, locale;

-- name: ListPageTranslationsByLocale :many
SELECT * FROM page_translations WHERE locale = @locale;

-- name: ListPageTranslationsForPage :many
SELECT * FROM page_translations WHERE page_id = @page_id ORDER BY locale;

-- name: UpsertPageTranslation :exec
INSERT INTO page_translations (page_id, locale, title, content, updated_by)
VALUES (@page_id, @locale, @title, @content, @updated_by)
ON CONFLICT (page_id, locale) DO UPDATE
SET title = EXCLUDED.title, content = EXCLUDED.content, updated_at = now(), updated_by = EXCLUDED.updated_by;

-- name: DeletePageTranslation :exec
DELETE FROM page_translations WHERE page_id = @page_id AND locale = @locale;

-- ---- profiles -------------------------------------------------------------

-- name: ListProfileTranslations :many
SELECT * FROM profile_translations ORDER BY profile_id, locale;

-- name: ListProfileTranslationsByLocale :many
SELECT * FROM profile_translations WHERE locale = @locale;

-- name: ListProfileTranslationsForProfile :many
SELECT * FROM profile_translations WHERE profile_id = @profile_id ORDER BY locale;

-- name: UpsertProfileTranslation :exec
INSERT INTO profile_translations (profile_id, locale, title, excerpt, content, updated_by)
VALUES (@profile_id, @locale, @title, @excerpt::text[], @content, @updated_by)
ON CONFLICT (profile_id, locale) DO UPDATE
SET title = EXCLUDED.title, excerpt = EXCLUDED.excerpt, content = EXCLUDED.content,
    updated_at = now(), updated_by = EXCLUDED.updated_by;

-- name: DeleteProfileTranslation :exec
DELETE FROM profile_translations WHERE profile_id = @profile_id AND locale = @locale;

-- ---- navigation -----------------------------------------------------------

-- name: ListNavItemTranslations :many
SELECT * FROM nav_item_translations ORDER BY nav_item_id, locale;

-- name: CreateNavItemTranslation :exec
INSERT INTO nav_item_translations (nav_item_id, locale, label) VALUES (@nav_item_id, @locale, @label);

-- ---- settings -------------------------------------------------------------

-- name: ListSettingsTranslations :many
SELECT * FROM site_settings_translations ORDER BY locale;

-- name: UpsertSettingsTranslation :exec
INSERT INTO site_settings_translations (locale, site_name, tagline, home_description, updated_by)
VALUES (@locale, @site_name, @tagline, @home_description, @updated_by)
ON CONFLICT (locale) DO UPDATE
SET site_name = EXCLUDED.site_name, tagline = EXCLUDED.tagline, home_description = EXCLUDED.home_description,
    updated_at = now(), updated_by = EXCLUDED.updated_by;

-- name: DeleteSettingsTranslation :exec
DELETE FROM site_settings_translations WHERE locale = @locale;

-- name: SetPageTranslationContent :exec
UPDATE page_translations SET content = @content WHERE page_id = @page_id AND locale = @locale;

-- name: SetProfileTranslationContent :exec
UPDATE profile_translations SET content = @content WHERE profile_id = @profile_id AND locale = @locale;
