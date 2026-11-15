# AZMA & Associates — iOS

SwiftUI app for the firm's two audiences and its own consultants:

- **Business professionals** leave a resume with AZMA, keep a profile a
  consultant can read, and apply to the searches the firm is retained on.
- **Clients** describe a position, work with a consultant on the posting, and
  follow who has applied.
- **Consultants** review postings before they reach the board, read the
  candidates on file, and pick up consultation requests.

Anyone can read the firm's pages and the job board without an account.

## Running it

```sh
brew install xcodegen          # only to regenerate the project
cd ios && xcodegen generate    # after adding or removing files
open AzmaAssociates.xcodeproj
```

`project.yml` is the source of truth for the project; `AzmaAssociates.xcodeproj`
is generated from it. Requires Xcode 16 or newer; the app targets iOS 17.

### Pointing the app at a server

The API base URL is a build setting (`AZMA_API_BASE_URL` in `project.yml`),
surfaced to the app through `Info.plist`:

| Configuration | Server |
|---|---|
| Debug | the production Cloud Run service |
| Release | the production Cloud Run service |

For local development, launch with `-azma.apiBaseURL http://localhost:4200` (`npm start` in the repo root, which proxies `/api` and `/media` to the Go server on :8080 and serves the site's images).

A value in `UserDefaults` under `azma.apiBaseURL` wins over both, so a build can
be pointed elsewhere without rebuilding:

```sh
xcrun simctl launch booted com.azmaassociates.mobile -azma.apiBaseURL http://localhost:8080
```

Talking to the Go server directly on :8080 works for everything except the
site's photographs, which the Angular build serves — unless the server is
started with `STATIC_DIR` pointing at the repo's `public/` folder.

## Languages

The app ships in English and Japanese. iOS picks the phone's language, and
people can change it for this app alone under Settings → AZMA → Language.
All UI text lives in `AzmaAssociates/Resources/Localizable.xcstrings`; English
is the source language, so the keys are the English text.

- In SwiftUI, a literal passed to `Text`, `Button`, `Label` and the app's own
  components (`SectionHeader`, `FieldRow`, `EmptyStateView`, `Chip("…")`,
  `Notice(.info, "…")`) is localized automatically.
- Text built in plain Swift (model labels, validation and error messages) uses
  `String(localized: "…")`.
- Data shows as sent: use `Chip(text:)`, `Notice(kind:message:)` and
  `Text(verbatim:)` for it. Server values such as statuses, sectors and
  employment types are stored as codes or English names and translated for
  display (`JobStatus.label`, `Format.sector`, `Format.employmentType`).

Xcode adds new strings to the catalog when it builds. From the command line:

```sh
xcodebuild -scheme AzmaAssociates -sdk iphonesimulator -derivedDataPath build build
xcrun xcstringstool sync AzmaAssociates/Resources/Localizable.xcstrings \
  $(find build -path '*arm64/*.stringsdata' | sed 's/^/--stringsdata /')
```

Then translate the new entries in Xcode, or hand them to a translator with
`xcodebuild -exportLocalizations` / `-importLocalizations`. To check a screen
in Japanese without changing the simulator's language:

```sh
xcrun simctl launch booted com.azmaassociates.mobile -AppleLanguages "(ja)" -AppleLocale ja_JP
```

Content from the CMS (pages, consultant profiles) and error messages written
by the server are still English only.

## Tests

```sh
xcodebuild -scheme AzmaAssociates -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- `AzmaAssociatesTests` — the CMS HTML renderer, formatting, form validation,
  and the API client against a stubbed `URLProtocol`. No server needed.
- `AzmaAssociatesUITests` — four tours (public, candidate, client, consultant)
  against a local server on :8080. They **skip** when nothing answers there, so
  they are safe to run on a machine with only the app checked out. They expect
  the demo accounts below.

Demo accounts, if you want the tours to run (see `server/README.md` for the
stack, then register through the API):

| Role | Email | Password |
|---|---|---|
| Candidate | kenji.watanabe@example.com | `a long enough password` |
| Client | aiko.tanaka@nippon-asset.example | `a long enough password` |
| Consultant | consultant@azma-associates.com | created with `cmd/admin` |

## How it is put together

```
AzmaAssociates/
  App/        the shell: tabs, theme, shared components, form controls
  Core/       networking, session, stores, models, the CMS HTML renderer
  Features/   one folder per area of the app
```

- **No third-party dependencies.** URLSession, Codable and SwiftUI only.
- **`APIClient`** is the only place HTTP happens; `Endpoints.swift` is the
  complete list of routes the app calls. The bearer token lives in an actor
  inside the client, and in the keychain between launches.
- **`AppSession`** owns who is signed in. A 401 from anywhere signs the app out
  through `session.message(for:)`, which is also what turns a thrown error into
  the sentence shown to the person.
- **`SiteStore`** holds the firm's pages and consultants, from the single
  `/api/v1/site` response, cached on disk so the app opens with content.
- **`CandidateStore`** is shared between the job board and the candidate tab,
  because both need to know what has been saved and applied for.
- **`HTMLContent`** turns the CMS's WordPress-era HTML into blocks laid out with
  the app's own typography — there is no web view in the app.
- **Theme** carries the web site's look across: the firm's navy, a serif for
  headings (New York, standing in for the web's DM Serif Display), a paper
  ground, and a gold rule under section titles. Light and dark both supported.

## What a client can and cannot see

A client sees the professional summary of everyone who applies to their
position — current title and employer, years, location, the note the candidate
wrote — but not their name, contact details or resume. Those are released when
a consultant moves the application to **shortlisted**, which is the app's
version of presenting a shortlist. Only a consultant can make that move, and
only a consultant can open the document itself. The server enforces this; the
app shows it.

Confidential searches are the same idea in the other direction: the client's
name is replaced with "Confidential client" everywhere a candidate can see it.
