"""Analyze sliced snd-lib SND01 tap/type samples: duration, envelope, spectral peaks."""
import glob
import numpy as np
from scipy.io import wavfile
from scipy.signal import find_peaks

for path in sorted(glob.glob("samples/tap_*.wav") + glob.glob("samples/type_*.wav")):
    sr, x = wavfile.read(path)
    x = x.astype(np.float64) / 32768.0
    # trim trailing silence for effective duration
    env = np.abs(x)
    peak = env.max()
    above = np.where(env > peak * 0.01)[0]
    eff_dur = (above[-1] - above[0]) / sr if len(above) else 0.0
    peak_idx = env.argmax()
    attack_ms = peak_idx / sr * 1000
    # envelope in 2ms windows
    w = int(sr * 0.002)
    frames = [env[i:i + w].max() for i in range(0, len(env), w)]
    # time to decay to 10% of peak after the peak
    dec = None
    for i in range(peak_idx, len(env)):
        if env[i:i + w].max() < peak * 0.1:
            dec = (i - peak_idx) / sr * 1000
            break
    # spectrum
    X = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freqs = np.fft.rfftfreq(len(x), 1 / sr)
    pk, props = find_peaks(X, height=X.max() * 0.05, distance=8)
    order = np.argsort(props["peak_heights"])[::-1][:5]
    top = [(round(freqs[pk[i]], 1), round(props["peak_heights"][i] / X.max(), 3)) for i in order]
    envstr = " ".join(f"{v:.2f}" for v in frames[:25])
    print(f"{path}: sr={sr} peak={peak:.3f} eff_dur={eff_dur*1000:.1f}ms "
          f"attack={attack_ms:.1f}ms decay_to_10pct={dec if dec is None else round(dec,1)}ms")
    print(f"  top5_peaks(Hz,rel): {top}")
    print(f"  env2ms: {envstr}")
