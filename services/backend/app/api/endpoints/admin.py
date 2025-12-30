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
        filters = [
            User.username.ilike(search_filter),
            User.email.ilike(search_filter),
        ]
        if hasattr(User, 'name'):
            filters.append(User.name.ilike(search_filter))
            
        query = query.where(or_(*filters))
    
    if role:
        query = query.join(User.role_obj).where(Role.name == role)
    
    # Sorting
    if sort:
        field, order = sort.split(":")
        # Map 'name' to 'username' since 'name' field doesn't exist in User model
        db_field = field if field != "name" else "username"
        attr = getattr(User, db_field, User.username)
        if order == "desc":
            query = query.order_by(attr.desc())
        else:
            query = query.order_by(attr.asc())
    
    # Pagination
    # Count total users before pagination but after filtering
    total_query = select(func.count(User.id)).select_from(query.order_by(None).subquery())
    total_result = await db.execute(total_query)
    total = total_result.scalar()
    
    query = query.offset((page - 1) * limit).limit(limit)
    result = await db.execute(query)
    users = result.scalars().all()
    
    return {"users": users, "total": total}
