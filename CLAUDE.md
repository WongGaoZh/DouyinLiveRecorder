# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DouyinLiveRecorder is a multi-platform live stream recording tool that supports 40+ streaming platforms (Douyin, TikTok, YouTube, Kuaishou, Huya, Douyu, Bilibili, etc.). It uses FFmpeg for recording and supports continuous monitoring, automatic recording, quality selection, and live status notifications.

**Key Features:**
- Asynchronous architecture for concurrent stream monitoring
- FFmpeg-based recording with multiple format support (ts, mkv, flv, mp4, mp3, m4a)
- Configurable quality settings per platform
- Push notifications (DingTalk, WeChat, Telegram, Email, Bark, Ntfy, PushPlus)
- Proxy support for overseas platforms
- Cookie-based authentication for platform-specific access

## Development Commands

### Running the Application

```bash
# Standard Python execution
python main.py

# Using uv (recommended for dependency management)
uv run main.py

# Linux systems
python3 main.py
```

### Dependency Management

```bash
# Install dependencies with pip
pip3 install -U pip && pip3 install -r requirements.txt

# Install with uv (auto-manages virtual environment)
uv sync

# Using Chinese mirror (if slow)
pip3 install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
uv sync --index https://pypi.tuna.tsinghua.edu.cn/simple
```

### Virtual Environment Setup

```bash
# Create virtual environment
python -m venv .venv
# or with uv
uv venv

# Activate (Bash)
source .venv/Scripts/activate

# Activate (PowerShell)
.venv\Scripts\activate.ps1

# Activate (Windows CMD)
.venv\Scripts\activate.bat
```

### FFmpeg Installation

FFmpeg is required for recording. On Windows, it's included. For other platforms:

```bash
# CentOS
yum install epel-release && yum install ffmpeg

# Ubuntu
apt update && apt install ffmpeg

# macOS
brew install ffmpeg
```

### Docker Commands

```bash
# Start with docker-compose
docker-compose up

# Start in background
docker-compose up -d

# Build custom image
docker build -t douyin-live-recorder:latest .

# Stop container
docker-compose stop
```

### Testing

```bash
# Run demo to test platform integration
python demo.py

# Test specific platform (edit demo.py to change platform)
# Available platforms: douyin, tiktok, kuaishou, huya, douyu, yy, bilibili, etc.
```

## Architecture

### Core Components

**main.py** - Main orchestrator
- Manages concurrent recording threads
- Monitors live stream status in loops
- Handles configuration loading and updates
- Coordinates FFmpeg recording processes
- Implements error recovery and retry logic

**src/spider.py** - Platform data fetchers (~160KB, largest file)
- Contains async functions for 40+ platforms
- Fetches live room data, stream status, and metadata
- Handles platform-specific API calls and parsing
- Uses httpx for async HTTP requests
- Integrates JavaScript execution via execjs for encrypted platforms

**src/stream.py** - Stream URL extractors
- Converts platform data into recordable stream URLs
- Handles quality selection (原画/超清/高清/标清/流畅)
- Manages m3u8 playlist parsing
- Validates stream availability

**src/room.py** - Room info parsers
- Extracts room IDs from various URL formats
- Handles short URLs and redirects
- Parses user IDs and unique identifiers

**src/ab_sign.py** - Douyin signature generator
- Generates authentication tokens for Douyin API
- Implements anti-bot signature algorithms

**src/utils.py** - Utility functions
- Logger configuration
- File path sanitization (removes emojis, special chars)
- Color output for terminal
- Error decorators

**src/initializer.py** - Environment setup
- Checks and installs Node.js if needed
- Validates system dependencies

**src/proxy.py** - Proxy detection and management
- Tests proxy connectivity
- Manages proxy configuration per platform

