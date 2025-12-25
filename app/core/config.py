from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "FastAPI Kubernetes Project"
    
    FASTAPI_KEY: str
    DATABASE_URL: str = ""
    
    model_config = SettingsConfigDict(case_sensitive=True, env_file=".env")

settings = Settings()
