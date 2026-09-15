/**
 * NABD :: internationalisation
 *
 * English and Arabic from the first commit, not as a retrofit. Roughly a
 * third of this market reads Arabic first, and a product that bolts RTL on in
 * v2 ends up with a layout that never quite works.
 */

import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';

import en from './locales/en.json';
import ar from './locales/ar.json';

export const SUPPORTED_LOCALES = ['en', 'ar'] as const;
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

export const RTL_LOCALES: SupportedLocale[] = ['ar'];

export function isRTL(locale: string): boolean {
  return RTL_LOCALES.includes(locale as SupportedLocale);
}

export const resources = {
  en: { translation: en },
  ar: { translation: ar },
} as const;

export function initI18n(locale: SupportedLocale = 'en') {
  if (!i18n.isInitialized) {
    void i18n.use(initReactI18next).init({
      resources,
      lng: locale,
      fallbackLng: 'en',
      compatibilityJSON: 'v4',
      interpolation: { escapeValue: false },
      returnNull: false,
    });
  }
  return i18n;
}

export default i18n;

// ---------------------------------------------------------------------------
// Formatters
// ---------------------------------------------------------------------------

/**
 * Distances are always presented in kilometres to one decimal place under
 * 10km and whole numbers above, because "12.4 km away" is noise and
 * "0.8 km away" is the difference between going and not going.
 */
export function formatDistanceKm(km: number, locale: SupportedLocale): string {
  const value = km < 10 ? Number(km.toFixed(1)) : Math.round(km);
  return new Intl.NumberFormat(locale === 'ar' ? 'ar-AE' : 'en-AE', {
    maximumFractionDigits: km < 10 ? 1 : 0,
  }).format(value);
}

export function formatAED(amount: number, locale: SupportedLocale): string {
  return new Intl.NumberFormat(locale === 'ar' ? 'ar-AE' : 'en-AE', {
    style: 'currency',
    currency: 'AED',
    maximumFractionDigits: amount % 1 === 0 ? 0 : 2,
  }).format(amount);
}

export function formatTime(date: Date, locale: SupportedLocale): string {
  return new Intl.DateTimeFormat(locale === 'ar' ? 'ar-AE' : 'en-AE', {
    timeZone: 'Asia/Dubai',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date);
}

export function formatDayAndTime(date: Date, locale: SupportedLocale): string {
  return new Intl.DateTimeFormat(locale === 'ar' ? 'ar-AE' : 'en-AE', {
    timeZone: 'Asia/Dubai',
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date);
}

/** Running pace, seconds per km, as m:ss. */
export function formatPace(secondsPerKm: number): string {
  const m = Math.floor(secondsPerKm / 60);
  const s = Math.round(secondsPerKm % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}
