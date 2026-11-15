#!/usr/bin/env python3
"""Runs Lua in the running JA3 debug build through the DAP evaluate request and prints the result.

Usage:
    lua.py FILE          run the Lua block in FILE
    lua.py < block.lua   run the Lua block from stdin
    lua.py -e EXPR       evaluate one expression

Prints "OK <result>" and exits 0, or prints "FAIL <error>" and exits 1.
The port is JA3_PORT, default 8165. Uses only the standard library, so it runs on Linux and Windows.
"""
import json
import os
import socket
import sys


def send(sock: socket.socket, seq: int, command: str, arguments: dict) -> None:
    body = json.dumps({"seq": seq, "type": "request", "command": command, "arguments": arguments}).encode()
    sock.sendall(b"Content-Length: %d\r\n\r\n" % len(body) + body)


def recv_response(sock: socket.socket, buf: bytes, request_seq: int) -> tuple[dict, bytes]:
    """Reads messages until the response to request_seq arrives, and drops the events before it."""
    while True:
        while b"\r\n\r\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                raise ConnectionError("the debugger closed the connection")
            buf += chunk
        head, buf = buf.split(b"\r\n\r\n", 1)
        length = int(head.split(b"Content-Length:")[1].strip().split(b"\r\n")[0])
        while len(buf) < length:
            buf += sock.recv(65536)
        msg, buf = json.loads(buf[:length]), buf[length:]
        if msg.get("type") == "response" and msg.get("request_seq") == request_seq:
            return msg, buf


def evaluate(expression: str, port: int) -> tuple[bool, str]:
    with socket.create_connection(("127.0.0.1", port), timeout=60) as sock:
        buf = b""
        send(sock, 1, "initialize", {"adapterID": "ja3-play"})
        _, buf = recv_response(sock, buf, 1)
        send(sock, 2, "attach", {})
        _, buf = recv_response(sock, buf, 2)
        send(sock, 3, "evaluate", {"expression": expression, "context": "repl"})
        msg, buf = recv_response(sock, buf, 3)
        send(sock, 4, "disconnect", {})
    result = msg.get("message") or (msg.get("body") or {}).get("result") or ""
    # Strings have a metatable in this engine, and the debugger prints it after the value.
    return bool(msg.get("success")), str(result).split(" {\n\tmetatable")[0]


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["-e"] and len(args) == 2:
        expression = args[1]
    elif len(args) == 1:
        with open(args[0], encoding="utf-8") as f:
            expression = "(function()\n" + f.read() + "\nend)()"
    elif not args:
        expression = "(function()\n" + sys.stdin.read() + "\nend)()"
    else:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        ok, result = evaluate(expression, int(os.environ.get("JA3_PORT", "8165")))
    except ConnectionRefusedError:
        print("FAIL no debugger on the port. Start the game with scripts/launch.sh.")
        return 1
    print(("OK " if ok else "FAIL ") + result)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
