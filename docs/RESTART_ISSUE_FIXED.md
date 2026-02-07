# 打包后一直重启问题 - 已修复

## 🎯 问题根源

**不是路径问题！** 真正的原因是 `input()` 在没有交互式终端时抛出 `EOFError`。

### 错误日志

```
请输入要录制的主播直播间网址（尽量使用PC网页端的直播间地址）:
Traceback (most recent call last):
  File "main.py", line 1796, in <module>
EOFError: EOF when reading a line
[PYI-96708:ERROR] Failed to execute script 'main' due to unhandled exception!
```

### 崩溃流程

```
1. URL_config.ini 为空
   ↓
2. 程序调用 input() 等待用户输入
   ↓
3. 打包后的应用没有交互式终端（stdin 关闭）
   ↓
4. input() 立即抛出 EOFError
   ↓
5. 程序崩溃退出
   ↓
6. 终端/脚本检测到崩溃 → 自动重启
   ↓
7. 循环往复 → 无限重启
```

---

## ✅ 已修复内容

### 1. 修改 main.py:1786-1801

**修复前：**
```python
if not ini_URL_content.strip():
    input_url = input('请输入要录制的主播直播间网址...\n')
    with open(url_config_file, 'w', encoding=text_encoding) as file:
        file.write(input_url)
```

**修复后：**
```python
if not ini_URL_content.strip():
    # 检查是否有交互式终端（避免打包后 input() 崩溃）
    if sys.stdin and sys.stdin.isatty():
        input_url = input('请输入要录制的主播直播间网址...\n')
        with open(url_config_file, 'w', encoding=text_encoding) as file:
            file.write(input_url)
    else:
        # 打包后或后台运行时，写入默认提示信息
        logger.warning("URL_config.ini 为空，请手动添加直播间 URL")
        with open(url_config_file, 'w', encoding=text_encoding) as file:
            file.write("# DouyinLiveRecorder URL 配置文件\n")
            file.write("# 每行一个直播间 URL，支持以下格式：\n")
            file.write("# 1. 直接 URL：https://live.douyin.com/123456\n")
            file.write("# 2. 指定画质：超清,https://live.douyin.com/123456\n")
            file.write("# 3. 注释行：#https://live.douyin.com/123456（暂时禁用）\n\n")
            file.write("# 请在下方添加你的直播间 URL：\n")
        print("\n" + "="*60)
        print("URL_config.ini 配置文件为空！")
        print(f"请编辑以下文件，添加要录制的直播间 URL：")
        print(f"  {url_config_file}")
        print("="*60 + "\n")
        sys.exit(0)  # 优雅退出，不要崩溃
```

### 2. 关键改进

- ✅ 使用 `sys.stdin.isatty()` 检测是否有交互式终端
- ✅ 打包后自动创建带提示的配置文件
- ✅ 优雅退出而不是崩溃（`sys.exit(0)` 而不是 `EOFError`）
- ✅ 清晰的用户提示信息

---

## 🔍 关于 sys.argv[0] 的澄清

### 实际情况

当运行 `dist/DouyinLiveRecorder/DouyinLiveRecorder` 时：

```python
sys.argv[0] = "/path/to/dist/DouyinLiveRecorder/DouyinLiveRecorder"
script_path = os.path.split(os.path.realpath(sys.argv[0]))[0]
# script_path = "/path/to/dist/DouyinLiveRecorder"  ✅ 正确！

config_file = f'{script_path}/config/config.ini'
# = "/path/to/dist/DouyinLiveRecorder/config/config.ini"  ✅ 正确！
```

### 证据

从 `ls -la dist/DouyinLiveRecorder/` 可以看到：

```
drwxr-xr-x  4 ssa-user  staff  128 Feb  6 18:03 config      ✅ 配置目录存在
drwxr-xr-x  4 ssa-user  staff  128 Feb  6 18:06 logs        ✅ 日志目录存在
drwxr-xr-x  2 ssa-user  staff   64 Feb  6 18:06 downloads   ✅ 下载目录存在
drwxr-xr-x 14 ssa-user  staff  448 Feb  6 18:07 backup_config ✅ 备份目录存在
```

**结论：** 路径处理是正确的，程序成功创建了所有目录。

### PyInstaller 的目录结构

```
dist/DouyinLiveRecorder/
├── DouyinLiveRecorder          # 可执行文件
├── config/                      # 运行时创建的配置（可写）
│   ├── config.ini
│   └── URL_config.ini
├── logs/                        # 运行时创建的日志（可写）
├── downloads/                   # 运行时创建的下载（可写）
├── backup_config/               # 运行时创建的备份（可写）
└── _internal/                   # PyInstaller 打包的资源（只读）
    ├── config/                  # 打包时的默认配置
    ├── src/javascript/          # JS 文件
    └── ffmpeg-universal         # FFmpeg 可执行文件
```

