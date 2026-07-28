"""Derive Maker WAV assets from the original SynthAudio Web Audio parameters.

The source project creates these effects at runtime. Maker consumes the same
oscillator, envelope, and noise specifications as deterministic WAV assets.
"""

from __future__ import annotations

import hashlib
import json
import math
import random
import struct
import wave
from pathlib import Path


MAKER_ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"D:\System Files\Download\牛顿\牛顿\src\game\audio\SynthAudio.ts")
AUDIO_ROOT = MAKER_ROOT / "assets" / "audio" / "phase1"
MANIFEST = MAKER_ROOT / "migration" / "phase1_audio_manifest.json"
SAMPLE_RATE = 44_100


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def envelope(local_time: float, duration: float, volume: float) -> float:
    if local_time < 0 or local_time >= duration:
        return 0.0
    floor = 0.0001
    attack = min(0.012, duration)
    if local_time < attack:
        return floor * (volume / floor) ** (local_time / attack)
    if duration <= attack:
        return floor
    return volume * (floor / volume) ** ((local_time - attack) / (duration - attack))


def phase_at(local_time: float, start_frequency: float, end_frequency: float, duration: float) -> float:
    if start_frequency == end_frequency:
        return math.tau * start_frequency * local_time
    ratio = end_frequency / start_frequency
    cycles = start_frequency * duration * (ratio ** (local_time / duration) - 1.0) / math.log(ratio)
    return math.tau * cycles


def oscillator(phase: float, kind: str) -> float:
    if kind == "sine":
        return math.sin(phase)
    if kind == "triangle":
        return 2.0 * math.asin(math.sin(phase)) / math.pi
    if kind == "sawtooth":
        normalized = phase / math.tau
        return 2.0 * (normalized - math.floor(normalized + 0.5))
    raise ValueError(f"unsupported oscillator {kind}")


def add_tone(samples: list[float], start_hz: float, end_hz: float, duration: float, kind: str, volume: float, delay: float = 0.0) -> None:
    start = round(delay * SAMPLE_RATE)
    end = min(len(samples), start + math.ceil(duration * SAMPLE_RATE))
    for index in range(start, end):
        local_time = (index - start) / SAMPLE_RATE
        samples[index] += oscillator(phase_at(local_time, start_hz, end_hz, duration), kind) * envelope(local_time, duration, volume)


def add_noise(samples: list[float], duration: float, volume: float, low_pass: float, seed: int) -> None:
    generator = random.Random(seed)
    alpha = 1.0 - math.exp(-math.tau * low_pass / SAMPLE_RATE)
    filtered = 0.0
    count = min(len(samples), math.ceil(duration * SAMPLE_RATE))
    for index in range(count):
        filtered += alpha * (generator.uniform(-1.0, 1.0) - filtered)
        local_time = index / SAMPLE_RATE
        gain = volume * (0.0001 / volume) ** (local_time / duration)
        samples[index] += filtered * gain


SOUNDS = {
    "launch": {
        "duration": 0.19,
        "tones": [(190, 430, 0.16, "sine", 0.09, 0.0)],
        "noises": [(0.08, 0.035, 900)],
    },
    "card": {
        "duration": 0.23,
        "tones": [(360, 760, 0.2, "triangle", 0.07, 0.0), (540, 980, 0.16, "sine", 0.04, 0.045)],
        "noises": [],
    },
    "impact": {
        "duration": 0.12,
        "tones": [(105, 58, 0.09, "sine", 0.05, 0.0)],
        "noises": [(0.045, 0.025, 520)],
    },
    "punch": {
        "duration": 0.31,
        "tones": [(94, 38, 0.28, "sine", 0.16, 0.0), (280, 120, 0.16, "sawtooth", 0.035, 0.03)],
        "noises": [(0.22, 0.13, 680)],
    },
    "success": {
        "duration": 0.70,
        "tones": [(392, 392, 0.34, "sine", 0.07, 0.0), (523.25, 523.25, 0.38, "sine", 0.065, 0.11), (659.25, 659.25, 0.45, "sine", 0.06, 0.22)],
        "noises": [],
    },
    "reset": {
        "duration": 0.15,
        "tones": [(280, 160, 0.12, "triangle", 0.045, 0.0)],
        "noises": [],
    },
}


def write_sound(name: str, spec: dict[str, object], seed: int) -> Path:
    duration = float(spec["duration"])
    samples = [0.0] * math.ceil(duration * SAMPLE_RATE)
    for tone in spec["tones"]:
        add_tone(samples, *tone)
    for noise in spec["noises"]:
        add_noise(samples, *noise, seed)
    output = AUDIO_ROOT / f"{name}.wav"
    with wave.open(str(output), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        pcm = bytearray()
        for sample in samples:
            clipped = max(-1.0, min(1.0, sample))
            pcm.extend(struct.pack("<h", round(clipped * 32767)))
        wav.writeframes(pcm)
    return output


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"source audio module not found: {SOURCE}")
    AUDIO_ROOT.mkdir(parents=True, exist_ok=True)
    outputs = []
    for seed, (name, spec) in enumerate(SOUNDS.items(), start=1):
        output = write_sound(name, spec, seed)
        outputs.append({
            "kind": name,
            "derived": output.relative_to(MAKER_ROOT).as_posix(),
            "sha256": sha256(output),
            "durationSeconds": spec["duration"],
        })
    MANIFEST.write_text(json.dumps({
        "schemaVersion": 1,
        "source": str(SOURCE).replace("\\", "/"),
        "sourceSha256": sha256(SOURCE),
        "sampleRate": SAMPLE_RATE,
        "note": "Derived from the original Web Audio oscillator, envelope, noise, and low-pass parameters.",
        "assets": outputs,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
