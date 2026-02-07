# macOS 打包实施计划

## 项目概述

DouyinLiveRecorder 是一个支持 40+ 平台的直播录制工具，基于 Python 开发。本计划旨在创建一个独立的 macOS 应用包，用户无需手动安装依赖即可使用。

## 技术要求

- **Python 版本**: 3.10+
- **关键依赖**: FFmpeg（视频录制）、Node.js（JavaScript 加密脚本执行）
- **架构支持**: Intel (x86_64) 和 Apple Silicon (arm64)
- **用户体验**: 双击运行，配置文件可编辑

## 打包工具选择

### 推荐方案：PyInstaller

**选择理由**：
1. 成熟稳定，社区活跃
2. 支持打包外部二进制文件（FFmpeg、Node.js）
3. 支持 Universal2 二进制（同时支持 Intel 和 Apple Silicon）
4. 对复杂依赖处理良好
5. 丰富的文档和案例

**替代方案对比**：
- **py2app**: macOS 原生但不够灵活，难以处理外部二进制
- **briefcase**: 现代但不够成熟，对 CLI 应用支持有限

## 实施阶段

### 阶段 1: 环境准备

#### 1.1 安装构建工具

```bash
# 安装 PyInstaller
pip install pyinstaller

# 安装项目依赖
pip install -r requirements.txt

# 安装 DMG 创建工具
brew install create-dmg

# 安装 Node.js（如果未安装）
brew install node
```

#### 1.2 准备外部依赖

**FFmpeg 处理**：
```bash
# 下载 FFmpeg 静态编译版本
# Intel 版本
wget https://evermeet.cx/ffmpeg/ffmpeg-6.0.zip -O ffmpeg-x86_64.zip
unzip ffmpeg-x86_64.zip -d build/ffmpeg-x86_64/

# Apple Silicon 版本
wget https://evermeet.cx/ffmpeg/ffmpeg-6.0-arm64.zip -O ffmpeg-arm64.zip
unzip ffmpeg-arm64.zip -d build/ffmpeg-arm64/

# 创建 Universal Binary
lipo -create build/ffmpeg-x86_64/ffmpeg build/ffmpeg-arm64/ffmpeg \
     -output build/ffmpeg-universal
```

**Node.js 处理**：
```bash
# 方案 A: 使用系统 Node.js（推荐）
# 在 spec 文件中添加 Node.js 路径检测

# 方案 B: 打包 Node.js 二进制
# 下载 Node.js 独立版本并打包进应用
```

### 阶段 2: PyInstaller 配置

#### 2.1 创建 PyInstaller Spec 文件

创建 `DouyinLiveRecorder.spec`:

```python
# -*- mode: python ; coding: utf-8 -*-
import os
import sys
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

block_cipher = None

# 收集所有数据文件
datas = [
    ('config/config.ini', 'config'),
    ('config/URL_config.ini', 'config'),
    ('src/javascript/*.js', 'src/javascript'),
    ('index.html', '.'),
]

# 收集隐藏导入
hiddenimports = [
    'execjs',
    'httpx',
    'loguru',
    'Crypto',
    'Crypto.Cipher',
    'Crypto.Cipher.AES',
]

# 添加 FFmpeg 二进制
binaries = [
    ('build/ffmpeg-universal', '.'),
]

# 如果打包 Node.js（可选）
# binaries.append(('/usr/local/bin/node', '.'))

a = Analysis(
    ['main.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='DouyinLiveRecorder',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,  # 保留终端输出
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch='universal2',  # Universal Binary
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='DouyinLiveRecorder',
)

app = BUNDLE(
    coll,
    name='DouyinLiveRecorder.app',
    icon=None,  # 可选：添加应用图标
    bundle_identifier='com.ihmily.douyinliverecorder',
    info_plist={
        'NSPrincipalClass': 'NSApplication',
        'NSHighResolutionCapable': 'True',
        'CFBundleShortVersionString': '4.0.7',
        'CFBundleVersion': '4.0.7',
        'NSHumanReadableCopyright': 'Copyright © 2023-2025 Hmily',
    },
)
```

#### 2.2 处理 PyExecJS 和 Node.js

创建运行时钩子 `hooks/runtime_hook_execjs.py`:

```python
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
```

