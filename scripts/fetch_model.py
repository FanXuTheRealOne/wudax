#!/usr/bin/env python3
"""把 Qwen3-0.6B-4bit 模型下载到工程内,供 App 打包离线使用。
用国内镜像 hf-mirror.com;零依赖(urllib 自动跟随重定向),避开 huggingface_hub
在新版 Python 上的兼容问题。下载后整个文件夹作为 folder reference 打进 .app,
运行时用 ModelConfiguration(directory:) 本地加载,完全不联网。
"""
import os
import sys
import urllib.request

ENDPOINT = os.environ.get("HF_ENDPOINT", "https://hf-mirror.com")
REPO = "mlx-community/Qwen3-0.6B-4bit"
FILES = [
    "config.json",
    "generation_config.json",   # 可能不存在,404 时跳过
    "model.safetensors",
    "model.safetensors.index.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "special_tokens_map.json",
    "added_tokens.json",
    "vocab.json",
    "merges.txt",
]

DEST = os.path.abspath(os.path.join(os.path.dirname(__file__), "..",
                                    "WudaX", "BundledModel", "LLMModel"))
os.makedirs(DEST, exist_ok=True)


def download(fname: str) -> bool:
    url = f"{ENDPOINT}/{REPO}/resolve/main/{fname}"
    out = os.path.join(DEST, fname)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "wudax-fetch"})
        with urllib.request.urlopen(req, timeout=60) as r, open(out, "wb") as f:
            total = int(r.headers.get("Content-Length", 0))
            got = 0
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                got += len(chunk)
                if total:
                    pct = got * 100 // total
                    print(f"\r  {fname:34s} {got/1e6:7.1f}/{total/1e6:.1f} MB {pct:3d}%",
                          end="", flush=True)
        print(f"\r  {fname:34s} {os.path.getsize(out)/1e6:7.1f} MB  ✓")
        return True
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"  {fname:34s} (仓库无此文件,跳过)")
            if os.path.exists(out):
                os.remove(out)
            return True
        print(f"  {fname:34s} HTTP {e.code} ✗")
        return False
    except Exception as e:  # noqa
        print(f"  {fname:34s} 失败: {e} ✗")
        return False


print(f"源 {ENDPOINT}  →  {DEST}")
ok = all(download(f) for f in FILES)
print("完成 ✅" if ok else "部分失败 ❌")
sys.exit(0 if ok else 1)
