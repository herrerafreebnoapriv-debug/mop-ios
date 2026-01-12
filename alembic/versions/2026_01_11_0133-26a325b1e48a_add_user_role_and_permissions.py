"""add_user_role_and_permissions

Revision ID: 26a325b1e48a
Revises: f07fd654883e
Create Date: 2026-01-11 01:33:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '26a325b1e48a'
down_revision = 'a4772a53dab9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 添加用户角色和权限字段
    op.add_column('users', sa.Column('role', sa.String(length=20), nullable=True, server_default='user', comment='用户角色：super_admin/room_owner/user'))
    op.add_column('users', sa.Column('max_rooms', sa.Integer(), nullable=True, comment='房主最大可创建房间数'))
    op.add_column('users', sa.Column('default_max_occupants', sa.Integer(), nullable=True, server_default='3', comment='房主房间默认最大人数上限'))
    op.add_column('users', sa.Column('is_disabled', sa.Boolean(), nullable=True, server_default='false', comment='是否禁用'))
    
    # 创建索引
    op.create_index('ix_users_role', 'users', ['role'], unique=False)
    op.create_index('ix_users_is_disabled', 'users', ['is_disabled'], unique=False)
    
    # 将 zhanan089 设置为超级管理员
    op.execute("""
        UPDATE users 
        SET role = 'super_admin', is_admin = true 
        WHERE username = 'zhanan089' OR phone LIKE '%zhanan089%'
    """)
    
    # 创建操作日志表
    op.create_table('operation_logs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True, comment='操作用户ID'),
        sa.Column('username', sa.String(length=100), nullable=True, comment='操作用户名（冗余字段，防止用户删除后无法追溯）'),
        sa.Column('operation_type', sa.String(length=20), nullable=False, comment='操作类型：create/read/update/delete'),
        sa.Column('resource_type', sa.String(length=50), nullable=False, comment='资源类型：user/room/device等'),
        sa.Column('resource_id', sa.Integer(), nullable=True, comment='资源ID'),
        sa.Column('resource_name', sa.String(length=200), nullable=True, comment='资源名称（冗余字段）'),
        sa.Column('operation_detail', sa.Text(), nullable=True, comment='操作详情（JSON格式）'),
        sa.Column('ip_address', sa.String(length=45), nullable=True, comment='操作IP地址'),
        sa.Column('user_agent', sa.String(length=500), nullable=True, comment='用户代理'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.text('now()'), comment='操作时间'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        comment='操作日志表'
    )
    
    # 创建操作日志索引
    op.create_index('ix_operation_logs_user_id', 'operation_logs', ['user_id'], unique=False)
    op.create_index('ix_operation_logs_operation_type', 'operation_logs', ['operation_type'], unique=False)
    op.create_index('ix_operation_logs_resource_type', 'operation_logs', ['resource_type'], unique=False)
    op.create_index('ix_operation_logs_resource_id', 'operation_logs', ['resource_id'], unique=False)
    op.create_index('ix_operation_logs_ip_address', 'operation_logs', ['ip_address'], unique=False)
    op.create_index('ix_operation_logs_created_at', 'operation_logs', ['created_at'], unique=False)


def downgrade() -> None:
    # 删除操作日志表
    op.drop_index('ix_operation_logs_created_at', table_name='operation_logs')
    op.drop_index('ix_operation_logs_ip_address', table_name='operation_logs')
    op.drop_index('ix_operation_logs_resource_id', table_name='operation_logs')
    op.drop_index('ix_operation_logs_resource_type', table_name='operation_logs')
    op.drop_index('ix_operation_logs_operation_type', table_name='operation_logs')
    op.drop_index('ix_operation_logs_user_id', table_name='operation_logs')
    op.drop_table('operation_logs')
    
    # 删除用户角色和权限字段
    op.drop_index('ix_users_is_disabled', table_name='users')
    op.drop_index('ix_users_role', table_name='users')
    op.drop_column('users', 'is_disabled')
    op.drop_column('users', 'default_max_occupants')
    op.drop_column('users', 'max_rooms')
    op.drop_column('users', 'role')