在 spec 文件中添加：
```python
runtime_hooks=['hooks/runtime_hook_execjs.py']
```

#### 2.3 处理配置文件的可编辑性

创建启动脚本 `launcher.py`:

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
启动器：确保配置文件在用户可访问的位置
"""
import os
import sys
import shutil
from pathlib import Path

def get_config_dir():
    """获取配置文件目录"""
    # macOS 应用支持目录
    home = Path.home()
    config_dir = home / 'Library' / 'Application Support' / 'DouyinLiveRecorder'
    config_dir.mkdir(parents=True, exist_ok=True)
    return config_dir

def ensure_config_files():
    """确保配置文件存在"""
    config_dir = get_config_dir()

    # 获取打包资源路径
    if hasattr(sys, '_MEIPASS'):
        bundle_dir = Path(sys._MEIPASS)
    else:
        bundle_dir = Path(__file__).parent

    # 复制默认配置文件（如果不存在）
    config_files = [
        'config/config.ini',
        'config/URL_config.ini',
    ]

    for config_file in config_files:
        src = bundle_dir / config_file
        dst = config_dir / Path(config_file).name

        if not dst.exists() and src.exists():
            shutil.copy2(src, dst)
            print(f"已创建配置文件: {dst}")

    return config_dir

def main():
    """主函数"""
    # 确保配置文件存在
    config_dir = ensure_config_files()

    # 修改工作目录
    os.chdir(config_dir.parent)

    # 设置配置文件路径
    os.environ['CONFIG_DIR'] = str(config_dir)

    # 导入并运行主程序
    if hasattr(sys, '_MEIPASS'):
        sys.path.insert(0, sys._MEIPASS)

    import main as app_main
    app_main.main()

if __name__ == '__main__':
    main()
```

**注意**: 需要修改 `main.py` 以支持自定义配置路径：

```python
# 在 main.py 开头添加
config_dir = os.environ.get('CONFIG_DIR', script_path)
config_file = f'{config_dir}/config.ini'
url_config_file = f'{config_dir}/URL_config.ini'
```

### 阶段 3: 构建和测试

#### 3.1 创建构建脚本

创建 `build_macos.sh`:

```bash
#!/bin/bash
set -e

echo "=== DouyinLiveRecorder macOS 打包脚本 ==="

# 清理旧构建
echo "清理旧构建..."
rm -rf build dist

# 准备 FFmpeg
echo "准备 FFmpeg..."
mkdir -p build
if [ ! -f "build/ffmpeg-universal" ]; then
    echo "请先下载并创建 FFmpeg Universal Binary"
    echo "参考文档中的 '阶段 1.2: 准备外部依赖'"
    exit 1
fi

# 构建应用
echo "开始构建..."
pyinstaller DouyinLiveRecorder.spec

# 验证构建
echo "验证构建..."
if [ -d "dist/DouyinLiveRecorder.app" ]; then
    echo "✓ 应用构建成功"

    # 检查架构
    echo "检查架构支持..."
    lipo -info dist/DouyinLiveRecorder.app/Contents/MacOS/DouyinLiveRecorder

    # 检查 FFmpeg
    if [ -f "dist/DouyinLiveRecorder.app/Contents/MacOS/ffmpeg-universal" ]; then
        echo "✓ FFmpeg 已打包"
    else
        echo "✗ FFmpeg 未找到"
    fi
else
    echo "✗ 构建失败"
    exit 1
fi

echo "=== 构建完成 ==="
echo "应用位置: dist/DouyinLiveRecorder.app"
```

#### 3.2 测试清单

**基础功能测试**：
- [ ] 应用可以双击启动
- [ ] 终端输出正常显示
- [ ] 配置文件可以找到并读取
- [ ] FFmpeg 可以正常调用
- [ ] Node.js 可以执行 JavaScript 脚本

**平台测试**：
- [ ] Intel Mac 上运行正常
- [ ] Apple Silicon Mac 上运行正常
- [ ] 至少测试 3 个不同平台的直播录制（抖音、B站、快手）

**配置测试**：
- [ ] 修改 config.ini 后重启生效
- [ ] 添加 URL 到 URL_config.ini 后生效
- [ ] 录制文件保存到正确位置

**依赖测试**：
```bash
# 测试 FFmpeg
./dist/DouyinLiveRecorder.app/Contents/MacOS/ffmpeg-universal -version

# 测试 Node.js（如果打包）
./dist/DouyinLiveRecorder.app/Contents/MacOS/node --version

# 测试应用启动
open dist/DouyinLiveRecorder.app
```

### 阶段 4: 创建分发包

#### 4.1 创建 DMG 安装包

创建 `create_dmg.sh`:

```bash
#!/bin/bash
set -e

APP_NAME="DouyinLiveRecorder"
VERSION="4.0.7"
DMG_NAME="${APP_NAME}-${VERSION}-macOS"

echo "=== 创建 DMG 安装包 ==="

# 检查应用是否存在
if [ ! -d "dist/${APP_NAME}.app" ]; then
    echo "错误: 应用未找到，请先运行 build_macos.sh"
    exit 1
fi

# 创建临时目录
mkdir -p dist/dmg
cp -r "dist/${APP_NAME}.app" dist/dmg/

# 创建 README
cat > dist/dmg/README.txt << EOF
DouyinLiveRecorder v${VERSION}

安装说明：
1. 将 ${APP_NAME}.app 拖到应用程序文件夹
2. 首次运行时，右键点击应用选择"打开"（绕过 Gatekeeper）
3. 配置文件位置：~/Library/Application Support/DouyinLiveRecorder/

使用说明：
1. 编辑配置文件 config.ini 设置录制参数
2. 在 URL_config.ini 中添加直播间地址（一行一个）
3. 双击运行应用开始监控和录制

注意事项：
- 首次运行需要安装 Node.js: brew install node
- 录制海外平台需要配置代理
- 推荐使用 ts 格式录制以防止文件损坏

项目地址：https://github.com/ihmily/DouyinLiveRecorder
EOF

# 创建 DMG
create-dmg \
    --volname "${APP_NAME}" \
    --volicon "icon.icns" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 200 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 600 185 \
    "dist/${DMG_NAME}.dmg" \
    "dist/dmg/"

# 清理
rm -rf dist/dmg

echo "=== DMG 创建完成 ==="
echo "文件位置: dist/${DMG_NAME}.dmg"
```

#### 4.2 代码签名（可选但推荐）

**前提条件**：
- Apple Developer 账号
- 开发者证书已安装

```bash
#!/bin/bash
# sign_app.sh

APP_PATH="dist/DouyinLiveRecorder.app"
IDENTITY="Developer ID Application: Your Name (TEAM_ID)"

echo "=== 代码签名 ==="

# 签名所有二进制文件
find "$APP_PATH" -type f \( -name "*.so" -o -name "*.dylib" \) -exec codesign --force --sign "$IDENTITY" {} \;

# 签名 FFmpeg
codesign --force --sign "$IDENTITY" "$APP_PATH/Contents/MacOS/ffmpeg-universal"

# 签名应用
codesign --force --deep --sign "$IDENTITY" "$APP_PATH"

# 验证签名
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "=== 签名完成 ==="
```

#### 4.3 公证（Notarization）

```bash
#!/bin/bash
# notarize_app.sh

DMG_PATH="dist/DouyinLiveRecorder-4.0.7-macOS.dmg"
APPLE_ID="your@email.com"
TEAM_ID="YOUR_TEAM_ID"
APP_PASSWORD="app-specific-password"

echo "=== 公证应用 ==="

# 上传公证
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

# 装订公证票据
xcrun stapler staple "$DMG_PATH"

echo "=== 公证完成 ==="
```

### 阶段 5: 文档和发布

#### 5.1 创建安装文档

创建 `docs/INSTALL_MACOS.md`:

```markdown
# macOS 安装指南

## 系统要求

- macOS 10.15 (Catalina) 或更高版本
- Intel 或 Apple Silicon (M1/M2) 处理器
- 至少 2GB 可用磁盘空间
- Node.js 14+ （首次运行时会提示安装）

## 安装步骤

### 方式 1: DMG 安装（推荐）

1. 下载 `DouyinLiveRecorder-x.x.x-macOS.dmg`
2. 双击打开 DMG 文件
3. 将 `DouyinLiveRecorder.app` 拖到应用程序文件夹
4. 首次运行：右键点击应用 → 选择"打开"

### 方式 2: 直接使用 .app

1. 下载 `DouyinLiveRecorder.app.zip`
2. 解压缩
3. 右键点击 → 选择"打开"

## 首次运行

1. 应用会自动创建配置文件目录：
   ```
   ~/Library/Application Support/DouyinLiveRecorder/
   ```

2. 安装 Node.js（如果未安装）：
   ```bash
   brew install node
   ```

3. 编辑配置文件：
   ```bash
   open ~/Library/Application\ Support/DouyinLiveRecorder/
   ```

## 配置说明

### config.ini
- 设置录制格式、画质、代理等参数
- 配置推送通知（钉钉、微信、Telegram 等）
- 添加平台 Cookie（抖音必填）

### URL_config.ini
- 添加要录制的直播间地址（一行一个）
- 使用 `#` 注释暂时不录制的地址
- 可以指定画质：`超清,https://live.douyin.com/xxxxx`

## 常见问题

### 应用无法打开
- 右键点击应用 → 选择"打开"
- 或在系统偏好设置 → 安全性与隐私 → 点击"仍要打开"

### Node.js 未找到
```bash
# 安装 Node.js
brew install node

# 验证安装
node --version
```

### 录制文件位置
默认保存在：
```
~/Library/Application Support/DouyinLiveRecorder/downloads/
```

可在 config.ini 中修改 `直播保存路径`

### 代理设置
录制海外平台（TikTok、YouTube 等）需要配置代理：
1. 编辑 config.ini
2. 设置 `是否使用代理ip(是/否) = 是`
3. 填写 `代理地址 = 127.0.0.1:7890`

## 卸载

1. 删除应用：
   ```bash
   rm -rf /Applications/DouyinLiveRecorder.app
   ```

2. 删除配置和录制文件：
   ```bash
   rm -rf ~/Library/Application\ Support/DouyinLiveRecorder
   ```

## 技术支持

- GitHub: https://github.com/ihmily/DouyinLiveRecorder
- Issues: https://github.com/ihmily/DouyinLiveRecorder/issues
```

#### 5.2 更新 README.md

在 README.md 中添加 macOS 安装部分：

```markdown
## 🍎 macOS 安装

### 下载安装包

前往 [Releases](https://github.com/ihmily/DouyinLiveRecorder/releases) 下载最新的 macOS 版本：
- `DouyinLiveRecorder-x.x.x-macOS.dmg` - DMG 安装包（推荐）
- `DouyinLiveRecorder.app.zip` - 独立应用包

### 快速开始

1. 安装应用后，配置文件位于：
   ```
   ~/Library/Application Support/DouyinLiveRecorder/
   ```

2. 编辑 `config.ini` 和 `URL_config.ini`

3. 双击运行应用

详细说明请查看 [macOS 安装指南](docs/INSTALL_MACOS.md)
```

#### 5.3 发布清单

**发布前检查**：
- [ ] 版本号已更新（main.py, spec 文件）
- [ ] 在 Intel 和 Apple Silicon Mac 上测试通过
- [ ] 文档已更新（README.md, INSTALL_MACOS.md）
- [ ] CHANGELOG 已更新
- [ ] 代码已签名和公证（如果有证书）

**发布文件**：
1. `DouyinLiveRecorder-4.0.7-macOS.dmg` - DMG 安装包
2. `DouyinLiveRecorder-4.0.7-macOS.app.zip` - 独立应用包
3. `DouyinLiveRecorder-4.0.7-macOS-universal.zip` - Universal Binary 压缩包

**GitHub Release 说明模板**：
```markdown
## DouyinLiveRecorder v4.0.7 - macOS 版本

### 新增
- ✨ 首次发布 macOS 原生应用包
- 🎯 支持 Intel 和 Apple Silicon (M1/M2) 架构
- 📦 内置 FFmpeg，无需手动安装
- ⚙️ 配置文件自动管理

### 安装方式

**DMG 安装包（推荐）**：
1. 下载 `DouyinLiveRecorder-4.0.7-macOS.dmg`
2. 双击打开，拖到应用程序文件夹
3. 右键点击应用选择"打开"

**独立应用包**：
1. 下载 `DouyinLiveRecorder-4.0.7-macOS.app.zip`
2. 解压后右键点击应用选择"打开"

### 系统要求
- macOS 10.15+ (Catalina 或更高)
- Node.js 14+ (首次运行会提示安装)

### 注意事项
- 首次运行需要右键点击选择"打开"以绕过 Gatekeeper
- 配置文件位于：`~/Library/Application Support/DouyinLiveRecorder/`
- 详细说明请查看 [macOS 安装指南](docs/INSTALL_MACOS.md)

### 下载
- [DouyinLiveRecorder-4.0.7-macOS.dmg](链接)
- [DouyinLiveRecorder-4.0.7-macOS.app.zip](链接)
```

## 风险评估

### 高风险

1. **PyExecJS 和 Node.js 集成**
   - **风险**: PyExecJS 依赖系统 Node.js，打包后可能找不到
   - **缓解**:
     - 方案 A: 在启动时检测并提示用户安装 Node.js
     - 方案 B: 打包 Node.js 二进制到应用中
     - 方案 C: 使用运行时钩子动态查找 Node.js

2. **FFmpeg 架构兼容性**
   - **风险**: Intel 和 Apple Silicon 需要不同的 FFmpeg 二进制
   - **缓解**: 使用 `lipo` 创建 Universal Binary

### 中风险

1. **配置文件访问**
   - **风险**: 打包后配置文件在 .app 内部，用户难以编辑
   - **缓解**: 使用启动器将配置文件复制到用户目录

2. **代码签名和公证**
   - **风险**: 未签名应用会被 Gatekeeper 阻止
   - **缓解**:
     - 提供详细的"右键打开"说明
     - 建议项目获取开发者证书进行签名

3. **应用体积**
   - **风险**: 打包后体积可能超过 200MB
   - **缓解**:
     - 使用 UPX 压缩
     - 排除不必要的依赖
     - 考虑分离 FFmpeg 为可选下载

### 低风险

1. **Python 版本兼容性**
   - **风险**: 不同 macOS 版本的 Python 兼容性
   - **缓解**: PyInstaller 会打包完整的 Python 运行时

2. **依赖库更新**
   - **风险**: 依赖库更新可能导致打包失败
   - **缓解**: 锁定依赖版本，使用 requirements.txt

## 复杂度评估

- **整体复杂度**: 中等
- **预计工作量**:
  - 环境准备和依赖处理: 4-6 小时
  - PyInstaller 配置和调试: 6-8 小时
  - 测试和修复: 4-6 小时
  - 文档编写: 2-3 小时
  - **总计**: 16-23 小时

## 后续优化

1. **自动更新机制**
   - 集成 Sparkle 框架实现应用内更新
   - 或使用 GitHub Releases API 检查更新

2. **GUI 界面**
   - 考虑使用 PyQt 或 Tkinter 创建图形界面
   - 提供更友好的配置编辑器

3. **Homebrew 分发**
   - 创建 Homebrew Cask 配方
   - 允许用户通过 `brew install --cask douyin-live-recorder` 安装

4. **性能优化**
   - 使用 PyInstaller 的 `--onefile` 选项创建单文件应用
   - 优化启动时间

## 参考资源

- [PyInstaller 官方文档](https://pyinstaller.org/en/stable/)
- [PyInstaller macOS 打包指南](https://pyinstaller.org/en/stable/usage.html#macos-specific-options)
- [Apple 代码签名指南](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [create-dmg 工具](https://github.com/create-dmg/create-dmg)
- [PyExecJS 文档](https://github.com/doloopwhile/PyExecJS)

## 总结

本计划提供了完整的 macOS 打包方案，使用 PyInstaller 作为主要工具，解决了 FFmpeg 和 Node.js 依赖问题，并提供了配置文件管理、代码签名、DMG 创建等完整流程。

**关键成功因素**：
1. 正确处理 PyExecJS 和 Node.js 依赖
2. 创建 Universal Binary 支持两种架构
3. 配置文件放在用户可访问位置
4. 提供清晰的安装和使用文档

**建议实施顺序**：
1. 先完成基础打包（阶段 1-3）
2. 在本地测试验证
3. 再进行 DMG 创建和签名（阶段 4）
4. 最后完善文档和发布（阶段 5）
