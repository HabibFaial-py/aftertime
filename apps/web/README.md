# AfterTime web

From the repository root in PowerShell:

```powershell
Set-Location apps/web
npm install
npm run dev
```

Open http://localhost:3000. Stop the server with Ctrl+C. Run checks from `apps/web`:

```powershell
npm run typecheck
npm run lint
npm run build
```
