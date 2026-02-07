import os
import sys

# 确保 Node.js 可用
def find_nodejs():
    """查找系统中的 Node.js"""
    possible_paths = [
        '/usr/local/bin/node',
        '/opt/homebrew/bin/node',
        '/usr/bin/node',
    ]

    for path in possible_paths:
        if os.path.exists(path):
            return path

    # 如果打包了 Node.js
    if hasattr(sys, '_MEIPASS'):
        bundled_node = os.path.join(sys._MEIPASS, 'node')
        if os.path.exists(bundled_node):
            return bundled_node

    return None

# 设置 Node.js 路径
nodejs_path = find_nodejs()
if nodejs_path:
    os.environ['EXECJS_RUNTIME'] = 'Node'
    # PyExecJS 会自动查找 Node.js
