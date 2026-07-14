  if (window.S3RPENT_EMBED && window.s3rpentAudio && window.s3rpentAudio.playing) {
    var rb = clamp01(window.s3rpentAudio.bass || 0);
    var rm = clamp01(window.s3rpentAudio.mid || 0);
    var rt = clamp01(window.s3rpentAudio.treble || 0);
    var re = clamp01(window.s3rpentAudio.energy || 0);
    var voc = clamp01(window.s3rpentAudio.vocal != null ? window.s3rpentAudio.vocal : rm * 0.45);
    var bassOnset = Math.max(0, rb - smoothBass);
    var energyOnset = Math.max(0, re - prevEnergy);
    prevEnergy = prevEnergy * 0.88 + re * 0.12;
    beatPulse *= Math.pow(0.36, dt);
    if ((window.s3rpentAudio.beat || 0) > 0.45) {
      beatPulse = Math.max(beatPulse, clamp01(window.s3rpentAudio.beat) * 0.55);
      beatOnsetFlag = true;
    } else if (bassOnset > 0.075 && rb > 0.32 && energyOnset > 0.020) {
      beatPulse = Math.max(beatPulse, Math.min(0.12, bassOnset * 0.18));
    }
    tickPodcastDjBeatMap();
    tickBeatMap();
    if (scheduledBeatFlag) {
      beatOnsetFlag = true;
      scheduledBeatFlag = false;
    }
    if (scheduledBeatPulse > beatPulse) beatPulse = scheduledBeatPulse;
    scheduledBeatPulse *= Math.pow(0.32, dt);
    function env(prev, next, attack, release) {
      var k = next > prev ? attack : release;
      return prev + (next - prev) * k;
    }
    smoothBass  = env(smoothBass, Math.min(0.82, rb * 0.78 + re * 0.025), 0.28, 0.075);
    smoothMid   = env(smoothMid,  Math.min(0.68, rm * 0.64 + re * 0.025), 0.18, 0.060);
    smoothTreb  = env(smoothTreb, Math.min(0.56, rt * 0.54), 0.18, 0.055);
    smoothEnergy= env(smoothEnergy, Math.min(0.72, re), 0.16, 0.055);
    updateCinemaDynamics(re, rb);
    updateCinemaTrackProfile({ energy: re, low: rb, vocal: voc, melody: rm, lowOnset: bassOnset, energyOnset: energyOnset });
    var sunEnergy = clamp01((smoothEnergy - 0.18) / 0.38);
    var sunVoice = clamp01((voc - 0.11) / 0.34);
    var sunMelody = clamp01((smoothMid - 0.16) / 0.27);
    var sunAir = clamp01((smoothTreb - 0.105) / 0.17);
    var sunRaw = clamp01(sunEnergy * 0.36 + sunVoice * 0.18 + sunMelody * 0.26 + sunAir * 0.20);
    sunRaw = sunRaw * sunRaw * (3 - 2 * sunRaw);
    lyricSunAvg += (sunRaw - lyricSunAvg) * 0.006;
    lyricSunPeak = Math.max(0.48, lyricSunPeak * 0.9985, sunRaw);
    var sunThreshold = Math.max(0.78, lyricSunAvg + 0.20, lyricSunPeak * 0.74);
    var sunGate = clamp01((sunRaw - sunThreshold) / Math.max(0.08, 1.0 - sunThreshold));
    sunGate = sunGate * sunGate * (3 - 2 * sunGate);
    lyricSunHold += (sunGate - lyricSunHold) * (sunGate > lyricSunHold ? 0.035 : 0.014);
    lyricSunTarget = lyricSunHold > 0.16 ? clamp01((lyricSunHold - 0.16) / 0.84) : 0;
    lyricSunEnergy += (lyricSunTarget - lyricSunEnergy) * (lyricSunTarget > lyricSunEnergy ? 0.075 : 0.030);
  } else if (analyser && playing && audio && !audio.paused) {
