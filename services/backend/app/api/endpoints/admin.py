from typing import Any, List
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_
from sqlalchemy.orm import selectinload

from app.api import deps
from app.db.session import get_db
from app.models.user import User
from app.models.role import Role
from app.schemas.user import User as UserSchema

router = APIRouter()

@router.get("/users", response_model=Any)
async def read_users(
    db: AsyncSession = Depends(get_db),
    page: int = Query(1, ge=1),
    limit: int = Query(10, ge=1, le=100),
    search: str = Query(None),
    role: str = Query(None),
    sort: str = Query("name:asc"),
    current_user: User = Depends(deps.get_current_active_admin),
) -> Any:
    """
    Retrieve users for admin dashboard.
    """
    query = select(User).options(selectinload(User.role_obj))
    
    # Filtering
    if search:
        search_filter = f"%{search}%"
        query = query.where(
            or_(
                User.username.ilike(search_filter),
                User.email.ilike(search_filter),
                User.name.ilike(search_filter) if hasattr(User, 'name') else User.username.ilike(search_filter)
            )
        )
    
    if role:
        query = query.join(User.role_obj).where(Role.name == role)
    
    # Sorting
    if sort:
        field, order = sort.split(":")
        attr = getattr(User, field, User.username)
        if order == "desc":
            query = query.order_by(attr.desc())
        else:
            query = query.order_by(attr.asc())
    
    # Pagination
    total_query = select(func.count()).select_from(query.subquery())
    total_result = await db.execute(total_query)
    total = total_result.scalar()
    
    query = query.offset((page - 1) * limit).limit(limit)
    result = await db.execute(query)
    users = result.scalars().all()
    
    return {"users": users, "total": total}
