#!/usr/bin/env python3
"""Create a continuous local orchestral excerpt from the attributed public-domain recording."""
import array
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import wave

ROOT = Path(__file__).resolve().parent
DEST = ROOT / "Resources" / "Music"
DEST.mkdir(exist_ok=True)
RATE, CHANNELS = 44100, 2
with tempfile.TemporaryDirectory() as temporary:
    decoded = Path(temporary) / "recording.wav"
    subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@44100",
                    "-c", "2", str(ROOT / "SampleSources/beethoven5.ogg"), str(decoded)], check=True)
    with wave.open(str(decoded)) as source:
        assert source.getnchannels() == CHANNELS and source.getsampwidth() == 2
        original = array.array("h", source.readframes(RATE * 65))
if sys.byteorder != "little": original.byteswap()
onset = next(i // CHANNELS for i, value in enumerate(original) if abs(value) > 900)
start = max(0, onset - round(0.015 * RATE))
excerpt = original[start * CHANNELS:(start + 60 * RATE) * CHANNELS]
gain = min(1.0, 0.32 * 32767 / max(abs(x) for x in excerpt))
# No periodic fades or cuts: only the excerpt's outer boundaries are faded.
length = len(excerpt) // CHANNELS
fade = round(0.015 * RATE)
pcm = array.array("h", (round(sample * gain * min(1, (i // CHANNELS) / fade,
    (length - 1 - i // CHANNELS) / fade)) for i, sample in enumerate(excerpt)))
segments = [[0, length]]
if sys.byteorder != "little": pcm.byteswap()
with wave.open(str(DEST / "beethoven5.wav"), "wb") as output:
    output.setnchannels(CHANNELS); output.setsampwidth(2); output.setframerate(RATE)
    output.writeframes(pcm.tobytes())
(DEST / "beethoven5.json").write_text(json.dumps({
    "id": "beethoven5", "name": "贝多芬第五交响曲 · 开篇",
    "segments": {"KeyA": segments}
}, ensure_ascii=False, indent=2) + "\n")
print(f"Built continuous {length / RATE:.1f}s stereo orchestral excerpt, source offset {start / RATE:.3f}s, peak gain {gain:.4f}")
