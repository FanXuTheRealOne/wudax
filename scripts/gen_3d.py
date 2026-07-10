#!/usr/bin/env python3
"""Submit exoskeleton render to Meshy image-to-3D (meshy-6) and download USDZ/GLB."""
import base64, json, os, sys, time
import requests

API_KEY = "REMOVED-LEAKED-MESHY-KEY"
BASE = "https://api.meshy.ai/openapi/v1/image-to-3d"
H = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "3d")

def submit(img_path):
    b64 = base64.b64encode(open(img_path, "rb").read()).decode()
    payload = {
        "image_url": f"data:image/png;base64,{b64}",
        "ai_model": "meshy-6",
        "topology": "triangle",
        "target_polycount": 100000,
        "should_remesh": True,
        "should_texture": True,
        "enable_pbr": True,
    }
    r = requests.post(BASE, headers=H, json=payload, timeout=120)
    print("submit:", r.status_code, r.text[:500])
    r.raise_for_status()
    return r.json()["result"]

def poll(task_id):
    while True:
        r = requests.get(f"{BASE}/{task_id}", headers=H, timeout=60)
        d = r.json()
        st = d.get("status")
        print(f"status={st} progress={d.get('progress')}", flush=True)
        if st == "SUCCEEDED":
            return d
        if st in ("FAILED", "CANCELED"):
            print(json.dumps(d, indent=2)[:1000])
            sys.exit(1)
        time.sleep(15)

if __name__ == "__main__":
    img = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "design", "exo_render.png")
    os.makedirs(OUT, exist_ok=True)
    task_id = submit(img)
    print("TASK:", task_id)
    d = poll(task_id)
    urls = d.get("model_urls", {})
    for fmt in ("usdz", "glb"):
        u = urls.get(fmt)
        if u:
            p = os.path.join(OUT, f"exoskeleton.{fmt}")
            open(p, "wb").write(requests.get(u, timeout=600).content)
            print("saved", p, os.path.getsize(p))
    # thumbnail for fallback
    if d.get("thumbnail_url"):
        open(os.path.join(OUT, "exo_thumb.png"), "wb").write(
            requests.get(d["thumbnail_url"], timeout=300).content)
    print("MESHY DONE")
