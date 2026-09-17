"""ShowdUp sound design, synthesized from scratch (no samples, no licences).

    python tool/sounds/synth.py

Writes OGG files into android/app/src/main/res/raw/. Every sound is built from
the same small palette: a marimba-like wooden tone for UI, a soft bell for
alarms and wins, and filtered air for movement. Needs numpy and ffmpeg.
"""

import os
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'android', 'app', 'src', 'main', 'res', 'raw')


def t_axis(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def env(t, attack, decay):
    attack_curve = 1 - np.exp(-t / max(attack, 1e-4))
    return attack_curve * np.exp(-t / decay)


def note(name):
    names = {'C': -9, 'C#': -8, 'D': -7, 'D#': -6, 'E': -5, 'F': -4, 'F#': -3,
             'G': -2, 'G#': -1, 'A': 0, 'A#': 1, 'B': 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + (octave - 4) * 12) / 12)


def marimba(freq, seconds=0.6, bright=1.0):
    """Wooden bar: a fundamental plus the tuned 4th and 10th partials."""
    t = t_axis(seconds)
    # Decay fits inside the clip, so short UI sounds end on silence, not a cut.
    ring = min(0.42, seconds / 5)
    partials = [(1.0, 1.0, ring), (3.93, 0.32 * bright, ring / 4.5), (10.6, 0.07 * bright, ring / 16)]
    tone = sum(a * np.sin(2 * np.pi * freq * r * t) * env(t, 0.0015, d) for r, a, d in partials)
    click = np.random.default_rng(7).normal(0, 1, len(t)) * env(t, 0.0003, 0.004) * 0.15
    return tone + click


def bell(freq, seconds=1.6, soft=1.0):
    """Soft bell: inharmonic partials that ring and fade at different rates."""
    t = t_axis(seconds)
    partials = [(0.5, 0.18, 1.1), (1.0, 1.0, 0.9), (2.0, 0.42 * soft, 0.55),
                (2.76, 0.30 * soft, 0.38), (5.4, 0.12 * soft, 0.16), (8.93, 0.05 * soft, 0.07)]
    shimmer = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
    return sum(a * np.sin(2 * np.pi * freq * r * t * shimmer) * env(t, 0.002, d) for r, a, d in partials)


def pluck(freq, seconds=0.5, damping=0.996):
    """Karplus-Strong string, for the moment something lands."""
    n = int(RATE * seconds)
    period = int(RATE / freq)
    buf = np.random.default_rng(3).uniform(-1, 1, period)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = damping * 0.5 * (buf[i % period] + buf[(i + 1) % period])
    return out * env(t_axis(seconds), 0.001, seconds * 0.4)


def air(seconds, start_hz, end_hz, q=1.2, loud=1.0, seed=11):
    """Filtered noise sweeping from start_hz to end_hz: a soft whoosh."""
    n = int(RATE * seconds)
    noise = np.random.default_rng(seed).normal(0, 1, n)
    out = np.zeros(n)
    z1 = z2 = 0.0
    for i in range(n):
        f = start_hz * (end_hz / start_hz) ** (i / n)
        w0 = 2 * np.pi * f / RATE
        alpha = np.sin(w0) / (2 * q)
        b0, a0 = alpha, 1 + alpha
        a1, a2 = -2 * np.cos(w0), 1 - alpha
        x = noise[i]
        # Direct form II transposed band-pass.
        y = (b0 / a0) * x + z1
        z1 = -(a1 / a0) * y + z2
        z2 = -(b0 / a0) * x - (a2 / a0) * y
        out[i] = y
    shape = np.sin(np.pi * np.linspace(0, 1, n)) ** 1.6
    return out * shape * loud


def mix(length, *parts):
    """parts: (signal, offset_seconds, gain)."""
    out = np.zeros(int(RATE * length))
    for signal, offset, gain in parts:
        start = int(RATE * offset)
        end = min(len(out), start + len(signal))
        out[start:end] += signal[: end - start] * gain
    return out


def lowpass(signal, cutoff):
    alpha = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    out = np.zeros_like(signal)
    y = 0.0
    for i, x in enumerate(signal):
        y += alpha * (x - y)
        out[i] = y
    return out


