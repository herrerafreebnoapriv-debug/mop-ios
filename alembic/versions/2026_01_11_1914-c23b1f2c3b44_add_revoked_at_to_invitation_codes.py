"""add_revoked_at_to_invitation_codes

Revision ID: c23b1f2c3b44
Revises: b871d70e034c
Create Date: 2026-01-11 19:14:04.093636

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'c23b1f2c3b44'
down_revision = 'b871d70e034c'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 添加 revoked_at 字段到 invitation_codes 表
    op.add_column('invitation_codes', sa.Column('revoked_at', sa.DateTime(), nullable=True, comment='撤回时间'))


def downgrade() -> None:
    # 移除 revoked_at 字段
    op.drop_column('invitation_codes', 'revoked_at')
