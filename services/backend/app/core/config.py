from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "FastAPI Kubernetes Project"
    
    SECRET_KEY: str = "temporary-secret-key-change-me"
    DATABASE_URL: str = "postgresql://postgres:postgres@localhost:5432/postgres"
    
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    
    GITHUB_CLIENT_ID: str = ""
    GITHUB_CLIENT_SECRET: str = ""
    GITHUB_REDIRECT_URI: str = "http://localhost:3000/auth/callback/github"
    
    CORS_ORIGINS: list[str] = ["http://localhost:3000"]
    
    model_config = SettingsConfigDict(case_sensitive=True, env_file=".env")

settings = Settings()
