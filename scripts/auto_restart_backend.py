#!/usr/bin/env python3
"""
自动重启后端服务器脚本
监控代码文件变化，自动重启后端服务器
"""

import os
import sys
import time
import subprocess
import signal
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# 项目根目录
PROJECT_ROOT = Path("/opt/mop")
RESTART_SCRIPT = PROJECT_ROOT / "restart_server.sh"
LOG_FILE = Path("/var/log/mop-auto-restart.log")

# 需要监控的文件扩展名
WATCHED_EXTENSIONS = {'.py', '.yaml', '.yml', '.json', '.env'}
# 需要监控的目录
WATCHED_DIRS = [
    'app',
    'alembic',
]

# 忽略的目录和文件
IGNORED_PATTERNS = [
    '__pycache__',
    '.git',
    '.pytest_cache',
    '*.pyc',
    '*.pyo',
    '.env',
    'venv',
    'env',
    'node_modules',
]

# 防抖延迟（秒）- 避免频繁重启
DEBOUNCE_DELAY = 3

class RestartHandler(FileSystemEventHandler):
    """文件变化处理器"""
    
    def __init__(self):
        self.last_restart_time = 0
        self.restart_timer = None
        
    def should_ignore(self, path: Path) -> bool:
        """检查路径是否应该被忽略"""
        path_str = str(path)
        for pattern in IGNORED_PATTERNS:
            if pattern in path_str:
                return True
        return False
    
    def is_watched_file(self, path: Path) -> bool:
        """检查文件是否需要监控"""
        if path.suffix not in WATCHED_EXTENSIONS:
            return False
        
        # 检查是否在监控目录中
        rel_path = path.relative_to(PROJECT_ROOT)
        for watched_dir in WATCHED_DIRS:
            if str(rel_path).startswith(watched_dir):
                return True
        
        return False
    
    def schedule_restart(self):
        """安排重启（防抖）"""
        current_time = time.time()
        
        # 如果距离上次重启时间太短，取消之前的定时器
        if self.restart_timer:
            return
        
        # 设置定时器
        def do_restart():
            self.restart_timer = None
            self.restart_backend()
        
        self.restart_timer = do_restart
        time.sleep(DEBOUNCE_DELAY)
        if self.restart_timer == do_restart:  # 如果定时器没有被取消
            do_restart()
    
    def restart_backend(self):
        """重启后端服务器"""
        current_time = time.time()
        
        # 防抖：如果距离上次重启时间太短，跳过
        if current_time - self.last_restart_time < DEBOUNCE_DELAY:
            return
        
        self.last_restart_time = current_time
        
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        log_msg = f"[{timestamp}] 检测到代码变化，正在重启后端服务器...\n"
        
        # 写入日志
        try:
            with open(LOG_FILE, 'a', encoding='utf-8') as f:
                f.write(log_msg)
        except Exception as e:
            print(f"写入日志失败: {e}")
        
        print(log_msg.strip())
        
        # 执行重启脚本
        try:
            result = subprocess.run(
                ['bash', str(RESTART_SCRIPT)],
                cwd=PROJECT_ROOT,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                success_msg = f"[{timestamp}] ✅ 后端服务器重启成功\n"
            else:
                success_msg = f"[{timestamp}] ❌ 后端服务器重启失败: {result.stderr}\n"
            
            print(success_msg.strip())
            
            # 写入日志
            try:
                with open(LOG_FILE, 'a', encoding='utf-8') as f:
                    f.write(success_msg)
                    if result.stdout:
                        f.write(result.stdout)
                    if result.stderr:
                        f.write(f"错误输出: {result.stderr}\n")
            except Exception as e:
                print(f"写入日志失败: {e}")
                
        except subprocess.TimeoutExpired:
            error_msg = f"[{timestamp}] ❌ 重启超时\n"
            print(error_msg.strip())
            try:
                with open(LOG_FILE, 'a', encoding='utf-8') as f:
                    f.write(error_msg)
            except:
                pass
        except Exception as e:
            error_msg = f"[{timestamp}] ❌ 重启失败: {str(e)}\n"
            print(error_msg.strip())
            try:
                with open(LOG_FILE, 'a', encoding='utf-8') as f:
                    f.write(error_msg)
            except:
                pass
    
    def on_modified(self, event):
        """文件修改事件"""
        if event.is_directory:
            return
        
        path = Path(event.src_path)
        
        # 检查是否应该忽略
        if self.should_ignore(path):
            return
        
        # 检查是否是监控的文件
        if not self.is_watched_file(path):
            return
        
        # 安排重启
        self.schedule_restart()
    
    def on_created(self, event):
        """文件创建事件"""
        self.on_modified(event)
    
    def on_deleted(self, event):
        """文件删除事件"""
        self.on_modified(event)


def main():
    """主函数"""
    print("=" * 60)
    print("MOP 后端自动重启监控服务")
    print("=" * 60)
    print(f"监控目录: {', '.join(WATCHED_DIRS)}")
    print(f"监控文件类型: {', '.join(WATCHED_EXTENSIONS)}")
    print(f"防抖延迟: {DEBOUNCE_DELAY} 秒")
    print(f"日志文件: {LOG_FILE}")
    print("=" * 60)
    print("按 Ctrl+C 停止监控")
    print()
    
    # 检查重启脚本是否存在
    if not RESTART_SCRIPT.exists():
        print(f"❌ 错误: 重启脚本不存在: {RESTART_SCRIPT}")
        sys.exit(1)
    
    # 确保重启脚本有执行权限
    os.chmod(RESTART_SCRIPT, 0o755)
    
    # 创建事件处理器和观察者
    event_handler = RestartHandler()
    observer = Observer()
    
    # 监控项目根目录
    observer.schedule(event_handler, str(PROJECT_ROOT), recursive=True)
    
    # 启动监控
    observer.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n正在停止监控...")
        observer.stop()
    
    observer.join()
    print("监控已停止")


if __name__ == "__main__":
    main()
