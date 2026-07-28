# eEarly EHR Module OpenSource

This repository contains the deployment configuration for the EHRbase-based clinical
data store used by eEarly: Docker Compose orchestration, environment configuration,
and the Keycloak realm used for OAuth2 authentication.

## 1. EHRbase endpoints in use

eEarly's backend talks to EHRbase exclusively through a single client class. The
endpoints below are the full API surface that a replacement storage layer needs to
support:

| Method | Path                          | Purpose                                                                 |
|--------|-------------------------------|--------------------------------------------------------------------------|
| `PUT`  | `/ehr/{ehrId}`                | Create a new EHR record                                                  |
| `GET`  | `/ehr/{ehrId}`                | Check whether an EHR exists (200 vs. 404)                                |
| `POST` | `/ehr/{ehrId}/composition`    | Store a composition (contribution)                                       |
| `POST` | `/query/aql`                  | Run AQL queries to fetch measurements, paginated via `fetch`/`offset`    |

All requests carry `Authorization: Bearer <token>`, obtained via an OAuth2
client-credentials grant against the Keycloak realm in this repo (see
[`realm-config/eearly-ehrbase-realm.json`](realm-config/eearly-ehrbase-realm.json),
client `ehrbase`).

The AQL queries used against `/query/aql` select observation data
(`archetype_node_id`, event value/units/magnitude, timestamps, device id) via
`EHR CONTAINS COMPOSITION CONTAINS OBSERVATION`, filtered by `ehr_id`, optional time
range, and optional `archetype_node_id` matches. A compatible storage layer needs to
support this query shape for `/query/aql` to be a drop-in replacement. Full request/
response semantics for all endpoints follow the standard openEHR ITS-REST
specification: https://specifications.openehr.org/releases/ITS-REST/Release-1.1.0

## 2. EHRbase source and version

We run the official, unmodified EHRbase image — no custom fork or patches. Pulling
the matching upstream revision:

- Project: https://github.com/ehrbase/ehrbase
- Version running in this environment: **2.34.0** (see `eearly-ehr-service` in
  [`docker-compose.yaml`](docker-compose.yaml))

## 3. Environment setup — step by step

Prerequisites: Docker and Docker Compose.

1. Clone this repository.
2. Review [`.env`](.env) and replace the placeholder values with your own
   credentials — **the values checked into this repo are placeholders only and
   must not be reused as-is.**
3. Start the stack:
   ```bash
   docker compose up -d
   ```
   This brings up five services: a Postgres database for Keycloak
   (`eearly-ehr-keycloak-db`), Keycloak itself (`eearly-ehr-keycloak`), a Postgres
   database for EHRbase (`eearly-ehr-db`, using the `ehrbase/ehrbase-v2-postgres`
   image), EHRbase itself (`eearly-ehr-service`), and `eearly-ehr-template-loader`,
   which uploads every template in [`templates/`](templates) to EHRbase once it's
   healthy, then exits.
4. On startup, Keycloak automatically imports the realm from
   [`realm-config/eearly-ehrbase-realm.json`](realm-config/eearly-ehrbase-realm.json)
   (mounted read-only, `command: ["start", "--import-realm"]`).
5. Once healthy:
   - EHRbase REST API: `http://localhost:8000/ehrbase/rest/...`
     (status check: `http://localhost:8000/ehrbase/rest/status`)
   - Keycloak: `http://localhost:9092` (admin), management/health endpoints on
     `9012`
   - EHRbase management endpoints (`/management/health`, `/management/info`,
     `/management/metrics`, `/management/prometheus`) are exposed read-only.
6. EHRbase is configured for OAuth2 authentication against the Keycloak realm
   (`SECURITY_OAUTH2USERROLE=USER`, `SECURITY_OAUTH2ADMINROLE=ADMIN`), with a basic
   auth fallback controlled by the `security_auth_*` variables in `.env`.

## 4. Dependencies

- **EHRbase** `2.34.0` — https://github.com/ehrbase/ehrbase (image:
  `ehrbase/ehrbase:2.34.0`)
- **EHRbase Postgres image** `16.2` — image: `ehrbase/ehrbase-v2-postgres:16.2`
- **Keycloak** `26.5.1` — https://www.keycloak.org/ / https://github.com/keycloak/keycloak
  (image: `keycloak/keycloak:26.5.1`)
- **PostgreSQL** `17` (Keycloak's own database) — image: `postgres:17`

No additional services (reverse proxy, message broker, etc.) are required to run
this environment standalone.

## 5. Configuration files

All configuration needed to reproduce the environment is in this repository:

- [`docker-compose.yaml`](docker-compose.yaml) — orchestrates all four services,
  networking, volumes, and health checks.
- [`.env`](.env) — environment variables consumed by `docker-compose.yaml`
  (database credentials, Keycloak admin credentials, EHRbase basic-auth
  credentials). Values are placeholders and must be rotated before any
  non-local use.
- [`realm-config/eearly-ehrbase-realm.json`](realm-config/eearly-ehrbase-realm.json)
  — Keycloak realm export, auto-imported on container startup. **This export
  currently contains a live client secret for the `ehrbase` client rather than a
  placeholder.** Rotate that secret in Keycloak and scrub it from the export
  before deploying this realm anywhere beyond local development.

## 6. Templates

[`templates/`](templates) contains the seven openEHR templates (`.opt` files) that
define eEarly's clinical data structures — one per measurement type (blood
pressure, blood glucose, body weight, body height, pulse, pulse oximetry, body
temperature). These templates are the only customization on top of stock
EHRbase; everything else in this environment is official, unmodified EHRbase
configuration (see [section 2](#2-ehrbase-source-and-version)).

They're loaded automatically: the `eearly-ehr-template-loader` service
([`template-loader/loader.sh`](template-loader/loader.sh)) waits for EHRbase to
become healthy, then `POST`s each template to
`/definition/template/adl1.4` and exits — no manual step required after
`docker compose up -d`. Re-running the stack is safe; templates that already
exist are skipped (EHRbase returns `409`).