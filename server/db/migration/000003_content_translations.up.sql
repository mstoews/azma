-- Translations of the public site's content.
--
-- English stays in the original tables and is the fallback for everything.
-- A translation row holds the text for one locale; any field left empty falls
-- back to English, so a page can go live in Japanese before every part of it
-- is translated. Images (hero, thumb, logo) are shared by all languages.
--
-- Locales are two-letter codes. Which ones the API accepts is decided in code
-- (api.supportedLocales), so adding a language needs no migration.

CREATE TABLE page_translations (
    page_id    bigint      NOT NULL REFERENCES pages (id) ON DELETE CASCADE,
    locale     text        NOT NULL CHECK (locale ~ '^[a-z]{2}$'),
    title      text        NOT NULL DEFAULT '',
    content    text        NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid        REFERENCES users (id) ON DELETE SET NULL,
    PRIMARY KEY (page_id, locale)
);

CREATE TABLE profile_translations (
    profile_id bigint      NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
    locale     text        NOT NULL CHECK (locale ~ '^[a-z]{2}$'),
    title      text        NOT NULL DEFAULT '',
    -- Card lines, as on profiles.excerpt. Empty means use the English lines.
    excerpt    text[]      NOT NULL DEFAULT '{}',
    content    text        NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid        REFERENCES users (id) ON DELETE SET NULL,
    PRIMARY KEY (profile_id, locale)
);

-- The menu is replaced as a whole, so its translations are too: they go with
-- their item.
CREATE TABLE nav_item_translations (
    nav_item_id bigint NOT NULL REFERENCES nav_items (id) ON DELETE CASCADE,
    locale      text   NOT NULL CHECK (locale ~ '^[a-z]{2}$'),
    label       text   NOT NULL,
    PRIMARY KEY (nav_item_id, locale)
);

CREATE TABLE site_settings_translations (
    locale           text        PRIMARY KEY CHECK (locale ~ '^[a-z]{2}$'),
    site_name        text        NOT NULL DEFAULT '',
    tagline          text        NOT NULL DEFAULT '',
    home_description text        NOT NULL DEFAULT '',
    updated_at       timestamptz NOT NULL DEFAULT now(),
    updated_by       uuid        REFERENCES users (id) ON DELETE SET NULL
);
