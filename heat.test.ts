import { describe, expect, it } from 'vitest';

import { evaluateHeat, heatIndexC, highRiskHours, isHeatSeason } from './heat';

const reading = (temperatureC: number, relativeHumidityPct: number) => ({
  temperatureC,
  relativeHumidityPct,
  observedAt: '2026-07-15T06:00:00.000Z',
  source: 'test',
});

describe('heatIndexC', () => {
  it('is close to air temperature in dry, mild conditions', () => {
    expect(heatIndexC(24, 30)).toBeGreaterThan(20);
    expect(heatIndexC(24, 30)).toBeLessThan(28);
  });

  it('rises sharply with humidity, which is the UAE coastal problem', () => {
    const dry = heatIndexC(38, 20);
    const humid = heatIndexC(38, 70);
    expect(humid).toBeGreaterThan(dry + 10);
  });

  it('reports a brutal apparent temperature for a Dubai August morning', () => {
    // 38C at 65% humidity is an ordinary August morning on the coast here.
    expect(heatIndexC(38, 65)).toBeGreaterThan(50);
  });
});

describe('evaluateHeat', () => {
  const advise = { policy: 'advise' as const, thresholdC: 40 };

  it('flags green in winter conditions', () => {
    const r = evaluateHeat(reading(24, 45), advise);
    expect(r.flag).toBe('green');
    expect(r.suggestIndoorAlternatives).toBe(false);
    expect(r.shouldAutoCancel).toBe(false);
  });

  it('flags red on a humid summer morning', () => {
    const r = evaluateHeat(reading(38, 65), advise);
    expect(r.flag).toBe('red');
    expect(r.messageKey).toBe('heat.advisory.red');
    expect(r.suggestIndoorAlternatives).toBe(true);
  });

  it('does not cancel under an advise-only policy', () => {
    const r = evaluateHeat(reading(40, 70), advise);
    expect(r.shouldAutoCancel).toBe(false);
  });

  it('cancels when the organiser chose auto_cancel and the threshold is passed', () => {
    const r = evaluateHeat(reading(40, 70), { policy: 'auto_cancel', thresholdC: 40 });
    expect(r.shouldAutoCancel).toBe(true);
  });

  it('keeps the reading on the advisory for the audit trail', () => {
    // An organiser who cancelled on a recorded reading is in a materially
    // better position than one who did not.
    const r = evaluateHeat(reading(41, 60), advise);
    expect(r.reading.source).toBe('test');
    expect(r.reading.observedAt).toBe('2026-07-15T06:00:00.000Z');
  });
});

describe('isHeatSeason', () => {
  it('covers May through September', () => {
    expect(isHeatSeason(new Date('2026-05-01T08:00:00Z'))).toBe(true);
    expect(isHeatSeason(new Date('2026-08-01T08:00:00Z'))).toBe(true);
    expect(isHeatSeason(new Date('2026-09-30T08:00:00Z'))).toBe(true);
    expect(isHeatSeason(new Date('2026-01-15T08:00:00Z'))).toBe(false);
    expect(isHeatSeason(new Date('2026-11-15T08:00:00Z'))).toBe(false);
  });

  it('greys out midday only in heat season', () => {
    expect(highRiskHours(new Date('2026-07-01T08:00:00Z'))).toEqual({ from: 10, to: 17 });
    expect(highRiskHours(new Date('2026-12-01T08:00:00Z'))).toBeNull();
  });
});
