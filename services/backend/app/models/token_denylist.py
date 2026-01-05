from sqlalchemy import Column, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from app.models.base import Base

class TokenDenylist(Base):
    __tablename__ = "token_denylist"

    jti = Column(String, primary_key=True, index=True, unique=True)
    exp = Column(DateTime(timezone=True), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    user_id = Column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    user = relationship("User")
