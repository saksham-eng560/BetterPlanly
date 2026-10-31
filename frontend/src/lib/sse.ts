/** Read a POST Server-Sent Events response (EventSource only supports GET). */

export interface SseEvent {
  event: string;
  data: unknown;
}

/** Split complete SSE blocks out of `buffer`; returns parsed events and the unfinished remainder. */
export function parseSseChunk(buffer: string): { events: SseEvent[]; rest: string } {
  const events: SseEvent[] = [];
  const blocks = buffer.split("\n\n");
  const rest = blocks.pop() ?? "";
  for (const block of blocks) {
    let event = "message";
    const data: string[] = [];
    for (const line of block.split("\n")) {
      if (line.startsWith("event:")) event = line.slice(6).trim();
      else if (line.startsWith("data:")) data.push(line.slice(5).trimStart());
    }
    if (data.length) events.push({ event, data: JSON.parse(data.join("\n")) });
  }
  return { events, rest };
}

export async function* streamSse(response: Response): AsyncGenerator<SseEvent> {
  if (!response.body) return;
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  let buffer = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    const { events, rest } = parseSseChunk(buffer + value);
    buffer = rest;
    yield* events;
  }
}
