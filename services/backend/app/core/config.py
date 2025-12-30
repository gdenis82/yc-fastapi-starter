from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "FastAPI Kubernetes Project"
    
    SECRET_KEY: str = "secret-key"
    DATABASE_URL: str = "postgresql://postgres:postgres@localhost:5432/postgres"
    
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    
    CORS_ORIGINS: list[str] = ["http://localhost:3000"]
    
    model_config = SettingsConfigDict(case_sensitive=True, env_file=".env")

settings = Settings()
