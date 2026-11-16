# Phase 4 #014F-3A: Windows psql TLS for the shared session pooler

**Status: setup design only.** No Supabase service or database was contacted, no SQL was run, no credentials were requested, and no certificates, settings or software were installed. The shared pooler's actual certificate chain and this project's connection have **not** been verified. The official documentation pages cited below were consulted without accessing the user's project.

## Local client and trust evidence

- `C:\Program Files\PostgreSQL\18\bin\psql.exe --version` reports PostgreSQL **18.6**. The matching `pg_config.exe --version` reports 18.6; `pg_config --configure` returned no build flags. The client is not on PATH.
- Inspection of the matching `libpq.dll` PE import table found `libssl-3-x64.dll` and `libcrypto-3-x64.dll`, as well as `Secur32.dll`. Direct local inspection of the bundled crypto library reports **OpenSSL 3.5.8**. These imports support an OpenSSL-backed libpq build; the `Secur32` import alone does not establish that libpq uses Schannel or automatically applies Windows trust policy.
- OpenSSL reports its compiled default CA file as `C:\Program Files\Common Files\SSL\cert.pem` and its default CA directory as `C:\Program Files\Common Files\SSL\certs`; neither existed when inspected. The default libpq `%APPDATA%\postgresql\root.crt` was also absent. Process variables `PGSSLROOTCERT`, `PGSSLMODE`, `OPENSSL_CONF`, `SSL_CERT_FILE` and `SSL_CERT_DIR` were not set in the inspection process. These observations do not rule out configuration in another process, OpenSSL providers or Windows trust integration.
- An **offline, inconclusive** library-only check loaded OpenSSL's default trust paths and tried to validate 40 self-issued certificates enumerated from the Windows `ROOT` store. None validated in that limited check. This was not a libpq handshake, did not establish that Windows trust can never be used, and did not examine the pooler certificate. No certificate details were printed.

