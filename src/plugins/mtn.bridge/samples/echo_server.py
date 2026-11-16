#!/usr/bin/env python3
"""Sample service process for the mtn.bridge plugin.

Reads one JSON message per line from stdin, writes one per line to stdout, and keeps
diagnostics on stderr. It offers two tools: "echo" and "slow_count" (reports progress
and honours cancellation).

Settings entry (plugin "Service bridge", "Servers"):
  [{"name": "sample", "command": "python", "args": ["C:/Tools/echo_server.py"]}]
"""
import json
import sys
import threading
import time

PROTOCOL = "2025-03-26"
TOOLS = [
    {
        "name": "echo",
        "description": "Returns the text it was given.",
        "inputSchema": {
            "type": "object",
            "properties": {"text": {"type": "string"}},
            "required": ["text"],
        },
    },
    {
        "name": "slow_count",
        "description": "Counts to n, one step per second, reporting progress.",
        "inputSchema": {
            "type": "object",
            "properties": {"n": {"type": "integer"}},
        },
    },
]

write_lock = threading.Lock()
cancelled = set()


def send(message):
    with write_lock:
        sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def reply(req_id, result):
    send({"jsonrpc": "2.0", "id": req_id, "result": result})


def fail(req_id, code, text):
    send({"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": text}})


def text_result(text, is_error=False):
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def run_tool(req_id, params):
    name = params.get("name")
    args = params.get("arguments") or {}
    token = (params.get("_meta") or {}).get("progressToken")
    if name == "echo":
        reply(req_id, text_result(str(args.get("text", ""))))
    elif name == "slow_count":
        n = int(args.get("n", 5))
        for i in range(1, n + 1):
            if req_id in cancelled:
                return
            time.sleep(1)
            if token is not None:
                send({"jsonrpc": "2.0", "method": "notifications/progress",
                      "params": {"progressToken": token, "progress": i, "total": n,
                                 "message": "step %d of %d" % (i, n)}})
        reply(req_id, text_result("counted to %d" % n))
    else:
        reply(req_id, text_result("unknown tool " + str(name), True))


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            print("bad json: " + line, file=sys.stderr)
            continue
        method = msg.get("method")
        req_id = msg.get("id")
        if method == "initialize":
            reply(req_id, {"protocolVersion": PROTOCOL, "capabilities": {"tools": {}},
                           "serverInfo": {"name": "sample", "version": "1"}})
        elif method == "tools/list":
            reply(req_id, {"tools": TOOLS})
        elif method == "tools/call":
            threading.Thread(target=run_tool, args=(req_id, msg.get("params") or {}),
                             daemon=True).start()
        elif method == "notifications/cancelled":
            cancelled.add((msg.get("params") or {}).get("requestId"))
        elif method == "ping":
            reply(req_id, {})
        elif req_id is not None:
            fail(req_id, -32601, "method not found")


if __name__ == "__main__":
    main()
