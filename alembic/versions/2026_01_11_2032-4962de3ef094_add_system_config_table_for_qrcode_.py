"""add_system_config_table_for_qrcode_settings

Revision ID: 4962de3ef094
Revises: c23b1f2c3b44
Create Date: 2026-01-11 20:32:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '4962de3ef094'
down_revision = 'c23b1f2c3b44'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 创建系统配置表
    op.create_table('system_configs',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('config_key', sa.String(length=100), nullable=False, unique=True, comment='配置键（唯一）'),
    sa.Column('config_value', sa.Text(), nullable=True, comment='配置值（JSON格式）'),
    sa.Column('description', sa.String(length=500), nullable=True, comment='配置说明'),
    sa.Column('created_at', sa.DateTime(), nullable=False, comment='创建时间'),
    sa.Column('updated_at', sa.DateTime(), nullable=False, comment='更新时间'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_system_configs_config_key', 'system_configs', ['config_key'], unique=True)
    
    # 插入默认配置
    from datetime import datetime
    op.execute(f"""
        INSERT INTO system_configs (config_key, config_value, description, created_at, updated_at)
        VALUES 
        ('qrcode.encrypted_enabled', 'true', '是否启用加密二维码邀请（需要客户端解密）', '{datetime.utcnow()}', '{datetime.utcnow()}'),
        ('qrcode.plain_enabled', 'false', '是否启用未加密二维码邀请（游客可直接扫描）', '{datetime.utcnow()}', '{datetime.utcnow()}'),
        ('qrcode.plain_max_scans', '3', '未加密二维码最大扫描次数（0表示不限制）', '{datetime.utcnow()}', '{datetime.utcnow()}')
    """)


def downgrade() -> None:
    op.drop_index('ix_system_configs_config_key', table_name='system_configs')
    op.drop_table('system_configs')
