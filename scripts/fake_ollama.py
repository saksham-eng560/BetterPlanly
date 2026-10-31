"""A scripted stand-in for Ollama's /api/chat, for demos and end-to-end tests without a model.

    python scripts/fake_ollama.py            # listens on :11434
    OLLAMA_BASE_URL=http://localhost:11434   # (the backend default)

Behaviour: day reviews and tick updates call replan_day, other messages get a
short canned reply, and after a tool result it summarises what the tool said.
It is deliberately dumb; the point is to exercise the real ChatOllama client,
tool execution, persistence and streaming.
"""

import json
import re
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = "fake-planner"


def decide(messages: list[dict]) -> dict:
    last = messages[-1]
    system = next((m["content"] for m in messages if m["role"] == "system"), "")
    today = (re.search(r"Now: \w+ (\d{4}-\d{2}-\d{2})", system) or [None, None])[1]
    if last["role"] == "tool":
        result = last["content"]
        if result.startswith("Moved:"):
            moves = result.splitlines()[1:]
            return {"content": f"Done — I moved {len(moves)} task{'s' * (len(moves) != 1)}:\n" + "\n".join(moves)}
        return {"content": f"All good: {result}"}
    text = last.get("content", "")
    if text.startswith("[day review]") and today:
        return {"tool_calls": [{"function": {"name": "replan_day", "arguments": {"date": today}}}]}
    if text.startswith("[update]") and today and "early" in text:
        return {"tool_calls": [{"function": {"name": "replan_day", "arguments": {"date": today, "pull_earlier": True}}}]}
    if text.startswith("[update]"):
        return {"content": "Nice work. The rest of today still fits, so I left it as is."}
    return {"content": "I'm a scripted demo model. Install Ollama and pull a real model for proper answers."}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # quieter
        sys.stderr.write("fake-ollama: " + fmt % args + "\n")

    def _json(self, body: dict, status: int = 200) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith("/api/tags"):
            return self._json({"models": [{"name": MODEL, "model": MODEL}]})
        self._json({"error": "not found"}, 404)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if not self.path.startswith("/api/chat"):
            return self._json({"error": "not found"}, 404)
        reply = decide(body.get("messages", []))
        now = datetime.now(timezone.utc).isoformat()
        message = {"role": "assistant", "content": reply.get("content", "")}
        if "tool_calls" in reply:
            message["tool_calls"] = reply["tool_calls"]
        chunks = []
        if body.get("stream", True) and message["content"]:
            for word in re.findall(r"\S+\s*", message["content"]):  # stream word by word
                chunks.append({"model": MODEL, "created_at": now, "message": {"role": "assistant", "content": word}, "done": False})
            message = {"role": "assistant", "content": ""}
        final = {
            "model": MODEL, "created_at": now, "message": message, "done": True, "done_reason": "stop",
            "total_duration": 1, "load_duration": 1, "prompt_eval_count": 1, "eval_count": 1,
        }
        if not body.get("stream", True):
            return self._json(final)
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.end_headers()
        for chunk in [*chunks, final]:
            self.wfile.write((json.dumps(chunk) + "\n").encode())
            self.wfile.flush()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 11434
    print(f"fake Ollama on http://localhost:{port}", file=sys.stderr)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
