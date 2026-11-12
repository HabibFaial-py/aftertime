# AfterTime API

The API exposes `GET /health`, which returns `{"status": "ok"}`, and `GET /v1/auth/me`.
Use Python 3.11 and the existing virtual environment at the repository root.
Run these commands in PowerShell from the repository root:

```powershell
.\.venv\Scripts\python.exe -m pip install -r services/api/requirements-lock.txt
Set-Location services/api
..\..\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

Visit http://127.0.0.1:8000/health. Stop the server with Ctrl+C.
To run the test, from the repository root:

```powershell
Set-Location services/api
..\..\.venv\Scripts\python.exe -m pytest
```

`requirements.txt` lists the direct dependencies; the lock file pins their
resolved dependencies for reproducible installation.

## Authentication

`GET /v1/auth/me` accepts a Supabase user access token in a Bearer header and returns only `{"id": "<verified subject>"}`. The API reads process environment variables; it does not automatically load `.env` files. Set these in the PowerShell session before starting the server, using your own development project values:

```powershell
$env:SUPABASE_URL = 'https://your-project.supabase.co'
$env:SUPABASE_PUBLISHABLE_KEY = 'your-publishable-key'
$env:SUPABASE_JWT_ISSUER = 'https://your-project.supabase.co/auth/v1'
$env:SUPABASE_JWT_AUDIENCE = 'authenticated'
```

Confirm the issuer and audience against your project configuration. The URL must be HTTPS and the issuer must match its `/auth/v1` path. The publishable key is required configuration but is not used by the JWKS verification path. Do not put service credentials in these variables or commit local values. `/health` works without auth configuration.

The verifier accepts ES256 and RS256 only, fetching the project's public keys from `/auth/v1/.well-known/jwks.json`; it verifies signature, issuer, audience, expiry and UUID subject. Key sets are cached in process for five minutes by PyJWT, in addition to Supabase's edge cache, so revoked keys may remain usable until caches expire. Unknown keys trigger a refresh subject to PyJWT's cooldown. Key-service failures return 503; invalid tokens return 401. This verifies a token locally and does not check whether a session has since been revoked or a user deleted.

Check the project's actual signing algorithm and key configuration before using this endpoint. Legacy HS256 tokens are rejected: Supabase recommends verifying those via its Auth server `/auth/v1/user`, which this slice does not implement. Never use the publishable key as a JWT signing secret. See [Supabase JWT verification](https://supabase.com/docs/guides/auth/jwts) and [signing-key caching](https://supabase.com/docs/guides/auth/signing-keys).

## Server-only database access (Phase 2, Part 1)

`app/database.py` contains a minimal `DatabaseRepository` for Supabase's PostgreSQL
Data API. It reuses pinned HTTPX 0.28.1; no dependencies or lockfile changes were
needed. This is HTTPS/PostgREST access, not a direct PostgreSQL/SQLAlchemy connection.
The sole operation currently available is `check_connection()`.

Compatibility review (2026-11-12): the current [Python initialization reference](https://supabase.com/docs/reference/python/initializing)
accepts a project URL and key, and the [Python server example](https://supabase.com/docs/reference/python/admin-api)
explicitly uses a secret key with session persistence and refresh disabled.
The full SDK supports this approach, but is unnecessary for this bounded read.
We use the existing HTTPX client directly, following [Supabase key guidance](https://supabase.com/docs/guides/getting-started/api-keys):
send `sb_secret_*` in `apikey`, not as a Bearer JWT. No SDK version is installed or
claimed tested. Legacy service-role JWTs and publishable keys are rejected by our
database configuration. No fallback to a weaker credential is attempted.

`get_database_settings()` reads `SUPABASE_URL` and `SUPABASE_SECRET_KEY` only when
the repository is constructed. Authentication settings and `app/auth.py` remain
independent. The URL must be an HTTPS origin on the default/443 port without
userinfo, path, query or fragment. Validation checks key type and header-safe
syntax; it cannot prove that a key exists, is unrevoked or belongs to the project.
The secret is excluded from the settings representation. `.env.example` contains
only a deliberately invalid placeholder, and `.env` files are not auto-loaded.

The repository creates and closes its own HTTP client, accepts no user JWTs or
incoming request headers, and has no sign-in/session API. It uses TLS validation,
five-second HTTP operation timeouts, no redirects, no retries and no environment
proxies. `/health` and `/v1/auth/me` never construct this client. No database route
or unrestricted query proxy is exposed.

The read-only check sends `HEAD /rest/v1/profiles?select=id&limit=1` with
`Accept-Profile: public`. It checks access to an existing table even if empty,
requests no row body or count, and returns no records. Only HTTP 200/206 is success;
permission errors, revoked keys, redirects and outages fail with a fixed message.
Provider error bodies and exception details are never printed or logged by this
code. Do not add request/header dumps, environment dumps or credential-bearing
tracing to privileged operations.

Secret keys run as `service_role` and bypass RLS. Existing schema/table grants
are still required. All future user-specific repository calls must enforce
authorization explicitly using the identity from the FastAPI JWT verifier before
retrieving data. This check does not prove RLS isolation, cross-account safety,
write privileges, transaction behavior or reveal authorization. Future atomic
capsule/job creation needs a separately designed transaction boundary; several
Data API requests are not one transaction. Migrations and RLS remain unchanged.

### Offline verification

From the repository root in PowerShell:

```powershell
Set-Location services/api
..\..\.venv\Scripts\python.exe -m pytest -q
..\..\.venv\Scripts\python.exe -m pip check
```

Database tests replace HTTP transport with mocks and use dummy keys. They cover
missing/invalid config, successful reads, permission/provider failures, redirects,
connection failures/timeouts, sanitized output, resource cleanup and independent
API behavior. No live database connection is made by these tests.

### Safe live connectivity test (manual, not run in this task)

After separate authorization, use the development project only. Confirm that
the existing `SUPABASE_URL` points to that project, the Data API exposes `public`,
and `service_role` has schema usage and SELECT on `public.profiles`. Do not change
RLS or grants to make the check pass. Obtain an existing server secret through
your trusted project settings; never paste it into chat, source files or a shell
command. Keep the existing Auth environment variables as configured above.

In a dedicated backend PowerShell terminal, run these commands from the repository
root. The secure prompt keeps the key out of terminal echo and command history;
the backend process inherits it from that terminal. Do not run with debug tracing or
environment capture enabled.

```powershell
Set-Location services/api
$databaseSecretInput = Read-Host 'Development Supabase server secret' -AsSecureString
$databaseSecretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($databaseSecretInput)
try {
    $env:SUPABASE_SECRET_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($databaseSecretPointer)
    ..\..\.venv\Scripts\python.exe -m app.check_database
    Write-Output "Connectivity command exit code: $LASTEXITCODE"
} finally {
    Remove-Item Env:SUPABASE_SECRET_KEY -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($databaseSecretPointer)
    $databaseSecretInput.Dispose()
}
```

Exit 0 prints `Database connectivity check passed.`; exit 1 prints only
`Database connectivity check failed.`; exit 2 reports missing/invalid configuration.
For failures, privately verify the project URL, key type/revocation, Data API/schema
settings, grants and network availability; do not print the key or raw provider
response. Record the actual result in STATUS. Live connectivity has not been
tested as part of this implementation.
