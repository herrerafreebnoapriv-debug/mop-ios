"""add_qrcode_type_to_qrcode_scans

Revision ID: 49f2d339a98e
Revises: 4962de3ef094
Create Date: 2026-01-11 20:33:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '49f2d339a98e'
down_revision = '4962de3ef094'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 添加二维码类型字段
    op.add_column('qrcode_scans', sa.Column('qrcode_type', sa.String(length=20), nullable=False, server_default='encrypted', comment='二维码类型：encrypted（加密）或 plain（未加密）'))
    op.create_index('ix_qrcode_scans_qrcode_type', 'qrcode_scans', ['qrcode_type'], unique=False)
    
    # 修改 max_scans 的注释，说明 0 表示不限制
    op.alter_column('qrcode_scans', 'max_scans',
                    existing_type=sa.INTEGER(),
                    comment='最大扫描次数（0表示不限制）',
                    existing_comment='最大扫描次数',
                    existing_nullable=False)


def downgrade() -> None:
    op.drop_index('ix_qrcode_scans_qrcode_type', table_name='qrcode_scans')
    op.drop_column('qrcode_scans', 'qrcode_type')
    op.alter_column('qrcode_scans', 'max_scans',
                    existing_type=sa.INTEGER(),
                    comment='最大扫描次数',
                    existing_comment='最大扫描次数（0表示不限制）',
                    existing_nullable=False)
