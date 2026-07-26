"""Generates a short, gentle arpeggio as a 16-bit mono WAV, stdlib only.

Usage: python3 sample-tone.py <output.wav>
"""

import math
import struct
import sys
import wave

RATE = 44100
NOTES = [261.63, 329.63, 392.00, 523.25, 392.00, 329.63]  # C major arpeggio
NOTE_SECONDS = 0.9
AMPLITUDE = 0.32


def envelope(position: float) -> float:
    """Soft attack and a long decay, so notes never click."""
    attack = min(position / 0.04, 1.0)
    decay = math.exp(-3.0 * position)
    return attack * decay


def samples() -> bytes:
    frames = bytearray()
    for note in NOTES:
        count = int(RATE * NOTE_SECONDS)
        for index in range(count):
            position = index / RATE
            # Fundamental plus a quiet octave and fifth for a warmer tone.
            value = (
                math.sin(2 * math.pi * note * position)
                + 0.28 * math.sin(2 * math.pi * note * 2 * position)
                + 0.12 * math.sin(2 * math.pi * note * 3 * position)
            )
            value *= AMPLITUDE * envelope(position)
            frames += struct.pack("<h", int(max(-1.0, min(1.0, value)) * 32767))
    return bytes(frames)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: sample-tone.py <output.wav>")
    with wave.open(sys.argv[1], "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(samples())


if __name__ == "__main__":
    main()
