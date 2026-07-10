#!/usr/bin/env python3
"""用白色 WUDAX 字标生成 App 图标(1024×1024,不透明)。
iOS 图标不允许 alpha 透明通道,所以把白 logo 合成到品牌墨松绿 #0F1E18 背景上。
"""
import os
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOGO = os.path.join(ROOT, "WudaX", "Sources", "Resources", "logo_white.png")
OUT_DIR = os.path.join(ROOT, "WudaX", "Sources", "Resources",
                       "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT_DIR, exist_ok=True)

SIZE = 1024
BG = (0x0F, 0x1E, 0x18, 255)   # 墨松绿

canvas = Image.new("RGBA", (SIZE, SIZE), BG)

logo = Image.open(LOGO).convert("RGBA")
# 字标占画布约 66% 宽,保持比例居中
target_w = int(SIZE * 0.66)
scale = target_w / logo.width
target_h = int(logo.height * scale)
logo = logo.resize((target_w, target_h), Image.LANCZOS)

x = (SIZE - target_w) // 2
y = (SIZE - target_h) // 2
canvas.alpha_composite(logo, (x, y))

# 压平成不透明 RGB(去掉 alpha,满足 App 图标要求)
flat = Image.new("RGB", (SIZE, SIZE), BG[:3])
flat.paste(canvas, mask=canvas.split()[3])

out = os.path.join(OUT_DIR, "icon_1024.png")
flat.save(out, "PNG")
print("图标已生成:", out, flat.size, flat.mode)
