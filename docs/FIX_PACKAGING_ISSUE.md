# 打包后重启问题修复指南

## 问题诊断

打包后应用一直重启的**根本原因**：

### 🔴 核心问题

1. **配置文件路径错误** - 使用 `sys.argv[0]` 无法在打包后正确定位资源
2. **日志文件路径不可写** - 尝试在应用包内（只读）写入日志
3. **没有检测打包状态** - 代码中完全没有使用 `sys._MEIPASS` 或 `sys.frozen`

### 打包后的路径问题

**开发环境：**
```
/Users/xxx/DouyinLiveRecorder/
├── main.py
├── config/
│   ├── config.ini
│   └── URL_config.ini
├── logs/
└── downloads/
```

**打包后（macOS）：**
```
DouyinLiveRecorder.app/
└── Contents/
    └── MacOS/
        ├── DouyinLiveRecorder (可执行文件)
        └── _internal/           (PyInstaller 临时解压目录 = sys._MEIPASS)
            ├── config/
            ├── src/javascript/
            └── ffmpeg-universal
```

**问题：**
- `sys.argv[0]` → `/Applications/DouyinLiveRecorder.app/Contents/MacOS/DouyinLiveRecorder`
- 代码尝试访问 `/Applications/DouyinLiveRecorder.app/Contents/MacOS/config/config.ini` ❌
- 实际位置在 `sys._MEIPASS/config/config.ini` ✅
- 且配置文件应该在用户目录（可写），不是应用包内（只读）

---

## 修复方案

### 步骤 1：已创建路径管理模块

✅ 已创建 `src/paths.py`，提供统一的路径管理：

```python
from src import paths

# 资源文件（只读，打包在应用内）
paths.BUNDLE_DIR          # 开发环境=项目根目录，打包后=sys._MEIPASS
paths.JS_SCRIPT_PATH      # JavaScript 文件目录
paths.FFMPEG_PATH         # FFmpeg 可执行文件

# 用户数据（可写，在用户目录）
paths.USER_DATA_DIR       # macOS: ~/Library/Application Support/DouyinLiveRecorder
paths.CONFIG_FILE         # 配置文件
paths.URL_CONFIG_FILE     # URL 配置文件
paths.LOG_DIR             # 日志目录
paths.DOWNLOAD_DIR        # 下载目录
paths.BACKUP_DIR          # 备份目录

# 首次运行初始化
paths.init_user_config()  # 复制默认配置到用户目录
```

### 步骤 2：修改 main.py

**位置：** `main.py:30-31` 添加导入

```python
from src import spider, stream
from src.proxy import ProxyDetector
from src.utils import logger
from src import utils
from src import paths  # ← 添加这行
from msg_push import (
    dingtalk, xizhi, tg_bot, send_email, bark, ntfy, pushplus
)
```

**位置：** `main.py:67-76` 替配置

```python
# 删除这些行：
# script_path = os.path.split(os.path.realpath(sys.argv[0]))[0]
# config_file = f'{script_path}/config/config.ini'
# url_config_file = f'{script_path}/config/URL_config.ini'
# backup_dir = f'{script_path}/backup_config'
# default_path = f'{script_path}/downloads'
# os.makedirs(default_path, exist_ok=True)

# 替换为：
# 初始化用户配置（首次运行时复制默认配置）
paths.init_user_config()

# 使用统一的路径管理
config_file = str(paths.CONFIG_FILE)
url_config_file = str(paths.URL_CONFIG_FILE)
backup_dir = str(paths.BACKUP_DIR)
default_path = str(paths.DOWNLOAD_DIR)
```

**位置：** 搜索所有 `script_path` 的使用，替换为对应的 `paths.*`

```bash
# 在 main.py 中搜索
grep -n "script_path" main.py
```

### 步骤 3：修改 src/__init__.py

**当前代码：**
```python
execute_dir = os.path.split(os.path.realpath(sys.argv[0]))[0]
node_execute_dir = Path(execute_dir) / 'node'
```

