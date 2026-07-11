#!/usr/bin/env python3
"""Submit a model to Rodin Bang! and save the task response.

Requires:
  export HYPER3D_API_KEY="..."

This script never stores or prints the API key.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import requests


ENDPOINT = "https://api.hyper3d.com/api/v2/bang"


def redact_sensitive_fields(value):
    if isinstance(value, dict):
        redacted = {}
        for key, item in value.items():
            if key.lower() in {"subscription_key", "api_key", "token", "secret", "authorization"}:
                redacted[key] = "[REDACTED]"
            else:
                redacted[key] = redact_sensitive_fields(item)
        return redacted
    if isinstance(value, list):
        return [redact_sensitive_fields(item) for item in value]
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Submit a custom model to Rodin Bang.")
    parser.add_argument("--model", default="assets/3d/exoskeleton.glb", help="Path to model file.")
    parser.add_argument("--image", default=None, help="Optional reference image path.")
    parser.add_argument("--prompt", default="Split the WUDAX knee exoskeleton into functional submodels: upper brace, lower brace, hinge actuator, straps, battery pack, sensors, and protective shells.")
    parser.add_argument("--strength", type=float, default=5)
    parser.add_argument("--geometry-file-format", default="glb", choices=["glb", "obj", "fbx", "stl", "usdz"])
    parser.add_argument("--material", default="PBR", choices=["PBR", "Shaded", "None", "All"])
    parser.add_argument("--resolution", default="Basic", choices=["Basic", "High"])
    parser.add_argument("--out", default="assets/3d/bang/task.json", help="Where to write the JSON task response.")
    args = parser.parse_args()

    api_key = os.environ.get("HYPER3D_API_KEY")
    if not api_key:
        raise SystemExit("Missing HYPER3D_API_KEY. Set it in your shell or local .env; never commit API keys.")

    model_path = Path(args.model)
    if not model_path.exists():
        raise SystemExit(f"Model not found: {model_path}")

    data = {
        "prompt": args.prompt,
        "strength": str(args.strength),
        "geometry_file_format": args.geometry_file_format,
        "material": args.material,
        "resolution": args.resolution,
    }

    files = {
        "model": (model_path.name, model_path.open("rb"), "application/octet-stream"),
    }

    image_handle = None
    try:
        if args.image:
            image_path = Path(args.image)
            if not image_path.exists():
                raise SystemExit(f"Image not found: {image_path}")
            image_handle = image_path.open("rb")
            files["image"] = (image_path.name, image_handle, "image/png")

        response = requests.post(
            ENDPOINT,
            data=data,
            files=files,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=600,
        )
    finally:
        files["model"][1].close()
        if image_handle:
            image_handle.close()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        payload = response.json()
    except ValueError:
        payload = {"error": "NON_JSON_RESPONSE", "message": response.text}

    safe_payload = {
        "status_code": response.status_code,
        "response": redact_sensitive_fields(payload),
    }
    out_path.write_text(json.dumps(safe_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    if response.ok:
        print(f"Rodin Bang submitted. Task response saved to {out_path}")
        print(f"Task UUID: {payload.get('uuid')}")
        return 0

    print(f"Rodin Bang request failed with HTTP {response.status_code}. Response saved to {out_path}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
