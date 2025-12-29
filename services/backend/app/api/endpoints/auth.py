from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload
from typing import Any

from app.api import deps
from app.core import security
from app.core.config import settings
from app.db.session import get_db
from app.models.user import User
from app.models.role import Role
from app.schemas.user import User as UserSchema, UserCreate
from app.schemas.token import Token

router = APIRouter()

async def get_role_by_name(db: AsyncSession, name: str) -> Role:
    result = await db.execute(select(Role).where(Role.name == name))
    return result.scalar_one_or_none()

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

@router.post("/login", response_model=Token)
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
    
    return {
        "access_token": security.create_access_token(user.id),
        "token_type": "bearer",
    }

@router.get("/me", response_model=UserSchema)
async def read_user_me(
    current_user: User = Depends(deps.get_current_active_user),
) -> Any:
    return current_user
