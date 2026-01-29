"""add_system_version_to_user_devices

Revision ID: 4879ed3b22bb
Revises: add_duration_msg
Create Date: 2026-01-24 21:40:14.937713

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '4879ed3b22bb'
down_revision = 'add_duration_msg'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 添加 system_version 字段到 user_devices 表
    op.add_column('user_devices', sa.Column('system_version', sa.String(length=50), nullable=True, comment='系统版本'))


def downgrade() -> None:
    # 移除 system_version 字段
    op.drop_column('user_devices', 'system_version')
