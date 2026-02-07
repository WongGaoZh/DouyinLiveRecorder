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
echo "准备 DMG 内容..."
mkdir -p dist/dmg
cp -r "dist/${APP_NAME}.app" dist/dmg/

# 创建 README
cat > dist/dmg/README.txt << 'EOF'
DouyinLiveRecorder v4.0.7

安装说明：
1. 将 DouyinLiveRecorder.app 拖到应用程序文件夹
2. 首次运行时，右键点击应用选择"打开"（绕过 Gatekeeper）
3. 配置文件位置：应用包内的 config 目录

使用说明：
1. 右键点击应用 -> 显示包内容 -> Contents -> Resources -> config
2. 编辑 config.ini 设置录制参数
3. 在 URL_config.ini 中添加直播间地址（一行一个）
4. 双击运行应用开始监控和录制

注意事项：
- 首次运行需要安装 Node.js: brew install node
- 录制海外平台需要配置代理
- 推荐使用 ts 格式录制以防止文件损坏
- 录制文件默认保存在：应用包同级目录的 downloads 文件夹

项目地址：https://github.com/ihmily/DouyinLiveRecorder
EOF

# 创建 DMG
echo "创建 DMG 文件..."
create-dmg \
    --volname "${APP_NAME}" \
    --window-pos 200 120 \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 200 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 600 185 \
    "dist/${DMG_NAME}.dmg" \
    "dist/dmg/" || true

# 清理
rm -rf dist/dmg

if [ -f "dist/${DMG_NAME}.dmg" ]; then
    echo ""
    echo "=== DMG 创建完成 ==="
    echo "文件位置: dist/${DMG_NAME}.dmg"
    echo "文件大小: $(du -h dist/${DMG_NAME}.dmg | cut -f1)"
    echo ""
    echo "测试 DMG："
    echo "  open dist/${DMG_NAME}.dmg"
else
    echo "✗ DMG 创建失败"
    exit 1
fi
