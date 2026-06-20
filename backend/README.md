# EACC Chat Backend

Trusted NestJS API for LMS authentication, PostgreSQL identity and membership
data, Firebase custom tokens, Firestore authorization projections, and push
notification registration.

The implementation follows
[`docs/production_architecture.md`](../docs/production_architecture.md).

## Requirements

- Node.js 22 or newer
- PostgreSQL

## Setup

```powershell
Copy-Item .env.example .env
npm.cmd install
npm.cmd run prisma:generate
```

Update `DATABASE_URL` and the three `FIREBASE_*` service-account values in
`.env`, then create the development migration:

```powershell
npm.cmd run prisma:migrate:dev -- --name init
```

## Commands

```powershell
npm.cmd run start:dev
npm.cmd run build
npm.cmd test
npm.cmd run lint
npm.cmd run prisma:validate
```

Health endpoint:

```text
GET /v1/health
```

LMS login endpoint:

```text
POST /v1/auth/lms-login
```

Request:

```json
{
  "role": "student",
  "username": "user@example.com",
  "password": "user-entered password"
}
```

## Current Scope

Implemented:

- Strict NestJS project structure
- Validated environment configuration
- PostgreSQL/Prisma schema
- Global Prisma service
- Health endpoint
- Normalized LMS client contracts
- Role-based EACC LMS endpoint routing
- Form-encoded LMS login requests
- Safe LMS error mapping
- Student and teacher response normalization tests
- Student HTML dashboard identity parser
- PHP session creation and dashboard loading
- Report-history course options excluded from authorization
- Student `/members/lms` active-course parser
- Closed courses excluded from active chat memberships
- Student and teacher LMS users synchronized to PostgreSQL
- Firebase custom tokens with role, LMS identity, display name, and course IDs
- Teacher course rosters returned to Flutter
- Admin Firebase authentication intentionally deferred

Waiting for the remaining role:

- Admin dashboard response and LMS authentication
- Firestore projection outbox worker
