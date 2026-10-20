# E11 Console

E11 Agency's internal task manager (Asana-style): projects, tasks, CD review, client assets.

- **server/**: the app server (Node 22, no outside packages). Built-in SQLite database, live updates (Server-Sent Events), file storage, and sign-in through Cloudflare Access.
- **web/**: the app itself (the same interface as the Mac app).
- **Dockerfile**: the container that runs on the office QNAP NAS (Container Station). Data lives in `/data`.

## Running locally (for development)

```bash
cd server
DATA_DIR=../data AUTH_DEV=1 ADMIN_EMAIL=you@e11-digital.com node src/index.js
# open http://localhost:8080/?as=you@e11-digital.com
```

`AUTH_DEV=1` turns off the Cloudflare sign-in check. **Never set it on the NAS.**

## Settings (environment variables)

| Variable | Meaning |
|---|---|
| `DATA_DIR` | Where the database, files, backups and trash are kept (`/data` in the container) |
| `CF_TEAM` | Cloudflare Zero Trust team name (`e11hq`) |
| `CF_AUD` | "Application Audience (AUD) Tag" of the console.e11hq.com Access application |
| `ADMIN_EMAIL` | Becomes the first Admin on an empty server |
| `PORT` | Default 8080 |

## Tests

```bash
cd server && npm test
```
