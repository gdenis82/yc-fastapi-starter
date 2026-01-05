from fastapi import APIRouter, Depends, HTTPException, status, Response, Request, BackgroundTasks
from fastapi.responses import JSONResponse
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from sqlalchemy.orm import selectinload
from typing import Any
from jose import jwt, JWTError

from app.api import deps
from app.core import security
from app.core.config import settings
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db, AsyncSessionLocal
from app.models.user import User
from app.models.role import Role
from app.models.token_denylist import TokenDenylist
from app.schemas.user import User as UserSchema, UserCreate, UserUpdate
from app.schemas.token import Token, TokenPayload

router = APIRouter()

async def cleanup_expired_tokens():
    from datetime import datetime, timezone
    async with AsyncSessionLocal() as db:
        try:
            now = datetime.now(timezone.utc)
            await db.execute(delete(TokenDenylist).where(TokenDenylist.exp < now))
            await db.commit()
        except Exception as e:
            await db.rollback()
            from app.core.logger import logger
            logger.error(f"Error cleaning up expired tokens: {e}")

async def get_role_by_name(db: AsyncSession, name: str) -> Role:
    result = await db.execute(select(Role).where(Role.name == name))
    return result.scalar_one_or_none()

@router.patch("/me", response_model=UserSchema)
async def update_user_me(
    *,
    db: AsyncSession = Depends(get_db),
    user_in: UserUpdate,
    current_user: User = Depends(deps.get_current_active_user),
) -> Any:
    if user_in.email is not None and user_in.email != current_user.email:
        result = await db.execute(select(User).where(User.email == user_in.email))
        user = result.scalar_one_or_none()
        if user:
            raise HTTPException(
                status_code=400,
                detail="The user with this email already exists in the system.",
            )
        current_user.email = user_in.email
    
    if user_in.username is not None:
        current_user.username = user_in.username
    
    if user_in.password is not None:
        current_user.hashed_password = security.get_password_hash(user_in.password)
    
    db.add(current_user)
    await db.commit()
    await db.refresh(current_user)
    
    # Reload with role_obj
    result = await db.execute(
        select(User)
        .where(User.id == current_user.id)
        .options(selectinload(User.role_obj))
    )
    return result.scalar_one()

@router.post("/register", response_model=UserSchema)
async def register(
    *,
    db: AsyncSession = Depends(get_db),
    user_in: UserCreate
) -> Any:
    try:
        result = await db.execute(select(User).where(User.email == user_in.email))
        user = result.scalar_one_or_none()
        if user:
            raise HTTPException(
                status_code=400,
                detail="The user with this email already exists in the system.",
            )
        
        role = await get_role_by_name(db, "user")
        
        user = User(
            username=user_in.username,
            email=user_in.email,
            hashed_password=security.get_password_hash(user_in.password),
            is_active=True,
            role_id=role.id if role else None
        )
        db.add(user)
        await db.commit()
        
        # Eagerly load role_obj for serialization
        result = await db.execute(
            select(User)
            .where(User.id == user.id)
            .options(selectinload(User.role_obj))
        )
        user = result.scalar_one()
        return user
    except HTTPException:
        raise
    except Exception as e:
        await db.rollback()
        from app.core.logger import logger
        logger.exception(f"Error during user registration: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Internal Server Error during registration: {str(e)}"
        )

@router.post("/login")
async def login(
    db: AsyncSession = Depends(get_db),
    form_data: OAuth2PasswordRequestForm = Depends()
) -> Any:
    result = await db.execute(select(User).where(User.email == form_data.username))
    user = result.scalar_one_or_none()
    if not user or not security.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Incorrect email or password")
    elif not user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    
    access_token = security.create_access_token(user.id)
    refresh_token = security.create_refresh_token(user.id)
    
    response = JSONResponse({
        "access_token": access_token,
        "token_type": "bearer",
    })
    response.set_cookie(
        key="refresh_token",
        value=refresh_token,
        httponly=True,
        secure=not settings.DEBUG,
        samesite="lax",
        max_age=settings.REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60,
        path="/api/auth",
    )
    
    return response

