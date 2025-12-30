import ssl
import os
import urllib.parse
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.engine import make_url
from app.core.config import settings

def fix_database_url(url: str) -> str:
    """
    Correctly escapes special characters in the database URL password.
    """
    if not url or "://" not in url:
        return url
    
    scheme, rest = url.split("://", 1)
    
    # Find where the path/query starts
    path_start = len(rest)
    for sep in "/?#":
        idx = rest.find(sep)
        if idx != -1 and idx < path_start:
            path_start = idx
            
    cred_and_host = rest[:path_start]
    path_and_query = rest[path_start:]
    
    if "@" not in cred_and_host:
        return url
        
    # The last '@' separates credentials from host
    creds, host = cred_and_host.rsplit("@", 1)
    
    if ":" not in creds:
        # No password part
        return url
        
    user, password = creds.split(":", 1)
    
    # Re-quote user and password to handle special characters like '@' or ':'
    # We unquote first to avoid double-encoding if it was already encoded
    quoted_user = urllib.parse.quote(urllib.parse.unquote(user), safe="")
    quoted_password = urllib.parse.quote(urllib.parse.unquote(password), safe="")
    
    return f"{scheme}://{quoted_user}:{quoted_password}@{host}{path_and_query}"

def get_engine_settings():
    fixed_url = fix_database_url(settings.DATABASE_URL)
    url = make_url(fixed_url)
    
    # Ensure we use asyncpg driver
    if url.drivername == "postgresql":
        url = url.set(drivername="postgresql+asyncpg")
    
    connect_args = {}
    query = dict(url.query)
    
    ssl_mode = query.pop("sslmode", None)
    ssl_root_cert = query.pop("sslrootcert", None)
    
    if ssl_mode:
        if ssl_mode in ['verify-ca', 'verify-full']:
            if ssl_root_cert:
                if os.path.exists(ssl_root_cert):
                    ssl_context = ssl.create_default_context(cafile=ssl_root_cert)
                else:
                    ssl_context = ssl.create_default_context()
            else:
                ssl_context = ssl.create_default_context()
                
            if ssl_mode == 'verify-ca':
                ssl_context.check_hostname = False
            
            connect_args["ssl"] = ssl_context
        elif ssl_mode == 'require':
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            connect_args["ssl"] = ssl_context
            
        # Update URL to remove ssl parameters that asyncpg doesn't support
        url = url.set(query=query)
        
    return url, connect_args

database_url, connect_args = get_engine_settings()

engine = create_async_engine(database_url, echo=True, connect_args=connect_args)
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    expire_on_commit=False,
    class_=AsyncSession
)

async def get_db():
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
