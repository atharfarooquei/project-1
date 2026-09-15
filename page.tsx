'use client';

/**
 * NABD :: partner reception screen
 *
 * One screen, meant to sit on a tablet at a gym front desk all day.
 *
 * Two halves, and both matter:
 *  - A rotating QR the member scans. Large enough to read across a counter.
 *  - A live feed of who just came in, with photo and tier, so the receptionist
 *    can see a mismatch. Without the feed the receptionist has no idea whether
 *    the person walking past actually checked in, and they will stop trusting
 *    the system within a week.
 *
 * Also here: the pause switch. A partner who can stop aggregator access
 * themselves at 7pm on a bad night is a partner who stays, and that control is
 * worth more to retention than any rate negotiation.
 */

import { use, useCallback, useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';

interface CodeResponse {
  payload: string;
  windowSeconds: number;
  expiresInSeconds: number;
}

interface RecentVisit {
  id: string;
  displayName: string;
  avatarUrl: string | null;
  tier: string;
  checkedInAt: string;
  status: 'granted' | 'denied';
  denialReason: string | null;
}

export default function ReceptionPage({
  params,
}: {
  params: Promise<{ venueId: string }>;
}) {
  // Next 15 passes route params as a promise; a client component unwraps it
  // with use() rather than awaiting.
  const { venueId } = use(params);

  const [code, setCode] = useState<CodeResponse | null>(null);
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const [secondsLeft, setSecondsLeft] = useState(0);
  const [recent, setRecent] = useState<RecentVisit[]>([]);
  const [isPaused, setPaused] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const fetchCode = useCallback(async () => {
    try {
      const response = await fetch(`/api/partner/venues/${venueId}/checkin-code`, {
        cache: 'no-store',
      });
      if (!response.ok) throw new Error('code fetch failed');
      const next = (await response.json()) as CodeResponse;

      setCode(next);
      setSecondsLeft(next.expiresInSeconds);
      setQrDataUrl(
        await QRCode.toDataURL(next.payload, {
          width: 720,
          margin: 1,
          errorCorrectionLevel: 'M',
          color: { dark: '#07090E', light: '#FFFFFF' },
        }),
      );
      setError(null);

      // Schedule the next fetch for just after this code rotates, rather than
      // on a fixed interval, so the displayed code is never stale.
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => void fetchCode(), (next.expiresInSeconds + 1) * 1000);
    } catch {
      setError('Could not refresh the check-in code. Retrying.');
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => void fetchCode(), 5000);
    }
  }, [venueId]);

  useEffect(() => {
    void fetchCode();
    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
  }, [fetchCode]);

  // Countdown ring.
  useEffect(() => {
    const tick = setInterval(() => setSecondsLeft((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(tick);
  }, []);

  // Live check-in feed.
  useEffect(() => {
    const poll = setInterval(async () => {
      try {
        const response = await fetch(`/api/partner/venues/${venueId}/recent-visits`, {
          cache: 'no-store',
        });
        if (response.ok) setRecent(((await response.json()).items ?? []) as RecentVisit[]);
      } catch {
        // A stale feed is tolerable; a crashed reception screen is not.
      }
    }, 5000);
    return () => clearInterval(poll);
  }, [venueId]);

  const togglePause = useCallback(async () => {
    const next = !isPaused;
    setPaused(next);
    await fetch(`/api/partner/venues/${venueId}/pause`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ paused: next, reason: next ? 'Paused at reception' : null }),
    });
  }, [isPaused, venueId]);

  const progress = code ? secondsLeft / code.windowSeconds : 0;

  return (
    <main className="flex min-h-screen bg-[#07090E] text-[#F2F4F7]">
      {/* Code panel */}
      <section className="flex flex-1 flex-col items-center justify-center gap-8 p-12">
        <h1 className="text-center text-3xl font-semibold tracking-tight">
          Scan to check in
          <span className="mt-2 block text-lg font-normal text-[#9AA4B2]" dir="rtl">
            امسح الرمز لتسجيل الدخول
          </span>
        </h1>

        <div className="relative rounded-3xl bg-white p-6 shadow-2xl">
          {qrDataUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={qrDataUrl} alt="Check-in code" className="h-[420px] w-[420px]" />
          ) : (
            <div className="h-[420px] w-[420px] animate-pulse rounded-2xl bg-[#EDEFF3]" />
          )}

          {isPaused ? (
            <div className="absolute inset-0 flex items-center justify-center rounded-3xl bg-[#07090E]/90">
              <p className="text-xl font-semibold text-[#E5624A]">Pass access paused</p>
            </div>
          ) : null}
        </div>

        {/* Countdown. Tells the member the code is live, which is what stops
            them photographing it and trying again tomorrow. */}
        <div className="w-[420px]">
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-[#1C2431]">
            <div
              className="h-full rounded-full bg-[#F0A73B] transition-[width] duration-1000 ease-linear"
              style={{ width: `${progress * 100}%` }}
            />
          </div>
          <p className="mt-3 text-center text-sm text-[#667085]">
            Code refreshes in {secondsLeft}s
          </p>
        </div>

        {error ? <p className="text-sm text-[#E5624A]">{error}</p> : null}
      </section>

      {/* Activity panel */}
      <aside className="flex w-[380px] flex-col border-l border-white/10 bg-[#0D1117]">
        <header className="flex items-center justify-between border-b border-white/10 p-6">
          <h2 className="text-lg font-semibold">Just checked in</h2>
          <button
            type="button"
            onClick={togglePause}
            className={`rounded-full px-4 py-2 text-xs font-semibold transition ${
              isPaused
                ? 'bg-[#E5624A] text-[#07090E]'
                : 'border border-white/20 text-[#9AA4B2] hover:border-[#E5624A] hover:text-[#E5624A]'
            }`}
          >
            {isPaused ? 'Resume access' : 'Pause access'}
          </button>
        </header>

        <ul className="flex-1 divide-y divide-white/5 overflow-y-auto">
          {recent.length === 0 ? (
            <li className="p-6 text-sm text-[#667085]">Nobody yet today.</li>
          ) : (
            recent.map((visit) => (
              <li key={visit.id} className="flex items-center gap-3 p-4">
                {visit.avatarUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={visit.avatarUrl}
                    alt=""
                    className="h-11 w-11 rounded-full object-cover"
                  />
                ) : (
                  <div className="h-11 w-11 rounded-full bg-[#1C2431]" />
                )}

                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{visit.displayName}</p>
                  <p className="text-xs text-[#667085]">
                    {new Date(visit.checkedInAt).toLocaleTimeString('en-AE', {
                      timeZone: 'Asia/Dubai',
                      hour: '2-digit',
                      minute: '2-digit',
                    })}
                    {' · '}
                    {visit.tier}
                  </p>
                </div>

                {visit.status === 'granted' ? (
                  <span className="rounded-full bg-[#3FB984]/15 px-2.5 py-1 text-[11px] font-semibold text-[#3FB984]">
                    In
                  </span>
                ) : (
                  // Denials appear here too. The receptionist is the person
                  // the member complains to, so they need to see the reason
                  // before the member reaches the desk.
                  <span className="rounded-full bg-[#E5624A]/15 px-2.5 py-1 text-[11px] font-semibold text-[#E5624A]">
                    {visit.denialReason?.replaceAll('_', ' ') ?? 'Denied'}
                  </span>
                )}
              </li>
            ))
          )}
        </ul>

        <footer className="border-t border-white/10 p-4 text-xs text-[#667085]">
          Phone flat or app not working? Use manual override in the dashboard. Every override is
          recorded with a reason.
        </footer>
      </aside>
    </main>
  );
}
