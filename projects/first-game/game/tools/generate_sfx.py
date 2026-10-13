"""자체 절차 합성. Python 표준 라이브러리만 사용, 외부 샘플 없음."""
from pathlib import Path
import hashlib
import json
import math
import random
import struct
import wave

RATE = 44100
OUT = Path(__file__).resolve().parents[1] / "assets" / "audio"


def synth(kind, seconds):
    rng = random.Random(100 + kind)
    result = []
    for i in range(round(seconds * RATE)):
        t = i / RATE
        fade = min(1.0, t / 0.004, (seconds - t) / 0.018)
        if kind == 0:  # 짧은 종이 마찰과 낮은 도장 충격
            value = (0.23 * rng.uniform(-1, 1) * math.exp(-22 * t)
                     + 0.38 * math.sin(2 * math.pi * 145 * t) * math.exp(-32 * t))
        elif kind == 1:  # 취소: 하강하는 부드러운 톤
            value = 0.30 * math.sin(2 * math.pi * (620 * t - 650 * t * t)) * math.exp(-10 * t)
        else:  # 완료: 직접 합성한 두 음, 녹음/음원 사용 없음
            value = 0.22 * math.sin(2 * math.pi * 660 * t) * math.exp(-5 * t)
            if t >= 0.09:
                value += 0.20 * math.sin(2 * math.pi * 880 * (t - 0.09)) * math.exp(-6 * (t - 0.09))
        result.append(round(value * fade * 32767))
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for kind, (name, duration) in enumerate((("print", 0.18), ("undo", 0.24), ("complete", 0.55))):
        samples = synth(kind, duration)
        assert max(abs(s) for s in samples) < 32767
        payload = struct.pack("<%dh" % len(samples), *samples)
        path = OUT / (name + ".wav")
        with wave.open(str(path), "wb") as wav:
            wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
            wav.writeframes(payload)
        with wave.open(str(path), "rb") as wav:
            assert wav.getparams()[:3] == (1, 2, RATE)
            assert wav.readframes(wav.getnframes()) == payload
        print(json.dumps({"file": str(path), "frames": len(samples),
                          "seconds": len(samples) / RATE,
                          "peak": max(abs(s) for s in samples),
                          "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}))


if __name__ == "__main__":
    main()
