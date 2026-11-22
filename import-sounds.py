#!/usr/bin/env python3
"""One-time, offline import of Mechvibes v3.5.7 bundled keyboard samples.
Usage: python3 import-sounds.py /path/to/mechvibes/source
No download, package manager, or network connection is used.
"""
import json
import pathlib
import subprocess
import sys
import tempfile
import wave

root = pathlib.Path(__file__).resolve().parent
source = pathlib.Path(sys.argv[1]).resolve()
destination = root / "Resources" / "Sounds"
destination.mkdir(parents=True, exist_ok=True)
names = {
    "topre-purple-hybrid-pbt": "Topre Purple · 柔和",
    "eg-oreo": "Everglide Oreo · 饱满",
    "eg-crystal-purple": "Everglide Crystal Purple · 清亮",
    "cherrymx-red-abs": "Cherry 红轴 · ABS",
    "cherrymx-black-abs": "Cherry 黑轴 · ABS",
    "cherrymx-black-pbt": "Cherry 黑轴 · PBT",
    "cherrymx-brown-abs": "Cherry 茶轴 · ABS",
    "cherrymx-brown-pbt": "Cherry 茶轴 · PBT",
    "cherrymx-blue-abs": "Cherry 青轴 · ABS",
    "cherrymx-blue-pbt": "Cherry 青轴 · PBT",
}
with tempfile.TemporaryDirectory(prefix="keytone-import-") as temporary:
    for pack_id, name in names.items():
        folder = source / "soundpacks" / "keyboard" / pack_id
        original = json.loads((folder / "config.json").read_text())
        decoded = pathlib.Path(temporary) / (pack_id + ".wav")
        subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16", "-r", "44100", "-c", "1",
                        str(folder / original["audio_file"]), str(decoded)], check=True)
        segments = {}
        offset = 0
        with wave.open(str(decoded), "rb") as audio, wave.open(str(destination / (pack_id + ".wav")), "wb") as compact:
            compact.setparams(audio.getparams())
            rate = audio.getframerate()
            for key, definition in original["definitions"].items():
                parts = []
                for start_ms, end_ms in definition["timing"]:
                    start = round(start_ms * rate / 1000)
                    end = min(audio.getnframes(), round(end_ms * rate / 1000))
                    if start < 0 or start >= end:
                        raise ValueError(f"Invalid segment: {pack_id}/{key}")
                    audio.setpos(start)
                    compact.writeframesraw(audio.readframes(end - start))
                    parts.append([offset, offset + end - start])
                    offset += end - start
                segments[key] = parts
        (destination / (pack_id + ".json")).write_text(json.dumps({
            "id": pack_id, "name": name, "segments": segments
        }, ensure_ascii=False, indent=2) + "\n")
        print(f"Imported {pack_id}: {len(segments)} keys")
(root / "Resources" / "Mechvibes-LICENSE.txt").write_bytes((source / "LICENSE").read_bytes())