@router.post("/refresh", response_model=Token)
async def refresh(
    request: Request,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db)
) -> Any:
    background_tasks.add_task(cleanup_expired_tokens)
    refresh_token = request.cookies.get("refresh_token")
    if not refresh_token:
        raise HTTPException(status_code=401, detail="Refresh token missing")
    
    try:
        payload = jwt.decode(
            refresh_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        token_data = TokenPayload(**payload)
        if payload.get("type") != "refresh" or not token_data.jti or not token_data.sub:
            raise HTTPException(status_code=401, detail="Invalid token type or missing JTI/sub")
        
        # Check denylist
        result = await db.execute(
            select(TokenDenylist).where(TokenDenylist.jti == token_data.jti)
        )
        if result.scalar_one_or_none():
            response = JSONResponse(status_code=401, content={"detail": "Token has been revoked"})
            response.delete_cookie("refresh_token", path="/api/auth")
            return response
    except jwt.ExpiredSignatureError:
        response = JSONResponse(status_code=401, content={"detail": "Refresh token expired"})
        response.delete_cookie("refresh_token", path="/api/auth")
        return response
    except (JWTError, Exception):
        response = JSONResponse(status_code=401, content={"detail": "Could not validate credentials"})
        response.delete_cookie("refresh_token", path="/api/auth")
        return response
    
    result = await db.execute(select(User).where(User.id == token_data.sub))
    user = result.scalar_one_or_none()
    if not user:
        response = JSONResponse(status_code=404, content={"detail": "User not found"})
        response.delete_cookie("refresh_token", path="/api/auth")
        return response
    if not user.is_active:
        response = JSONResponse(status_code=400, content={"detail": "Inactive user"})
        response.delete_cookie("refresh_token", path="/api/auth")
        return response
    
    new_access_token = security.create_access_token(user.id)
    new_refresh_token = security.create_refresh_token(user.id)
    
    # Revoke old jti
    from datetime import datetime, timezone
    try:
        denylist_entry = TokenDenylist(
            jti=token_data.jti,
            exp=datetime.fromtimestamp(token_data.exp, tz=timezone.utc),
            user_id=user.id
        )
        db.add(denylist_entry)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        # Already in denylist - likely a race condition or reuse
        response = JSONResponse(status_code=401, content={"detail": "Token already revoked"})
        response.delete_cookie("refresh_token", path="/api/auth")
        return response
    except Exception as e:
        await db.rollback()
        from app.core.logger import logger
        logger.error(f"Error adding token to denylist: {e}")
        response = JSONResponse(status_code=401, content={"detail": "Token rotation failed"})
        response.delete_cookie("refresh_token", path="/api/auth")
        return response
    
    response = JSONResponse({
        "access_token": new_access_token,
        "token_type": "bearer",
    })
    response.set_cookie(
        key="refresh_token",
        value=new_refresh_token,
        httponly=True,
        secure=not settings.DEBUG,
        samesite="lax",
        max_age=settings.REFRESH_TOKEN_EXPIRE_DAYS * 24 * 60 * 60,
        path="/api/auth",
    )
    return response

@router.post("/logout")
async def logout(
    request: Request,
    response: Response,
    db: AsyncSession = Depends(get_db)
):
    refresh_token = request.cookies.get("refresh_token")
    if refresh_token:
        try:
            payload = jwt.decode(
                refresh_token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
            )
            token_data = TokenPayload(**payload)
            if payload.get("type") == "refresh" and token_data.jti and token_data.sub:
                from datetime import datetime, timezone
                try:
                    denylist_entry = TokenDenylist(
                        jti=token_data.jti,
                        exp=datetime.fromtimestamp(token_data.exp, tz=timezone.utc),
                        user_id=token_data.sub
                    )
                    db.add(denylist_entry)
                    await db.commit()
                except IntegrityError:
                    await db.rollback()
                except Exception as e:
                    await db.rollback()
                    from app.core.logger import logger
                    logger.error(f"Logout denylist error: {e}")
        except Exception:
            pass

    response.delete_cookie(
        key="refresh_token",
        httponly=True,
        secure=not settings.DEBUG,
        samesite="lax",
        path="/api/auth",
    )
    return {"detail": "Successfully logged out"}

@router.get("/me", response_model=UserSchema)
async def read_user_me(
    current_user: User = Depends(deps.get_current_active_user),
) -> Any:
    return current_user
