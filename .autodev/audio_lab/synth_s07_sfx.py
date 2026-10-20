"""Deterministic original SFX for S07 (Claude Code, 2026-10-21). Python stdlib only.

menu_paper.wav          dry paper handling for opening orders/records.
chapter_transition.wav  a muffled press thump, its softer release and a paper slide.

No recordings, samples, downloads or generative audio services. Same inputs give
byte-identical WAVs; `python synth_s07_sfx.py OUT_DIR` writes both and prints the
measurements recorded in ASSET_LICENSES.json. Listening quality is not claimed.
"""
import hashlib
import io
import json
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 48000

def lowpass(signal, cutoff):
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    y, out = 0.0, []
    for x in signal:
        y += a * (x - y)
        out.append(y)
    return out

def highpass(signal, cutoff):
    return [x - y for x, y in zip(signal, lowpass(signal, cutoff))]

def noise(seed, count):
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(count)]

def edge_fades(samples, fade_in, fade_out):
    count = len(samples)
    for i in range(count):
        t_in = i / max(1, int(fade_in * RATE))
        t_out = (count - 1 - i) / max(1, int(fade_out * RATE))
        g = 1.0
        if t_in < 1.0: g *= 0.5 - 0.5 * math.cos(math.pi * t_in)
        if t_out < 1.0: g *= 0.5 - 0.5 * math.cos(math.pi * t_out)
        samples[i] *= g
    samples[-1] = 0.0
    return samples

def encode(samples, peak):
    scale = peak / max(map(abs, samples))
    pcm = [max(-32767, min(32767, round(x * scale * 32767))) for x in samples]
    buffer = io.BytesIO()
    with wave.open(buffer, 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(struct.pack('<%dh' % len(pcm), *pcm))
    return buffer.getvalue(), scale

def menu_paper():
    count = int(0.42 * RATE)
    band = lowpass(highpass(noise(20261021, count), 1200.0), 5200.0)
    bursts = ((0.000, 1.00, 0.045), (0.110, 0.70, 0.040), (0.240, 0.45, 0.055))
    out = []
    for i, x in enumerate(band):
        t = i / RATE
        env = 0.12 * math.sin(math.pi * t / 0.42)  # soft slide bed
        for start, gain, decay in bursts:
            if t >= start:
                local = t - start
                env += gain * (local / 0.006 if local < 0.006 else math.exp(-(local - 0.006) / decay))
        out.append(x * env)
    return edge_fades(out, 0.002, 0.030), 0.20

def chapter_transition():
    count = int(1.8 * RATE)
    slide = lowpass(highpass(noise(19981118, count), 300.0), 2500.0)
    out, phase, phase2 = [], 0.0, 0.0
    for i in range(count):
        t = i / RATE
        frequency = 58.0 + 34.0 * math.exp(-t / 0.09)
        phase += 2.0 * math.pi * frequency / RATE
        thump = math.sin(phase) * min(1.0, t / 0.012) * math.exp(-t / 0.28)
        knock = 0.35 * math.sin(2.0 * math.pi * 180.0 * t) * min(1.0, t / 0.004) * math.exp(-t / 0.05)
        second = 0.0
        if t >= 0.62:
            r = t - 0.62
            phase2 += 2.0 * math.pi * (52.0 + 20.0 * math.exp(-r / 0.08)) / RATE
            second = 0.45 * math.sin(phase2) * min(1.0, r / 0.015) * math.exp(-r / 0.22)
        paper = 0.0
        if 0.18 <= t <= 1.35:
            paper = 0.18 * math.sin(math.pi * (t - 0.18) / 1.17) * slide[i] * 3.0
        ring = 0.04 * math.exp(-t / 0.6) * (math.sin(2 * math.pi * 523.25 * t) + 0.5 * math.sin(2 * math.pi * 784.0 * t))
        out.append(thump + knock + second + paper + ring)
    return edge_fades(out, 0.0005, 0.150), 0.34

def measure(data):
    with wave.open(io.BytesIO(data), 'rb') as w:
        frames = w.readframes(w.getnframes())
        params = (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes())
    s = struct.unpack('<%dh' % (len(frames) // 2), frames)
    return {'channels': params[0], 'sample_width_bytes': params[1], 'sample_rate_hz': params[2], 'frame_count': params[3],
            'duration_seconds': round(params[3] / params[2], 6), 'absolute_peak_pcm16': max(map(abs, s)),
            'normalized_absolute_peak': max(map(abs, s)) / 32768, 'rms': round(math.sqrt(sum(x * x for x in s) / len(s)) / 32768, 6),
            'first_sample_pcm16': s[0], 'last_sample_pcm16': s[-1], 'sha256': hashlib.sha256(data).hexdigest()}

def main(out_dir):
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, builder in (('menu_paper.wav', menu_paper), ('chapter_transition.wav', chapter_transition)):
        samples, peak = builder()
        data, scale = encode(samples, peak)
        (out / name).write_bytes(data)
        report[name] = dict(measure(data), target_peak=peak, normalization_scale=scale)
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    main(sys.argv[1])