def finish(signal, peak_db, fade_ms=6):
    fade = int(RATE * fade_ms / 1000)
    signal = signal.copy()
    signal[:fade] *= np.linspace(0, 1, fade)
    signal[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(signal)) or 1
    return signal / peak * 10 ** (peak_db / 20)


def write(name, signal, peak_db):
    data = finish(signal, peak_db)
    pcm = (np.clip(data, -1, 1) * 32767).astype('<i2')
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + '.wav')
        with wave.open(wav, 'wb') as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes(pcm.tobytes())
        target = os.path.join(OUT, name + '.ogg')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '6', target], check=True)
    print(f'{name}.ogg  {len(data) / RATE:.2f}s')


def main():
    # UI: short, soft, woody. Quiet so they sit under everything else.
    write('ui_tap', lowpass(marimba(note('G5'), 0.16, bright=0.6), 5000), -16)
    write('ui_select', lowpass(marimba(note('D6'), 0.13, bright=0.4), 7000), -18)
    write('ui_toggle_on', mix(0.22, (marimba(note('E5'), 0.12), 0, 1), (marimba(note('B5'), 0.16), 0.055, 0.9)), -15)
    write('ui_toggle_off', mix(0.22, (marimba(note('B5'), 0.12), 0, 0.9), (marimba(note('E5'), 0.16), 0.055, 1)), -16)
    write('ui_page', air(0.2, 900, 3200, q=0.9, loud=1.0), -24)
    write('hold_tick', lowpass(marimba(note('A5'), 0.1, bright=0.3), 6000), -19)
    write('ui_error', mix(0.34, (marimba(note('D4'), 0.18, bright=0.5), 0, 1), (marimba(note('A3'), 0.22, bright=0.5), 0.1, 1)), -14)

    # The flip: air rising into a plucked landing.
    write('flip', mix(0.62, (air(0.34, 500, 4200, q=1.4, loud=1.0), 0, 0.55),
                      (pluck(note('C6'), 0.3), 0.28, 0.8), (marimba(note('G6'), 0.25, bright=0.5), 0.3, 0.35)), -9)

    # Caught: a low wooden knock with a muted bell behind it.
    write('caught', mix(0.5, (lowpass(marimba(note('C3'), 0.3, bright=0.2), 1400), 0, 1.0),
                        (bell(note('G4'), 0.45, soft=0.3), 0.02, 0.28)), -8)

    # Showed up: a bright marimba arpeggio resolving on a bell, with air.
    arpeggio = mix(2.0, (marimba(note('C5'), 0.5), 0, 0.9), (marimba(note('E5'), 0.5), 0.07, 0.85),
                   (marimba(note('G5'), 0.5), 0.14, 0.85), (bell(note('C6'), 1.7, soft=0.7), 0.21, 0.6),
                   (air(0.5, 3000, 9000, q=0.7, loud=0.4), 0.18, 0.25))
    write('release', arpeggio, -6)

    # A single alarm bell, for the story and the ringing mark.
    write('ding', bell(note('E5'), 2.0, soft=0.8), -8)

    # Logo sting: ring, ring, whoosh, land.
    write('intro', mix(3.0, (bell(note('E5'), 0.9, soft=0.6), 0.0, 0.55), (bell(note('E5'), 0.9, soft=0.6), 0.28, 0.45),
                       (air(0.45, 400, 5200, q=1.3, loud=1.0), 0.95, 0.5),
                       (pluck(note('G5'), 0.5), 1.36, 0.7), (marimba(note('C5'), 0.7), 1.36, 0.7),
                       (marimba(note('G5'), 0.7), 1.44, 0.5), (bell(note('C6'), 1.45, soft=0.5), 1.52, 0.4)), -7)

    # The alarm: a rising marimba figure that loops cleanly every 2.4 seconds.
    figure = [('C5', 0.0), ('E5', 0.15), ('G5', 0.30), ('C6', 0.45), ('G5', 0.75), ('C6', 0.9), ('E6', 1.05)]
    parts = [(marimba(note(n), 0.55), at, 0.8) for n, at in figure]
    parts.append((bell(note('C6'), 1.0, soft=0.6), 1.05, 0.45))
    write('alarm_showdup', mix(2.4, *parts), -1.5)


if __name__ == '__main__':
    main()
