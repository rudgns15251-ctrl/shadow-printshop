"""Convert the three original MEDIA-001 mono WAVs to 48 kHz without dependencies.
The approved 44.1 kHz originals remain untouched. Linear interpolation is
sufficient for these short trial effects; listen to the final mix on Windows.
"""
from pathlib import Path
import struct
import wave

ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
TARGET_RATE = 48000


def convert(name):
    with wave.open(str(ROOT / f'{name}.wav'), 'rb') as original:
        assert original.getnchannels() == 1 and original.getsampwidth() == 2
        source_rate = original.getframerate()
        raw = original.readframes(original.getnframes())
    samples = struct.unpack('<' + 'h' * (len(raw) // 2), raw)
    output_size = round(len(samples) * TARGET_RATE / source_rate)
    output = []
    for dest in range(output_size):
        pos = dest * source_rate / TARGET_RATE
        before = min(int(pos), len(samples) - 1)
        after = min(before + 1, len(samples) - 1)
        fraction = pos - before
        value = round(samples[before] * (1.0 - fraction) + samples[after] * fraction)
        output.append(max(-32768, min(32767, value)))
    with wave.open(str(ROOT / f'slice_{name}.wav'), 'wb') as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(TARGET_RATE)
        target.writeframes(struct.pack('<' + 'h' * len(output), *output))
    print(f'slice_{name}.wav: {TARGET_RATE} Hz / {len(output)} frames')


if __name__ == '__main__':
    for name in ('print', 'undo', 'complete'):
        convert(name)
