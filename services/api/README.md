# AfterTime API

The API currently exposes `GET /health`, which returns `{"status": "ok"}`.
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
