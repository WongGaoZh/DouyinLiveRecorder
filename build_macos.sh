#!/bin/bash
set -e

echo "=== DouyinLiveRecorder macOS 打包脚本 ==="

# 清理旧构建
echo "清理旧构建..."
rm -rf build/DouyinLiveRecorder dist

# 检查 FFmpeg
echo "检查 FFmpeg..."
if [ ! -f "build/ffmpeg-universal" ]; then
    echo "✗ FFmpeg 未找到，正在复制..."
    mkdir -p build
    cp /opt/homebrew/bin/ffmpeg build/ffmpeg-universal
    chmod +x build/ffmpeg-universal
fi

# 激活虚拟环境
echo "激活虚拟环境..."
source .venv/bin/activate

# 构建应用
echo "开始构建..."
pyinstaller DouyinLiveRecorder.spec --clean

# 验证构建
echo "验证构建..."
if [ -d "dist/DouyinLiveRecorder.app" ]; then
    echo "✓ 应用构建成功"

    # 检查架构
    echo "检查架构支持..."
    file dist/DouyinLiveRecorder.app/Contents/MacOS/DouyinLiveRecorder

    # 检查 FFmpeg
    if [ -f "dist/DouyinLiveRecorder.app/Contents/MacOS/ffmpeg-universal" ]; then
        echo "✓ FFmpeg 已打包"
        file dist/DouyinLiveRecorder.app/Contents/MacOS/ffmpeg-universal
    else
        echo "✗ FFmpeg 未找到"
    fi

    # 检查配置文件
    if [ -d "dist/DouyinLiveRecorder.app/Contents/MacOS/config" ]; then
        echo "✓ 配置文件已打包"
        ls -la dist/DouyinLiveRecorder.app/Contents/MacOS/config/
    else
        echo "✗ 配置文件未找到"
    fi

    # 检查 JavaScript 文件
    if [ -d "dist/DouyinLiveRecorder.app/Contents/MacOS/src/javascript" ]; then
        echo "✓ JavaScript 文件已打包"
        ls -la dist/DouyinLiveRecorder.app/Contents/MacOS/src/javascript/
    else
        echo "✗ JavaScript 文件未找到"
    fi
else
    echo "✗ 构建失败"
    exit 1
fi

echo ""
echo "=== 构建完成 ==="
echo "应用位置: dist/DouyinLiveRecorder.app"
echo ""
echo "测试运行："
echo "  open dist/DouyinLiveRecorder.app"
echo ""
echo "创建 DMG："
echo "  ./create_dmg.sh"
