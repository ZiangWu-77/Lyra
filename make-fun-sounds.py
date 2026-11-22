#!/usr/bin/env python3
"""Generate original cartoon keyboard samples entirely offline, with Python stdlib.
The duck sounds are synthesized effects, not recordings of real animals.
The real-cat recording is rebuilt separately with import-cat.py.
All generated material is covered by this project's MIT license.
"""
import array
import json
import math
import pathlib
import random
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parent
DEST = ROOT / "Resources" / "Sounds"
RATE = 44100
TAU = 2 * math.pi
KEYS = sorted(json.loads((DEST / "eg-oreo.json").read_text())["segments"])

def envelope(t, duration, attack=0.009):
    return min(1, t / attack) * min(1, (duration - t) / 0.025)

def synth(kind, variant, release=False):
    rng = random.Random(1700 + variant)
    pitch = 2 ** ((variant % 9 - 4) / 18)
    duration = 0.15 * (1.25 if variant >= 12 else 1)
    if release:
        duration = 0.035
    phase = 0.0
    samples = []
    for index in range(round(duration * RATE)):
        t = index / RATE
        x = t / duration
        if release:
            hz = (930 if kind == "bubble" else 600) * pitch * (1 - 0.55 * x)
            phase += TAU * hz / RATE
            value = math.sin(phase) * math.exp(-7 * x) * 0.22
        elif kind == "duck":
            hz = (215 - 75 * x + 12 * math.sin(TAU * 32 * t)) * pitch
            phase += TAU * hz / RATE
            value = 0.0
            for harmonic in range(1, 16):
                weight = math.exp(-((harmonic * hz - 1250) / 850) ** 2) / (harmonic ** 0.65)
                value += weight * math.sin(harmonic * phase)
            value = math.tanh(value * 3.2) * (0.8 + 0.2 * math.sin(TAU * 63 * t))
        elif kind == "bubble":
            hz = (330 + 1700 * math.exp(-35 * t)) * pitch
            phase += TAU * hz / RATE
            value = (math.sin(phase) + 0.15 * math.sin(phase * 2.03)) * math.exp(-22 * t)
            value += rng.uniform(-1, 1) * math.exp(-180 * t) * 0.12
        else:
            step = min(2, int(x * 3))
            hz = [523.25, 659.25, 783.99][step] * pitch
            phase += TAU * hz / RATE
            # Band-limited square-like tone; no harsh full-band discontinuities.
            value = sum(math.sin(phase * h) / h for h in (1, 3, 5, 7)) * math.exp(-9 * t)
        samples.append(value * envelope(t, duration))
    peak = max(abs(value) for value in samples)
    gain = (0.12 if release else 0.62) / max(peak, 0.001)
    return array.array("h", (round(value * gain * 32767) for value in samples))

for kind, name in [("bubble", "泡泡 · 轻弹"),
                   ("duck", "橡皮鸭 · 嘎嘎"), ("arcade", "街机 · 8-bit")]:
    pack_id = "fun-" + kind
    pcm = array.array("h")
    variants = []
    for variant in range(16):
        parts = []
        for release in (False, True):
            clip = synth(kind, variant, release)
            start = len(pcm)
            pcm.extend(clip)
            parts.append([start, len(pcm)])
        variants.append(parts)
    definitions = {}
    for key in KEYS:
        variant = {"Space": 12, "Enter": 13, "Backspace": 14, "Escape": 15}.get(key)
        if variant is None:
            variant = sum((index + 1) * ord(char) for index, char in enumerate(key)) % 12
        definitions[key] = variants[variant]
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(DEST / (pack_id + ".wav")), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    (DEST / (pack_id + ".json")).write_text(json.dumps({"id": pack_id, "name": name,
        "segments": definitions}, ensure_ascii=False, indent=2) + "\n")
    print(f"Generated {name}: 16 variants, down/up samples, {len(pcm)/RATE:.2f}s PCM")
