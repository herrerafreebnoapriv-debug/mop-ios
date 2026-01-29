"""add extra_data to messages for call_invitation

Revision ID: a1b2c3d4e5f6
Revises: 4879ed3b22bb
Create Date: 2026-01-28

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = 'a1b2c3d4e5f6'
down_revision = '4879ed3b22bb'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'messages',
        sa.Column(
            'extra_data',
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
            comment='扩展数据，如 call_invitation（视频通话邀请）',
        ),
    )


def downgrade() -> None:
    op.drop_column('messages', 'extra_data')
