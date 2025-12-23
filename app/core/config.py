from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field, computed_field

class Settings(BaseSettings):
    PROJECT_NAME: str = "FastAPI Kubernetes Project"
    
    POSTGRES_SERVER: str
    POSTGRES_USER: str
    POSTGRES_PASSWORD: str
    POSTGRES_DB: str
    POSTGRES_PORT: str = "5432"
    FASTAPI_KEY: str
    
    @computed_field
    @property
    def SQLALCHEMY_DATABASE_URI(self) -> str:
        # Use sslmode=require for Yandex Cloud Managed PostgreSQL.
        # asyncpg uses 'ssl' parameter instead of 'sslmode'
        return f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}@{self.POSTGRES_SERVER}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}?ssl=require"

    model_config = SettingsConfigDict(case_sensitive=True, env_file=".env")

settings = Settings()
