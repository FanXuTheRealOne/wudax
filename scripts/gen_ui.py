#!/usr/bin/env python3
"""WUDAX UI design mockups + exoskeleton product render via image2 API."""
import base64, json, os, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests

API_BASE = "https://api.tokenrouter.com/v1"
API_KEY = "sk-D2L6oJiio9Mcts0uB3mQ6nMliszCowkGe78TTrVvKfiGPDEP"
MODEL = "openai/gpt-5.4-image-2"
OUT = os.path.join(os.path.dirname(__file__), "..", "design")

BRAND = (
    "Premium iOS app UI design mockup, single iPhone 16 Pro screen, flat front view, "
    "full-bleed screen only, no device frame, no hands, 9:19.5 aspect. "
    "Brand: WUDAX, a hiking fatigue-management exoskeleton company. Brand spirit: Zhuangzi 'Wu Dai' "
    "(effortless, natural, calm). Design language: deep ink-pine green background (#0F1E18), "
    "rice-paper off-white cards (#F5F1E8), amber accent (#D9822B) for caution, cinnabar red (#B3402E) "
    "only for retreat warnings, thin topographic contour-line motifs, subtle ink-brush texture accents, "
    "elegant Chinese serif headlines (Songti style) with clean sans body text in Simplified Chinese, "
    "generous whitespace, quiet luxury outdoor aesthetic, ultra-detailed, crisp UI text, dribbble quality. "
)

SCREENS = {
    "01_home": (
        "Home screen '行程' : top has small calligraphy wordmark 'wudaX', a serene ink-wash mountain "
        "ridge illustration header, one large route card '武功山 · 龙山村-发云界' showing distance 24.6km, "
        "ascent 1780m, estimated 9h30m, a small risk badge '中高风险' in amber, a quiet button '导入 GPX 路线', "
        "below a small section '疲劳档案' with two subtle stat chips (下坡耐受, 补给习惯). Minimal, calm, almost empty."
    ),
    "02_budget_card": (
        "Trip risk budget card screen '行程预算卡': elevation profile chart of the route in thin contour "
        "line style with 3 flagged risk points, overall risk level '中高' shown as a large elegant seal-stamp "
        "style badge, list of top-3 risks with amber icons (长下坡 1200m 连续下降 / 17:40 后进入夜行风险 / 补水点稀少), "
        "suggested supplies row (水 3.0L, 食物 1600kcal, 头灯), a section '关键复核点' with 3 checkpoints on "
        "a mini route map. Bottom pill button '确认并开始准备'."
    ),
    "03_agent_ask": (
        "Conversational agent screen '行前确认': chat-style but very refined, agent bubbles on rice-paper "
        "cards asking questions one at a time: '你几点出发？', '身上实际带多少水？', quick-reply chips "
        "(05:30 / 06:00 / 06:30), a subtle progress indicator '3/5', agent avatar is a minimal ink-brush "
        "circle. Calm, spacious, not a busy chat app."
    ),
    "04_gatekeeper": (
        "Pre-departure gate screen '出发守门': checklist with elegant toggle rows: 水 2.5L/建议3.0L shown "
        "with amber warning bar, 食物 ✓, 头灯 ✓, 备用电源 ✓, 保暖/雨具 ✓, 离线轨迹 ✓. A prominent quiet "
        "warning card: '当前水量低于建议下限，17:40 后可能仍在复杂地形' with two action buttons '增加补给' "
        "and '降低路线目标', bottom primary button '接受风险并出发' in ink green."
    ),
    "05_checkin": (
        "In-trip check-in card '状态确认' triggered by agent: dark immersive mode, current stats bar (已行进 "
        "11.2km · 计划偏差 -18min), three big questions with elegant sliders/steppers: '剩余水量' with bottle "
        "icons, '膝盖疼痛 0-10' slider, '困倦程度 0-10' slider, one big verdict area showing '谨慎继续' in "
        "amber seal-stamp style with one-line reason. Feels like a wristwatch-simple interaction enlarged."
    ),
    "06_retreat": (
        "Retreat decision screen '撤退窗口': serious but calm, cinnabar red accent seal-stamp badge '建议降级', "
        "reason list: 低补给 + 长下坡 + 夜间风险叠加, an elevation profile showing point of no return marked, "
        "two route options compared: 继续至发云界 (回程夜间下撤, 风险高) vs 当前节点下撤 (2.1km 到公路, 日落前可完成), "
        "big bottom buttons '选择下撤路线' (primary) and '仍然继续' (ghost, small)."
    ),
    "07_review": (
        "Post-trip review screen '行后复盘': timeline of the day with the moment marked where '享受路线' turned "
        "into '只想走出去' at 14:20, cards summarizing 失控点: 补给不足 from 13:00, 膝痛 4/10 起于长下坡, "
        "agent question card '如果重走一次，你会在哪里降级？' with tappable timeline, section '疲劳档案已更新' "
        "showing 下坡耐受 slightly lowered. Warm dusk-toned ink-wash header illustration."
    ),
    "08_exo": (
        "Exoskeleton showcase screen '装备': a photorealistic 3D render of a sleek carbon-fiber knee "
        "exoskeleton floating center stage on dark ink-green gradient, soft studio rim light, 360° rotate "
        "hint dots below, spec chips (制动余量, 电量 82%, 连接状态 v2.0 预留), text 'WUDAX 膝关节外骨骼 · 即将支持', "
        "quiet elegant, Apple-store product page quality."
    ),
}

EXO_RENDER = (
    "Photorealistic industrial design product photograph of a premium knee exoskeleton wearable device, "
    "single product only, 3/4 front view, centered, plain pure white studio background, soft even lighting, "
    "no human, no text, no logo watermark. Design: matte carbon-fiber and magnesium-alloy frame in deep "
    "ink-green and charcoal, hinged actuator joint at the knee with subtle amber accent ring, breathable "
    "padded straps for thigh and calf, compact battery pack, sleek Apple-like minimalist outdoor gear "
    "aesthetic, ultra sharp, 8k product shot"
)

def gen(name, prompt, size=None):
    body = {"model": MODEL, "prompt": prompt}
    if size:
        body["size"] = size
    for attempt in range(3):
        try:
            r = requests.post(
                f"{API_BASE}/images/generations",
                headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
                json=body, timeout=600)
            r.raise_for_status()
            d = r.json()["data"][0]
            path = os.path.join(OUT, f"{name}.png")
            if d.get("b64_json"):
                open(path, "wb").write(base64.b64decode(d["b64_json"]))
            elif d.get("url"):
                open(path, "wb").write(requests.get(d["url"], timeout=300).content)
            print(f"OK {name}")
            return name
        except Exception as e:
            print(f"RETRY {name} ({attempt+1}): {e}", flush=True)
            time.sleep(10)
    print(f"FAIL {name}")
    return None

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    jobs = {"exo_render": (EXO_RENDER, "1024x1024")}
    for k, v in SCREENS.items():
        jobs[k] = (BRAND + v, "1024x1536")
    with ThreadPoolExecutor(max_workers=3) as ex:
        futs = [ex.submit(gen, k, p, s) for k, (p, s) in jobs.items()]
        for f in as_completed(futs):
            f.result()
    print("ALL DONE")
