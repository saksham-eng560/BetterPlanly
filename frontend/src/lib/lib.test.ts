import { describe, expect, it } from "vitest";

import { addDays, endTime, formatDuration, localNowIso, nextMonday, relativeDay, weekStart } from "./dates";
import { parseSseChunk } from "./sse";

describe("dates", () => {
  it("does week arithmetic in local dates", () => {
    expect(weekStart("2026-10-30")).toBe("2026-10-26"); // Friday → Monday
    expect(weekStart("2026-11-01")).toBe("2026-10-26"); // Sunday belongs to the same week
    expect(nextMonday("2026-10-30")).toBe("2026-11-02");
    expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
  });

  it("formats durations and end times", () => {
    expect(formatDuration(90)).toBe("1h 30m");
    expect(formatDuration(45)).toBe("45m");
    expect(formatDuration(120)).toBe("2h");
    expect(endTime("09:30", 90)).toBe("11:00");
    expect(endTime("09:30", null)).toBeNull();
  });

  it("names nearby days", () => {
    expect(relativeDay("2026-10-30", "2026-10-30")).toBe("Today");
    expect(relativeDay("2026-10-31", "2026-10-30")).toBe("Tomorrow");
    expect(relativeDay("2026-10-29", "2026-10-30")).toBe("Yesterday");
  });

  it("sends local time with its UTC offset", () => {
    expect(localNowIso(new Date(2026, 9, 30, 10, 5, 0))).toMatch(/^2026-10-30T10:05:00[+-]\d\d:\d\d$/);
  });
});

describe("parseSseChunk", () => {
  it("parses complete events and keeps the remainder", () => {
    const { events, rest } = parseSseChunk(
      'event: token\ndata: {"text": "Hi"}\n\nevent: done\ndata: {}\n\nevent: tok',
    );
    expect(events).toEqual([
      { event: "token", data: { text: "Hi" } },
      { event: "done", data: {} },
    ]);
    expect(rest).toBe("event: tok");
  });
});