**关键点：**
- `sys.argv[0]` 指向 `dist/DouyinLiveRecorder/DouyinLiveRecorder`
- `script_path` = `dist/DouyinLiveRecorder/`
- 配置文件在 `dist/DouyinLiveRecorder/config/`（可写）✅
- 资源文件在 `dist/DouyinLiveRecorder/_internal/`（只读）✅

---

## 🚀 验证修复

### 1. 重新打包

```bash
./build_macos.sh
```

### 2. 测试运行

```bash
cd dist/DouyinLiveRecorder
./DouyinLiveRecorder
```

**预期行为：**
- 如果 `URL_config.ini` 为空，程序会：
  1. 自动创建带提示的配置文件
  2. 打印清晰的提示信息
  3. 优雅退出（退出码 0）
  4. **不会崩溃，不会重启**

### 3. 添加 URL 后正常运行

编辑 `config/URL_config.ini`：

```ini
# DouyinLiveRecorder URL 配置文件
# 请在下方添加你的直播间 URL：
https://live.douyin.com/123456
```

再次运行：

```bash
./DouyinLiveRecorder
```

程序应该正常启动并开始监控直播间。

---

## 📊 修复前后对比

| 场景 | 修复前 | 修复后 |
|------|--------|--------|
| URL_config.ini 为空 | `EOFError` 崩溃 → 无限重启 | 创建默认配置 → 优雅退出 |
| 开发环境运行 | 正常提示输入 | 正常提示输入 |
| 打包后运行 | 崩溃重启 | 优雅退出并提示 |
| 后台运行 | 崩溃重启 | 优雅退出并提示 |

---

## 🎓 经验教训

### 1. 打包后的应用不能使用 `input()`

**原因：**
- 打包后的应用通常没有交互式终端
- `sys.stdin` 可能是 `None` 或关闭状态
- `input()` 会立即抛出 `EOFError`

**解决方案：**
```python
if sys.stdin and sys.stdin.isatty():
    # 有交互式终端，可以使用 input()
    user_input = input("请输入：")
else:
    # 没有交互式终端，使用其他方式
    logger.warning("请通过配置文件提供输入")
    sys.exit(0)
```

### 2. 配置文件应该有默认内容

**避免空文件导致的问题：**
- 打包时包含默认配置模板
- 首次运行时自动创建带注释的配置文件
- 提供清晰的使用说明

### 3. 错误处理要考虑打包环境

**开发环境 vs 打包环境：**
- 开发环境：有终端、有调试器、可以交互
- 打包环境：无终端、无调试器、不能交互
- 需要针对两种环境提供不同的错误处理策略

---

## 🔧 其他建议

### 1. 添加启动脚本

创建 `start.sh`：

```bash
#!/bin/bash
cd "$(dirname "$0")"

# 检查配置文件
if [ ! -f "config/URL_config.ini" ] || [ ! -s "config/URL_config.ini" ]; then
    echo "错误：config/URL_config.ini 不存在或为空"
    echo "请先编辑配置文件，添加要录制的直播间 URL"
    exit 1
fi

# 启动程序
./DouyinLiveRecorder
```

### 2. 添加配置验证

在程序启动时验证配置：

```python
def validate_config():
    """验证配置文件是否有效"""
    if not os.path.exists(url_config_file):
        return False, "URL_config.ini 不存在"

    with open(url_config_file, 'r', encoding=text_encoding) as f:
        content = f.read().strip()
        # 过滤注释行
        urls = [line.strip() for line in content.split('\n')
                if line.strip() and not line.strip().startswith('#')]

        if not urls:
            return False, "URL_config.ini 中没有有效的 URL"

    return True, "配置有效"

# 在主程序启动前调用
is_valid, message = validate_config()
if not is_valid:
    logger.error(message)
    print(f"\n配置错误：{message}")
    print(f"请编辑 {url_config_file} 文件")
    sys.exit(1)
```

### 3. 添加日志轮转

确保日志不会无限增长：

```python
logger.add(
    LOG_DIR / "streamget.log",
    rotation="10 MB",      # 每 10MB 轮转一次
    retention="7 days",    # 保留 7 天
    compression="zip",     # 压缩旧日志
    ...
)
```

---

## 总结

**问题：** 打包后一直重启
**原因：** `input()` 在无终端环境下抛出 `EOFError`
**修复：** 检测终端状态，优雅处理无终端情况
**状态：** ✅ 已修复

现在重新打包后，程序应该可以正常运行了！
