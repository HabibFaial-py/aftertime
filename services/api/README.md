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
