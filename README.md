# AzmaAssociates

This project was generated using [Angular CLI](https://github.com/angular/angular-cli) version 22.2.4.

## Running locally

Everything you need day to day is in the `Makefile`; run `make` to list it.
Locally, the API and the website run on your machine against the **Neon**
database, which holds UAT/test data (it is not the live site's data). Its
connection string is a secret in Google Secret Manager (project `web-azma`).

First time:

```bash
gcloud auth login      # an account that can read the project's secrets
make install           # npm + Go dependencies
make secrets           # copies the secrets into server/app.env (git-ignored)
```

Then, in two terminals:

```bash
make api               # API on http://localhost:8080
```

```bash
make web               # website on http://localhost:4200, admin at /admin
```

or `make dev` to run both in one terminal. Run `make secrets` again whenever
the secret changes; it only replaces the secret lines in `server/app.env`, so
your other local settings stay.

Other commands: `make admin EMAIL=… NAME="…"` (create or reset a CMS
administrator), `make media` (copy uploaded images from the bucket to
`server/media`, so they show locally), `make test`, `make build`.

To release to Cloud Run: if the release adds migrations, run `make migrate`
first (local and Cloud Run share the Neon database), then `make release`, which
builds the image in Cloud Build and deploys that build after asking you to
confirm. `make deploy TAG=<build-id>`
rolls back to an earlier build. See `server/README.md` → Deploying.

### Local database instead of Neon

With Docker running, you can work against a PostgreSQL container instead of
Neon. Set it up once:

```bash
make db-up                 # PostgreSQL 16 on localhost:55440
make migrate DB=local      # create the schema
make db-seed               # load the original site content
make admin DB=local EMAIL=you@example.com NAME="Your Name"
```

Then add `DB=local` to the usual commands, e.g. `make dev DB=local`. It
overrides `DB_SOURCE` without changing `server/app.env`, so leaving it off
goes back to Neon. `make db-down` stops the container (the data is kept),
`make db-reset` deletes the data, `make db-psql` opens a SQL shell, and
`make test-integration` runs the API integration tests against a scratch
`cms_test` database in the container.

Database migrations are not applied automatically (`AUTO_MIGRATE=false`,
locally and on Cloud Run). When a change adds a migration in
`server/db/migration`, run `make migrate`; `make migrate-status` shows the
current schema version. If the schema is behind, the API logs a warning at
startup.

## Development server

`make web` runs `ng serve`; `npm start` does the same.

Once the server is running, open your browser and navigate to `http://localhost:4200/`. The application will automatically reload whenever you modify any of the source files.

## Code scaffolding

Angular CLI includes powerful code scaffolding tools. To generate a new component, run:

```bash
ng generate component component-name
```

For a complete list of available schematics (such as `components`, `directives`, or `pipes`), run:

```bash
ng generate --help
```

## Building

To build the project run:

```bash
ng build
```

This will compile your project and store the build artifacts in the `dist/` directory. By default, the production build optimizes your application for performance and speed.

## Running unit tests

To execute unit tests with the [Vitest](https://vitest.dev/) test runner, use the following command:

```bash
ng test
```

## Running end-to-end tests

For end-to-end (e2e) testing, run:

```bash
ng e2e
```

Angular CLI does not come with an end-to-end testing framework by default. You can choose one that suits your needs.

## Additional Resources

For more information on using the Angular CLI, including detailed command references, visit the [Angular CLI Overview and Command Reference](https://angular.dev/tools/cli) page.
