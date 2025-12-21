from fastapi import APIRouter

router = APIRouter()

@router.get("/")
async def read_root():
    return {"message": "Hello from FastAPI on Kubernetes!"}

@router.get("/health")
async def health():
    return {"status": "ok"}
