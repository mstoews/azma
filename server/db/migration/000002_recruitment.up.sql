-- AZMA & Associates recruitment: the entities the mobile app drives.
--
-- 000001 covers the public web site (pages, consultant profiles, media). This
-- migration adds the two sides of a search assignment: business professionals
-- who leave a resume with us, clients who ask us to fill a position, and the
-- consultation requests that start both conversations.

-- 000001 allowed administrators only. Candidates and employers sign in through
-- the same sessions table and are separated by role; only `admin` reaches
-- /api/v1/admin/*.
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('admin', 'candidate', 'employer'));

-- Resumes are confidential: unlike `media`, they are never served from a
-- public path. storage_path is a key in the same object store, under
-- resumes/, and the bytes come back only through an authenticated download.
CREATE TABLE resumes (
    id           bigserial   PRIMARY KEY,
    user_id      uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    filename     text        NOT NULL,
    storage_path text        NOT NULL,
    mime_type    text        NOT NULL DEFAULT '',
    size_bytes   bigint      NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX resumes_user_idx ON resumes (user_id, created_at DESC);

-- One row per candidate. Everything but the name is optional so a profile can
-- be saved early and filled in over time.
CREATE TABLE candidate_profiles (
    user_id            uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    full_name          text        NOT NULL DEFAULT '',
    headline           text        NOT NULL DEFAULT '',
    summary            text        NOT NULL DEFAULT '',
    location           text        NOT NULL DEFAULT '',
    phone              text        NOT NULL DEFAULT '',
    linkedin_url       text        NOT NULL DEFAULT '',
    current_employer   text        NOT NULL DEFAULT '',
    current_title      text        NOT NULL DEFAULT '',
    years_experience   integer     NOT NULL DEFAULT 0 CHECK (years_experience BETWEEN 0 AND 70),
    -- Sectors from the "Our Expertise" page; desired_roles is free text.
    sectors            text[]      NOT NULL DEFAULT '{}',
    desired_roles      text[]      NOT NULL DEFAULT '{}',
    languages          text[]      NOT NULL DEFAULT '{}',
    work_authorization text        NOT NULL DEFAULT '',
    salary_expectation text        NOT NULL DEFAULT '',
    -- False means "registered, but not in the market right now".
    open_to_offers     boolean     NOT NULL DEFAULT true,
    -- True once the candidate asks us to represent them, which is what makes
    -- the profile visible to consultants.
    submitted          boolean     NOT NULL DEFAULT false,
    submitted_at       timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX candidate_profiles_submitted_idx ON candidate_profiles (submitted, updated_at DESC);

-- One row per hiring client.
CREATE TABLE employer_profiles (
    user_id      uuid        PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    company      text        NOT NULL DEFAULT '',
    contact_name text        NOT NULL DEFAULT '',
    contact_role text        NOT NULL DEFAULT '',
    phone        text        NOT NULL DEFAULT '',
    website      text        NOT NULL DEFAULT '',
    location     text        NOT NULL DEFAULT '',
    about        text        NOT NULL DEFAULT '',
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);

-- A position an employer has asked us to fill. Postings are reviewed by a
-- consultant before they reach the public board, which is why `pending` is the
-- state a submitted job lands in.
CREATE TABLE jobs (
    id              bigserial   PRIMARY KEY,
    employer_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title           text        NOT NULL,
    company         text        NOT NULL DEFAULT '',
    -- Clients who do not want to be named on the board; consultants still see it.
    confidential    boolean     NOT NULL DEFAULT false,
    location        text        NOT NULL DEFAULT '',
    remote          boolean     NOT NULL DEFAULT false,
    sector          text        NOT NULL DEFAULT '',
    employment_type text        NOT NULL DEFAULT 'full_time'
        CHECK (employment_type IN ('full_time', 'contract', 'part_time', 'internship')),
    description     text        NOT NULL DEFAULT '',
    requirements    text        NOT NULL DEFAULT '',
    salary_min      integer     CHECK (salary_min IS NULL OR salary_min >= 0),
    salary_max      integer     CHECK (salary_max IS NULL OR salary_max >= 0),
    salary_currency text        NOT NULL DEFAULT '' CHECK (salary_currency IN ('', 'JPY', 'SGD', 'USD', 'EUR', 'GBP', 'HKD', 'AUD')),
    status          text        NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'pending', 'published', 'filled', 'closed', 'rejected')),
    -- A consultant's note back to the employer when a posting is rejected or
    -- needs work.
    review_note     text        NOT NULL DEFAULT '',
    reviewed_by     uuid        REFERENCES users (id) ON DELETE SET NULL,
    reviewed_at     timestamptz,
    published_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CHECK (salary_min IS NULL OR salary_max IS NULL OR salary_max >= salary_min)
);
CREATE INDEX jobs_employer_idx ON jobs (employer_id, created_at DESC);
CREATE INDEX jobs_board_idx ON jobs (status, published_at DESC);

CREATE TABLE job_applications (
    id           bigserial   PRIMARY KEY,
    job_id       bigint      NOT NULL REFERENCES jobs (id) ON DELETE CASCADE,
    candidate_id uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- Kept if the resume is deleted: the application still reads as submitted.
    resume_id    bigint      REFERENCES resumes (id) ON DELETE SET NULL,
    cover_note   text        NOT NULL DEFAULT '',
    status       text        NOT NULL DEFAULT 'submitted'
        CHECK (status IN ('submitted', 'under_review', 'shortlisted', 'interviewing', 'offer', 'placed', 'rejected', 'withdrawn')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (job_id, candidate_id)
);
CREATE INDEX job_applications_candidate_idx ON job_applications (candidate_id, created_at DESC);

CREATE TABLE saved_jobs (
    candidate_id uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    job_id       bigint      NOT NULL REFERENCES jobs (id) ON DELETE CASCADE,
    created_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (candidate_id, job_id)
);

-- "Please call me about hiring / about my career." Signed in or not: the web
-- site's Contact page is an email address, and this is its app equivalent.
CREATE TABLE inquiries (
    id         bigserial   PRIMARY KEY,
    user_id    uuid        REFERENCES users (id) ON DELETE SET NULL,
    kind       text        NOT NULL CHECK (kind IN ('hiring', 'career', 'general')),
    name       text        NOT NULL,
    email      text        NOT NULL,
    phone      text        NOT NULL DEFAULT '',
    company    text        NOT NULL DEFAULT '',
    -- Which office should pick this up.
    office     text        NOT NULL DEFAULT '' CHECK (office IN ('', 'tokyo', 'singapore')),
    message    text        NOT NULL,
    status     text        NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'in_progress', 'closed')),
    handled_by uuid        REFERENCES users (id) ON DELETE SET NULL,
    handled_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX inquiries_status_idx ON inquiries (status, created_at DESC);
