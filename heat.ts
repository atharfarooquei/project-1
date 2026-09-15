/**
 * NABD :: outdoor heat advisory
 *
 * Every UAE fitness product treats the summer as a churn problem. It is
 * actually an unbuilt feature. From May to September outdoor training here is
 * genuinely hazardous between roughly 10:00 and 17:00, and the difference
 * between a run club that people trust and one they quietly leave is whether
 * it tells them so.
 *
 * This is also a liability reduction: an organiser who cancelled on a
 * recorded reading is in a materially better position than one who did not.
 * Every advisory decision is snapshotted onto the meet occurrence.
 *
 * Note on the science: this uses the US National Weather Service heat index
 * (Rothfusz regression), which is an apparent-temperature model for shade.
 * It is not WBGT, which additionally accounts for solar radiation and wind
 * and is the correct measure for athletes in direct sun. Treat the thresholds
 * below as conservative product defaults, not as a medical standard, and have
 * them reviewed before they gate anything safety-critical.
 */

import type { HeatFlag } from '../types/domain';

export interface WeatherReading {
  temperatureC: number;
  relativeHumidityPct: number;
  windSpeedKmh?: number;
  uvIndex?: number;
  observedAt: string;
  source: string;
}

/** Apparent temperature in Celsius (NWS heat index, converted). */
export function heatIndexC(temperatureC: number, relativeHumidityPct: number): number {
  const t = (temperatureC * 9) / 5 + 32;
  const r = relativeHumidityPct;

  // Below roughly 27C the regression is not meaningful; a simple average is
  // closer to reality.
  if (t < 80) {
    const simple = 0.5 * (t + 61 + (t - 68) * 1.2 + r * 0.094);
    return Math.round((((simple + t) / 2 - 32) * 5) / 9 * 10) / 10;
  }

  let hi =
    -42.379 +
    2.04901523 * t +
    10.14333127 * r -
    0.22475541 * t * r -
    0.00683783 * t * t -
    0.05481717 * r * r +
    0.00122874 * t * t * r +
    0.00085282 * t * r * r -
    0.00000199 * t * t * r * r;

  // NWS adjustments at the extremes.
  if (r < 13 && t >= 80 && t <= 112) {
    hi -= ((13 - r) / 4) * Math.sqrt((17 - Math.abs(t - 95)) / 17);
  } else if (r > 85 && t >= 80 && t <= 87) {
    hi += ((r - 85) / 10) * ((87 - t) / 5);
  }

  return Math.round((((hi - 32) * 5) / 9) * 10) / 10;
}

export interface HeatAdvisory {
  flag: HeatFlag;
  heatIndexC: number;
  /** i18n key for the member-facing message. */
  messageKey: string;
  /** True when the meet's `auto_cancel` policy should fire. */
  shouldAutoCancel: boolean;
  /** Surfaced alongside the advisory when conditions are amber or worse. */
  suggestIndoorAlternatives: boolean;
  reading: WeatherReading;
}

export interface HeatPolicyConfig {
  policy: 'none' | 'advise' | 'auto_cancel';
  /** Apparent-temperature threshold above which the policy fires. */
  thresholdC: number;
}

const AMBER_C = 35;
const RED_C = 41;

export function evaluateHeat(
  reading: WeatherReading,
  config: HeatPolicyConfig,
): HeatAdvisory {
  const hi = heatIndexC(reading.temperatureC, reading.relativeHumidityPct);

  let flag: HeatFlag = 'green';
  if (hi >= RED_C) flag = 'red';
  else if (hi >= AMBER_C) flag = 'amber';

  const overThreshold = hi >= config.thresholdC;

  return {
    flag,
    heatIndexC: hi,
    messageKey:
      flag === 'red'
        ? 'heat.advisory.red'
        : flag === 'amber'
          ? 'heat.advisory.amber'
          : 'heat.advisory.green',
    shouldAutoCancel: config.policy === 'auto_cancel' && overThreshold,
    suggestIndoorAlternatives: flag !== 'green',
    reading,
  };
}

/**
 * Whether outdoor meets in this month should default to a heat policy at all.
 * Used to pick sensible defaults when a host creates a meet, so the safe
 * setting is the one they get without thinking about it.
 */
export function isHeatSeason(date: Date, timeZone = 'Asia/Dubai'): boolean {
  const month = Number(
    new Intl.DateTimeFormat('en-GB', { timeZone, month: 'numeric' }).format(date),
  );
  return month >= 5 && month <= 9;
}

/**
 * Daylight windows worth avoiding in heat season. Returned as local hours so
 * the scheduling UI can grey them out rather than merely warn after the fact.
 */
export function highRiskHours(date: Date): { from: number; to: number } | null {
  return isHeatSeason(date) ? { from: 10, to: 17 } : null;
}
