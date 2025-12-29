from sqlalchemy import String, Boolean, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.models.base import Base
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from app.models.role import Role

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=True) # Nullable for OAuth users
    role_id: Mapped[int] = mapped_column(ForeignKey("roles.id"), nullable=True)
    role: Mapped[str] = mapped_column(String(50), default="user") # Keep for backward compatibility or transition
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    github_id: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=True)

    role_obj: Mapped["Role"] = relationship("Role", back_populates="users")