**src/http_clients/** - HTTP client wrappers
- `async_http.py` - Async httpx wrapper with retry logic
- `sync_http.py` - Synchronous requests wrapper

**src/javascript/** - JavaScript decryption modules
- Platform-specific encryption/decryption scripts
- Executed via PyExecJS for signature generation

**msg_push.py** - Notification system
- Implements pations to multiple services
- Supports batch notifications

**ffmpeg_install.py** - FFmpeg installer
- Auto-downloads FFmpeg on Windows
- Validates FFmpeg installation

### Configuration Files

**config/config.ini** - Main configuration
- Recording settings (format, quality, path, segmentation)
- Proxy settings and platform-specific proxy list
- Push notification configuration (DingTalk, WeChat, TG, Email, Bark, Ntfy, PushPlus)
- Cookie storage for authenticated platforms
- Custom script execution after recording

**config/URL_config.ini** - Stream URLs to monitor
- One URL per line
- Prefix with `#` to disable monitoring without removing
- Optional quality prefix: `超清,https://live.douyin.com/745964462470`

### Data Flow

1. **Monitoring Loop** (main.py)
   - Reads URLs from `URL_config.ini`
   - Creates monitoring threads based on `同一时间访问网络的线程数`
   - Sleeps for `循环时间(秒)` between checks

2. **Stream Detection** (spider.py)
   - Async function fetches platform-specific API
   - Returns: `{anchor_name, is_live, status, title, record_url, ...}`
   - Handles cookies, proxies, and platform-specific auth

3. **URL Extraction** (stream.py)
   - Converts API response to recordable stream URL
   - Selects quality based on config or per-URL setting
   - Returns final m3u8/flv/rtmp URL

4. **Recording** (main.py)
   - Spawns FFmpeg subprocess with stream URL
   - Saves to `downloads/{platform}/{anchor_name}/`
   - Implements segmentation if `分段录制是否开启 = 是`
   - Auto-converts to mp4 if `录制完成后自动转为mp4格式 = 是`

5. **Notification** (msg_push.py)
   - Sends push when stream starts/ends
   - Supports custom message templates

### Threading Model

- **Main thread**: Configuration management, display updates
- **Monitor threads**: One per URL, checks live status every `循环时间(秒)`
- **Recording threads**: One per active streges FFmpeg process
- **Semaphore control**: `同一时间访问网络的线程数` limits concurrent network requests

### Error Handling

- **Error window tracking**: Monitors error frequency to prevent IP bans
- **Automatic retry**: Failed requests retry with exponential backoff
- **Cookie refresh**: Some platforms auto-refresh cookies on auth failure
- **Graceful shutdown**: Ctrl+C properly terminates FFmpeg and saves recordings

## Platform-Specific Notes

### Douyin (抖音)
- **Requires cookie** in config.ini
- Uses `ab_sign.py` for API signature generation
- Supports dual-screen recording
- Can use room URL, short URL, or user homepage

### TikTok
- **Requires proxy** (configured in `使用代理录制的平台`)
- Cookie optional but recommended for stability

### Overseas Platforms
- Platforms requiring proxy are pre-configured in config.ini
- Add custom platforms to `额外使用代理录制的平台(逗号分隔)`

### Xiaohongshu (小红书)
- Requires share link format: `http://xhslink.com/xpJpfM`
- Cookie required for access

### Taobao/JD
- Requires valid cookie for authentication
- Uses JavaScript signature generation

## Important Patterns

### Async/Await Usage
All platform fetchers in `spider.py` and stream extractorsn `stream.py` are async functions. Use `asyncio.run()` when calling from sync context:

```python
stream_data = asyncio.run(spider.get_douyin_app_stream_data(url, proxy_addr, cookies))
```

### Error Decorator
Use `@trace_error_decorator` on functions that may fail:

```python
from src.utils import trace_error_decorator

@trace_error_decorator
async def get_platform_data(url: str) -> dict:
    # Function will log errors and return None on exception
    pass
```

### File Path Sanitization
Always sanitize filenames to remove special charers and emojis:

```python
import re
rstr = r"[\/\\\:\*\？?\"\<\>\|&#.。,， ~！· ]"
safe_name = re.sub(rstr, "_", raw_name)
```

### Quality Selection
Quality mapping: `{"OD": 0, "BD": 0, "UHD": 1, "HD": 2, "SD": 3, "LD": 4}`
- OD/BD = 原画 (Original)
- UHD = 超清 (Ultra HD)
- HD = 高清 (High Definition)
- SD = 标清 (Standard Definition)
- LD = 流畅 (Low Definition)

## Common Issues

### Recording Stops After 2 Minutes
- Check if platform requires specific FFmpeg parameters
- Verify stream URL is still valid (some platforms rotate URLs)
- Enable segmented recording: `分段录制是否开n### Cannot Access Overseas Platforms
- Ensure proxy is configured: `是否使用代理ip(是/否) = 是`
- Add proxy address: `代理地址 = 127.0.0.1:7890`
- Verify platform is in proxy list: `使用代理录制的平台`

### Cookie Expired
- Update cookie in `config/config.ini` under `[Cookie]` section
- Some platforms auto-refresh cookies (check logs)

### FFmpeg Not Found (Linux/macOS)
- Run installation commands in "FFmpeg Installation" section
- Verify with: `ffmpeg -version`

### Video File Corrupted on Interrupt
- Use `ts` format: `视频保存格式ts|mkv|flv|mp4|mp3音频|m4a音频 = ts`
- TS format is more resilient to interruption

## Code Modification Guidelines

### Adding New Platform Support

1. Add fetcher function in `src/spider.py`:
```python
@trace_error_decorator
async def get_newplatform_stream_data(url: str, proxy_addr: str = None, cookies: str = None) -> dict:
    # Return: {anchor_name, is_live, title, record_url, ...}
    pass
```

2. Add stream extractor in `src/stream.py` (if needed):
```python
@trace_error_decorator
async def get_newplatform_stream_url(json_data: dict, video_quality: str, proxy_addr: str) -> dict:
    # Return: {anchor_name, is_live, flv_url/m3u8_url}
    pass
```

3. Add room parser in `src/room.py` (if needed):
```python
def get_newplatform_room_id(url: str) -> str:
    # Extract room ID from URL
    pn4. Add to `demo.py` for testing:
```python
"newplatform": {
    "url": "https://example.com/room/12345",
    "func": spider.get_newplatform_stream_data,
}
```

### Modifying Recording Logic

Recording logic is in `main.py` around line 1000-2000. Key functions:
- `start_record()` - Initiates FFmpeg recording
- `monitoring_live()` - Monitors stream status
- `update_file()` - Updates configuration files

### Adding Notification Channels

Add new push function in `msg_push.py`:
```python
def new_push_service(content: str, title: str, config: dict) -> None:
    # Implement notification logic
    pass
```

Then integrate in `main.py` push notification section.

## Dependencies

- **requests** - Synchronous HTTP (legacy, being phased out)
- **httpx[http2]** - Async HTTP with HTTP/2 support
- **loguru** - Structured logging
- **pycryptodome** - Encryption/decryption for platform APIs
- **PyExecJS** - Execute JavaScript for signature generation
- **tqdm** - Progress bars
- **distro** - OS detection

## Python Version

Requires **Python >= 3.10** for modern async syntax and type hints.
