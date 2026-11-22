#!/usr/bin/env python3
"""Build the bundled real-cat pack from the approved local CC0 sample, offline."""
import array
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

ROOT = Path(__file__).resolve().parent
DEST = ROOT / "Resources" / "Sounds"
with tempfile.TemporaryDirectory() as temporary:
    decoded = Path(temporary) / "cat.wav"
    subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@44100",
                    "-c", "1", str(ROOT / "SampleSources/cat-meow-qubodup.mp3"),
                    str(decoded)], check=True)
    with wave.open(str(decoded)) as source:
        assert source.getnchannels() == 1 and source.getsampwidth() == 2
        pcm = array.array("h", source.readframes(source.getnframes()))
if sys.byteorder != "little":
    pcm.byteswap()
# Preserve the approved recording's pitch and duration. Limit the peak and use
# short fades to avoid sharp edges. Key release is silent, even when enabled.
gain = min(1.0, 0.45 * 32767 / max(1, max(abs(x) for x in pcm)))
fade = 220
pcm = array.array("h", (round(x * gain * min(1, i / fade, (len(pcm)-1-i) / fade))
                       for i, x in enumerate(pcm)))
end = len(pcm)
pcm.append(0)
keys = json.loads((DEST / "eg-oreo.json").read_text())["segments"]
pack = {"id": "fun-cat", "name": "猫猫喵 · 真实录音",
        "segments": {key: [[0, end], [end, end+1]] for key in keys}}
if sys.byteorder != "little":
    pcm.byteswap()
with wave.open(str(DEST / "fun-cat.wav"), "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(44100)
    output.writeframes(pcm.tobytes())
(DEST / "fun-cat.json").write_text(json.dumps(pack, ensure_ascii=False, indent=2) + "\n")
print(f"Built real-cat pack: {end/44100:.3f}s, {len(keys)} keys, silent releases")
