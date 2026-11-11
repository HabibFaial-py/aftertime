from fastapi import Depends, FastAPI

from app.auth import current_user

app = FastAPI()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/auth/me")
def me(user_id: str = Depends(current_user)) -> dict[str, str]:
    return {"id": user_id}
