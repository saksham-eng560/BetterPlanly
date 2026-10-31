/** Local-date helpers. Planly dates are local wall-clock "YYYY-MM-DD" strings. */

const pad = (n: number) => String(n).padStart(2, "0");

export function isoDate(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function parseDate(iso: string): Date {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(y, m - 1, d);
}

export function addDays(iso: string, days: number): string {
  const d = parseDate(iso);
  d.setDate(d.getDate() + days);
  return isoDate(d);
}

export function today(): string {
  return isoDate(new Date());
}

/** Monday of the week containing `iso`. */
export function weekStart(iso: string): string {
  const d = parseDate(iso);
  return addDays(iso, -((d.getDay() + 6) % 7));
}

export function nextMonday(iso: string): string {
  return addDays(weekStart(iso), 7);
}

/** Local time with UTC offset, e.g. 2026-10-30T10:05:00+05:30 (what the agent expects). */
export function localNowIso(now = new Date()): string {
  const offset = -now.getTimezoneOffset();
  const sign = offset >= 0 ? "+" : "-";
  const abs = Math.abs(offset);
  return (
    `${isoDate(now)}T${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}` +
    `${sign}${pad(Math.floor(abs / 60))}:${pad(abs % 60)}`
  );
}

export function minutesOf(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return h * 60 + m;
}

/** Minutes since local midnight. */
export function nowMinutes(now = new Date()): number {
  return now.getHours() * 60 + now.getMinutes();
}

/** Share of [start, start + duration) elapsed at `now` (minutes since midnight); 0 outside it. */
export function elapsedShare(start: string | null, duration: number | null, now: number | null): number {
  if (now === null || !start || !duration) return 0;
  const from = minutesOf(start);
  return now >= from && now < from + duration ? (now - from) / duration : 0;
}

export function timeOf(minutes: number): string {
  return `${pad(Math.floor(minutes / 60) % 24)}:${pad(minutes % 60)}`;
}

export function formatDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (!h) return `${m}m`;
  return m ? `${h}h ${m}m` : `${h}h`;
}

export function endTime(start: string, duration: number | null): string | null {
  return duration ? timeOf(minutesOf(start) + duration) : null;
}

export function weekdayLong(iso: string): string {
  return parseDate(iso).toLocaleDateString(undefined, { weekday: "long" });
}

export function dayMonth(iso: string): string {
  return parseDate(iso).toLocaleDateString(undefined, { day: "numeric", month: "long" });
}

export function shortDay(iso: string): string {
  return parseDate(iso).toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
}

/** "Today", "Tomorrow", "Yesterday" or a short date. */
export function relativeDay(iso: string, todayIso = today()): string {
  if (iso === todayIso) return "Today";
  if (iso === addDays(todayIso, 1)) return "Tomorrow";
  if (iso === addDays(todayIso, -1)) return "Yesterday";
  return shortDay(iso);
}

export function timeAgo(isoDateTime: string, now = Date.now()): string {
  const seconds = Math.round((now - new Date(isoDateTime).getTime()) / 1000);
  if (seconds < 45) return "just now";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  return new Date(isoDateTime).toLocaleDateString(undefined, { day: "numeric", month: "short" });
}