**修改为：**
```python
from src.paths import BUNDLE_DIR, NODE_PATH

node_execute_dir = NODE_PATH
```

### 步骤 4：修改 ffmpeg_install.py

**当前代码：**
```python
execute_dir = os.path.split(os.path.realpath(sys.argv[0]))[0]
ffmpeg_path = os.path.join(execute_dir, 'ffmpeg')
```

**修改为：**
```python
from src.paths import FFMPEG_PATH, BUNDLE_DIR
import sys

if getattr(sys, 'frozen', False):
    # 打包后
    ffmpeg_path = str(FFMPEG_PATH.parent)
else:
    # 开发环境
    execute_dir = os.path.split(os.path.realpath(sys.argv[0]))[0]
    ffmpeg_path = os.path.join(execute_dir, 'ffmpeg')
```

### 步骤 5：修改 i18n.py

**当前代码：**
```python
execute_dir = os.path.split(os.path.realpath(sys.argv[0]))[0]
if os.path.exists(Path(execute_dir) / '_internal/i18n'):
    locale_path = Path(execute_dir) / '_internal/i18n'
else:
    locale_path = Path(execute_dir) / 'i18n'
```

**修改为：**
```python
from src.paths import BUNDLE_DIR, I18N_PATH

locale_path = I18N_PATH
```

### 步骤 6：修改 src/initializer.py

**当前代码：**
```python
execute_dir = os.path.split(os.path.realpath(sys.argv[0]))[0]
```

**修改为：**
```python
from src.paths import BUNDLE_DIR, NODE_PATH

execute_dir = str(BUNDLE_DIR)
```

### 步骤 7：✅ 已修改 src/logger.py

已经修改完成，使用 `paths.LOG_DIR`。

---

## 修改后的打包流程

### 1. 更新 DouyinLiveRecorder.spec

确保打包默认配置文件：

```python
datas = [
    ('config/config.ini', 'config'),           # 默认配置（只读）
    ('config/URL_config.ini', 'config'),       # 默认 URL 配置（只读）
    ('src/javascript', 'src/javascript'),      # JS 文件
    ('index.html', '.'),
    ('i18n', 'i18n'),                          # 国际化文件
]
```

### 2. 首次运行流程

```
1. 用户启动应用
2. paths.init_user_config() 检查用户配置
3. 如果不存在，从 sys._MEIPASS/config/ 复制到用户目录
4. 后续读写都在用户目录进行
```

### 3. 用户数据位置

**macOS:**
```
~/Library/Application Support/DouyinLiveRecorder/
├── config/
│   ├── config.ini
│   └── URL_config.ini
├── logs/
│   ├── streamget.log
│   └── PlayURL.log
├── downloads/
└── backup_config/
```

**Windows:**
```
%APPDATA%\DouyinLiveRecorder\
├── config\
├── logs\
├── downloads\
└── backup_config\
```

**Linux:**
```
~/.DouyinLiveRecorder/
├── config/
├── logs/
├── downloads/
└── backup_config/
```

---

## 验证修复

### 1. 开发环境测试

```bash
# 运行应用，确保路径正确
python main.py

# 检查路径
python -c "from src import paths; print(paths.CONFIG_FILE)"
```

### 2. 打包测试

```bash
# 打包
./build_macos.sh

# 运行打包后的应用
open dist/DouyinLiveRecorder.app

# 检查用户数据目录是否创建
ls -la ~/Library/Application\ Support/DouyinLiveRecorder/
```

### 3. 日志检查

打包后运行，检查日志：

```bash
# 查看日志（应该在用户目录，不是应用包内）
tail -f ~/Library/Application\ Support/DouyinLiveRecorder/logs/streamget.log
```

---

## 关键文件修改清单

| 文件 | 状态 | 修改内容 |
|------|------|----------|
| src/paths.py | ✅ 已创建 | 统一路径管理模块 |
| src/logger.py | ✅ 已修改 | 使用 paths.LOG_DIR |
| main.py | ⚠️ 待修改 | 替换 script_path 为 paths.* |
| src/__init__.py | ⚠️ 待修改 | 使用 paths.NODE_PATH |
| ffmpeg_install.py | ⚠️ 待修改 | 使用 paths.FFMPEG_PATH |
| i18n.py | ⚠️ 待修改 | 使用 paths.I18N_PATH |
| src/initializer.py | ⚠️ 待修改 | 使用 paths.BUNDLE_DIR |

