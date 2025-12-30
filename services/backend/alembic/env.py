import os
from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context
from app.models.base import Base
from app.core.config import settings

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
# from myapp import mymodel
# target_metadata = mymodel.Base.metadata
target_metadata = Base.metadata

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option("my_important_option")
# ... etc.


import asyncio
import ssl
import os
import urllib.parse
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.engine import make_url

def fix_database_url(url: str) -> str:
    """
    Correctly escapes special characters in the database URL password.
    Handles cases where password contains '@' or '?'.
    """
    if not url or "://" not in url:
        return url
    
    scheme, rest = url.split("://", 1)
    
    # Identify the credentials and host part.
    # It ends at the first '/', '?' or '#' that is NOT part of the credentials.
    # However, if the password contains '?' or '@', it can be ambiguous.
    # The most reliable separator between host and path is the first '/'.
    first_slash = rest.find("/")
    if first_slash != -1:
        cred_and_host = rest[:first_slash]
        path_and_query = rest[first_slash:]
    else:
        # If no '/', the host part might end with '?' (query string)
        # We find the LAST '@' to separate credentials from host.
        last_at = rest.rfind("@")
        if last_at == -1:
            return url
            
        # Everything after the last '@' until the first '?' is the host.
        remaining = rest[last_at+1:]
        host_end = len(remaining)
        for sep in "?#":
            idx = remaining.find(sep)
            if idx != -1 and idx < host_end:
                host_end = idx
        
        cred_and_host = rest[:last_at + 1 + host_end]
        path_and_query = rest[last_at + 1 + host_end:]

    if "@" not in cred_and_host:
        return url
        
    # The last '@' in cred_and_host separates credentials from host
    creds, host = cred_and_host.rsplit("@", 1)
    
    if ":" not in creds:
        user = creds
        password = ""
    else:
        user, password = creds.split(":", 1)
    
    # Re-quote user and password
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
        print(f"DEBUG: Configuring SSL context for mode: {ssl_mode}")
        if ssl_mode in ['verify-ca', 'verify-full']:
            if ssl_root_cert:
                if os.path.exists(ssl_root_cert):
                    ssl_context = ssl.create_default_context(cafile=ssl_root_cert)
                else:
                    print(f"DEBUG: Warning: sslrootcert file not found at {ssl_root_cert}")
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

def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.

    This configures the context with just a URL
    and not an Engine, though an Engine is acceptable
    here as well.  By skipping the Engine creation
    we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.

    """
    url, _ = get_engine_settings()
    context.configure(
        url=str(url),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)

    with context.begin_transaction():
        context.run_migrations()


async def run_migrations_online() -> None:
    """Run migrations in 'online' mode.

    In this scenario we need to create an Engine
    and associate a connection with the context.

    """
    url, connect_args = get_engine_settings()
    
    print(f"DEBUG: Creating engine for {url.drivername} (host: {url.host})")

    connectable = create_async_engine(
        url,
        poolclass=pool.NullPool,
        connect_args=connect_args,
    )

    print("DEBUG: Connecting to database...")
    async with connectable.connect() as connection:
        print("DEBUG: Connection established. Running migrations sync...")
        await connection.run_sync(do_run_migrations)

    print("DEBUG: Migrations completed. Disposing engine...")
    await connectable.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    asyncio.run(run_migrations_online())
