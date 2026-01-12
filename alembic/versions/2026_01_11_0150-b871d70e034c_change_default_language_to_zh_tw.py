"""change_default_language_to_zh_TW

Revision ID: b871d70e034c
Revises: 26a325b1e48a
Create Date: 2026-01-11 01:50:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'b871d70e034c'
down_revision = '26a325b1e48a'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 更新 users 表的 language 字段默认值为 zh_TW
    op.alter_column('users', 'language',
                    existing_type=sa.String(length=10),
                    server_default='zh_TW',
                    comment='用户语言偏好')
    
    # 将现有用户的 language 为 NULL 或 en_US 的更新为 zh_TW
    op.execute("""
        UPDATE users 
        SET language = 'zh_TW' 
        WHERE language IS NULL OR language = 'en_US'
    """)


def downgrade() -> None:
    # 恢复默认值为 en_US
    op.alter_column('users', 'language',
                    existing_type=sa.String(length=10),
                    server_default='en_US',
                    comment='用户语言偏好')
    
    # 将现有用户的 language 为 zh_TW 的更新为 en_US
    op.execute("""
        UPDATE users 
        SET language = 'en_US' 
        WHERE language = 'zh_TW'
    """)