---

## 快速修复脚本

创建 `fix_paths.py` 自动替换：

```python
#!/usr/bin/env python3
"""自动修复路径引用"""
import re
from pathlib import Path

def fix_file(file_path, replacements):
    """替换文件中的内容"""
    content = Path(file_path).read_text(encoding='utf-8')

    for old, new in replacements:
        content = content.replace(old, new)

    Path(file_path).write_text(content, encoding='utf-8')
    print(f"✓ 已修复: {file_path}")

# main.py 修复
fix_file('main.py', [
    (
        "script_path = os.path.split(os.path.realpath(sys.argv[0]))[0]\n"
        "config_file = f'{script_path}/config/config.ini'\n"
        "url_config_file = f'{script_path}/config/URL_config.ini'\n"
        "backup_dir = f'{script_path}/backup_config'\n"
        "text_encoding = 'utf-8-sig'\n"
        "rstr = r\"[\/\\\:\*\？?\\\"\<\>\|&#.。,， ~！· ]\"\n"
        "default_path = f'{script_path}/downloads'\n"
        "os.makedirs(default_path, exist_ok=True)",

        "# 初始化用户配置（首次运行时复制默认配置）\n"
        "paths.init_user_config()\n\n"
        "# 使用统一的路径管理\n"
        "config_file = str(paths.CONFIG_FILE)\n"
        "url_config_file = str(paths.URL_CONFIG_FILE)\n"
        "backup_dir = str(paths.BACKUP_DIR)\n"
        "text_encoding = 'utf-8-sig'\n"
        "rstr = r\"[\/\\\:\*\？?\\\"\<\>\|&#.。,， ~！· ]\"\n"
        "default_path = str(paths.DOWNLOAD_DIR)"
    ),
    (
        "from src import utils\n",
        "from src import utils\nfrom src import paths\n"
    )
])

print("\n=== 修复完成 ===")
print("请手动检查以下文件：")
print("- src/__init__.py")
print("- ffmpeg_install.py")
print("- i18n.py")
print("- src/initializer.py")
```

---

## 常见问题

### Q1: 打包后找不到配置文件

**原因：** 配置文件在 `sys._MEIPASS`，但代码用 `sys.argv[0]` 查找

**解决：** 使用 `paths.CONFIG_FILE`，首次运行会自动复制到用户目录

### Q2: 日志文件无法写入

**原因：** 应用包内目录是只读的

**解决：** 使用 `paths.LOG_DIR`，指向用户可写目录

### Q3: JavaScript 文件找不到

**原因：** JS 文件在 `sys._MEIPASS/src/javascript/`

**解决：** 使用 `paths.JS_SCRIPT_PATH`

### Q4: FFmpeg 无法执行

**原因：** FFmpeg 路径错误或权限问题

**解决：**
1. 使用 `paths.FFMPEG_PATH`
2. 确保 spec 文件正确打包 FFmpeg
3. 检查可执行权限：`chmod +x dist/DouyinLiveRecorder.app/Contents/MacOS/ffmpeg-universal`

---

## 总结

**修复前：**
- ❌ 所有路径基于 `sys.argv[0]`
- ❌ 没有区分只读资源和可写数据
- ❌ 没有检测打包状态

**修复后：**
- ✅ 使用 `sys._MEIPASS` 访问打包资源
- ✅ 用户数据存储在系统标准位置
- ✅ 开发环境和打包环境都能正常运行
- ✅ 首次运行自动初始化配置

**关键改进：**
1. 创建统一的 `src/paths.py` 模块
2. 所有文件使用 `paths.*` 而不是 `sys.argv[0]`
3. 配置文件存储在用户目录，应用包内只保留默认配置
4. 日志和下载文件都在用户可写目录