PostgreSQL 18 defines `sslrootcert=system` as the SSL implementation's default trust, not as a promise of Windows Schannel behavior; OpenSSL paths and environment can affect it. [PostgreSQL connection parameters](https://www.postgresql.org/docs/18/libpq-connect.html). OpenSSL's current [TLS guide](https://docs.openssl.org/3.5/man7/ossl-guide-tls-introduction/) describes Windows-root support from 3.2 onward, while its [Windows store documentation](https://docs.openssl.org/3.5/man7/OSSL_STORE-winstore/) notes that some Windows-specific trust constraints are not honored by that provider. Because the offline result did not establish the behavior of this particular libpq build, **do not assume `sslrootcert=system` will validate this pooler or reproduce all Windows trust decisions**. Testing that option against the actual pooler requires separate authorization; do not weaken verification if it fails.

## Recommended configuration: provider CA file

Supabase's [psql guide](https://supabase.com/docs/guides/database/psql) explicitly documents using the Dashboard's database root certificate, the **Session pooler** connection settings, and `sslmode=verify-full` together. This is the recommended, reviewable path here because it does not depend on an unverified Windows-store integration. The downloaded CA is public trust material, not a password, but its authenticity and integrity matter. A successful verification against it has not been demonstrated for this project or pooler.

For a later, separately authorized setup:

1. Privately open the official Supabase Dashboard and select only `aftertime-sql-test`; verify ref `wokkxbgbrsmydozvyvkt`. Under **Database Settings / SSL Configuration**, obtain the current database/server root CA certificate using the Dashboard's official download. Store the public certificate in a user-controlled local directory outside the repository, with its origin and permissions protected. Do not append it to a system trust store, modify the project, or download an arbitrary peer certificate and trust it as a root. Recheck current provider guidance if labels or certificates change.
2. Obtain the exact **Session pooler** hostname, port, database name and pooler username from the same project's Connect panel. Supabase's [connection guide](https://supabase.com/docs/guides/database/connecting-to-postgres) distinguishes the shared session pooler from transaction mode; use the Dashboard values rather than constructing the hostname from the region or assuming a port. The session pooler's username includes the project reference in Supabase's documented convention. Never paste a connection URI or password into a command, shell history, chat or report.
3. Ensure the downloaded trust file is PEM format as required by libpq, even if its filename ends in `.crt` or `.cer`. Verify locally without displaying its contents, for example by checking that it contains a `-----BEGIN CERTIFICATE-----` marker. If it is DER or an unexpected bundle, follow official provider guidance for safe format conversion; do not substitute a leaf certificate as a CA or silently expand trust. Confirm the trusted root source independently if the Dashboard download or chain is unexpected.
4. In a private PowerShell process, after reviewing any inherited `PG*`, `SSL_CERT_*`, `OPENSSL_CONF`, libpq service, password-file and TLS-key-log settings, set **only process-local** connection parameters. The following are templates to replace privately, not commands executed by this task. Do not copy actual values into a transcript or file. `PGUSER` is a database role, not an Auth email; the database password must not be put in an environment variable.

```powershell
$env:PGHOST = '<exact-session-pooler-host-from-Dashboard>'
$env:PGPORT = '<session-pooler-port-from-Dashboard>'
$env:PGDATABASE = '<database-name-from-Dashboard>'
$env:PGUSER = '<session-pooler-user-from-Dashboard>'
$env:PGSSLMODE = 'verify-full'
$env:PGSSLROOTCERT = '<absolute-path-to-authenticated-PEM-CA-file>'
$env:PGGSSENCMODE = 'disable'
$env:PGCONNECT_TIMEOUT = '10'
```

Set `PGGSSENCMODE=disable` so that libpq does not select GSS encryption in preference to TLS; PostgreSQL documents that `sslmode` alone does not force TLS when GSS encryption is available. Preserve the exact Dashboard hostname in `PGHOST`, rather than substituting an IP address or another pooler's name. Remove inherited `PGHOSTADDR` or other conflicting connection overrides before use; ensure no connection service or command-line option overrides these values. Do not set `PGPASSWORD`, use a password file, enable TLS key logging or change persistent machine/user settings.

5. Only after separate authorization for a connection, start the local client with an interactive password prompt:

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' --no-psqlrc --password
```

The command is intentionally missing credentials and was not executed. Password input goes to the client prompt, not the shell command. Before starting, independently confirm project, CA path, exact host and role; avoid terminal recording, logs and screenshots. On exit, close the client and clear the process-local `PG*` variables or close that PowerShell window. A public CA file can be removed later without changing project configuration.

## How validation works and what remains unproven

`verify-full` requires a trusted certificate chain **and** a server certificate hostname match; [PostgreSQL TLS guidance](https://www.postgresql.org/docs/18/libpq-ssl.html) describes SAN and wildcard matching. With `PGHOST` set to the exact Dashboard pooler DNS name, a successful TLS handshake configured as above demonstrates validation against the supplied CA and that host name for that connection. A separate connection attempt or SQL is not needed to configure these settings; the eventual handshake itself is the test. Do not infer verification merely because a TCP port is open, DNS resolves, or psql reports encryption. An administrator-controlled TLS interception root in a broadly trusted store changes the security meaning of that trust, which is another reason to prefer the authenticated provider CA when it validates the pooler.

The pooler host is shared: TLS hostname verification authenticates the host named by the certificate, **not by itself the project's tenant**. The correct Dashboard endpoint, project-qualified pooler username, database authentication and independently verified isolated project remain necessary. A successful TLS connection also does not prove session affinity, Auth row privileges or safe recipient claiming. Follow the independent two-session checks in `docs/PHASE_4_POSTGRES_TEST_SETUP_014F2.md` after separate authorization.

If CA loading, the hostname, the server chain, TLS negotiation or project identity cannot be verified, stop and record a sanitized failure. Do not downgrade to `require`, `verify-ca`, plaintext or an IP literal; do not add an unverified root, disable certificate checks, reset a password, change SSL enforcement, or guess that the project CA covers every shared pooler certificate. Investigate against current provider guidance or support. Never capture passwords, JWTs, user UUIDs, connection strings, raw query output or full logs in the results.
