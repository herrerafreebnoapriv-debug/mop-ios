"""add duration to messages

Revision ID: add_duration_msg
Revises: 6b47a5052638
Create Date: 2026-01-24 16:00:00

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'add_duration_msg'
down_revision = '6b47a5052638'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('messages', sa.Column('duration', sa.Integer(), nullable=True, comment='时长（秒），用于语音/视频消息'))


def downgrade() -> None:
    op.drop_column('messages', 'duration')
