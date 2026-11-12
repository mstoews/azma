-- AZMA & Associates CMS: initial schema.
--
-- gen_random_uuid() is built in from PostgreSQL 13, so no extension is needed.

CREATE TABLE users (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    email          text        NOT NULL,
    name           text        NOT NULL DEFAULT '',
    password_hash  text        NOT NULL,
    -- Only administrators exist today. The column is here so a narrower role
    -- (e.g. editor) can be added later without reshaping the table.
    role           text        NOT NULL DEFAULT 'admin' CHECK (role IN ('admin')),
    disabled       boolean     NOT NULL DEFAULT false,
    failed_logins  integer     NOT NULL DEFAULT 0,
    locked_until   timestamptz,
    last_login_at  timestamptz,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_key ON users (lower(email));

-- Opaque bearer sessions. Only the SHA-256 of the token is stored, so a
-- database leak does not leak usable tokens.
CREATE TABLE sessions (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    token_hash   bytea       NOT NULL UNIQUE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz NOT NULL,
    last_used_at timestamptz NOT NULL DEFAULT now(),
    revoked_at   timestamptz,
    user_agent   text        NOT NULL DEFAULT '',
    ip           text        NOT NULL DEFAULT ''
);
CREATE INDEX sessions_user_id_idx ON sessions (user_id);

-- Single-row table of site-wide settings.
CREATE TABLE site_settings (
    id                boolean     PRIMARY KEY DEFAULT true CHECK (id),
    site_name         text        NOT NULL DEFAULT '',
    tagline           text        NOT NULL DEFAULT '',
    home_description  text        NOT NULL DEFAULT '',
    home_header_image text        NOT NULL DEFAULT '',
    logo              text        NOT NULL DEFAULT '',
    updated_at        timestamptz NOT NULL DEFAULT now(),
    updated_by        uuid        REFERENCES users (id) ON DELETE SET NULL
);
INSERT INTO site_settings (id) VALUES (true);

CREATE TABLE pages (
    id           bigserial   PRIMARY KEY,
    slug         text        NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    title        text        NOT NULL,
    hero         text        NOT NULL DEFAULT '',
    content      text        NOT NULL DEFAULT '',
    published    boolean     NOT NULL DEFAULT false,
    sort_order   integer     NOT NULL DEFAULT 0,
    -- WordPress post ID, so old /?page_id=N links keep resolving.
    legacy_wp_id integer     UNIQUE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    updated_by   uuid        REFERENCES users (id) ON DELETE SET NULL
);

-- Team member profiles (WordPress "posts" on the original site).
CREATE TABLE profiles (
    id           bigserial   PRIMARY KEY,
    slug         text        NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    title        text        NOT NULL,
    -- Archive card lines: Japanese name, role, office.
    excerpt      text[]      NOT NULL DEFAULT '{}',
    thumb        text        NOT NULL DEFAULT '',
    hero         text        NOT NULL DEFAULT '',
    content      text        NOT NULL DEFAULT '',
    published    boolean     NOT NULL DEFAULT false,
    sort_order   integer     NOT NULL DEFAULT 0,
    legacy_wp_id integer     UNIQUE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    updated_by   uuid        REFERENCES users (id) ON DELETE SET NULL
);

-- Primary navigation. Each item points either at a page or at an external URL.
CREATE TABLE nav_items (
    id         bigserial PRIMARY KEY,
    label      text      NOT NULL,
    page_id    bigint    REFERENCES pages (id) ON DELETE CASCADE,
    href       text,
    sort_order integer   NOT NULL DEFAULT 0,
    CHECK ((page_id IS NULL) <> (href IS NULL))
);

CREATE TABLE media (
    id           bigserial   PRIMARY KEY,
    -- Public URL path, e.g. /media/2026/11/ab12cd-photo.jpg.
    url          text        NOT NULL UNIQUE,
    filename     text        NOT NULL,
    -- Path relative to MEDIA_DIR for uploads; NULL for files imported from the
    -- WordPress export, which ship inside the front-end build.
    storage_path text,
    mime_type    text        NOT NULL DEFAULT '',
    size_bytes   bigint      NOT NULL DEFAULT 0,
    width        integer,
    height       integer,
    alt          text        NOT NULL DEFAULT '',
    source       text        NOT NULL DEFAULT 'upload' CHECK (source IN ('upload', 'wordpress')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    created_by   uuid        REFERENCES users (id) ON DELETE SET NULL
);

-- Who changed what. `details` holds the before/after snapshot so a bad edit
-- can be recovered by hand.
CREATE TABLE audit_log (
    id         bigserial   PRIMARY KEY,
    user_id    uuid        REFERENCES users (id) ON DELETE SET NULL,
    user_email text        NOT NULL DEFAULT '',
    action     text        NOT NULL,
    entity     text        NOT NULL,
    entity_id  text        NOT NULL DEFAULT '',
    details    jsonb       NOT NULL DEFAULT '{}',
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_created_at_idx ON audit_log (created_at DESC);
