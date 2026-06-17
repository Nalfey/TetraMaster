#!/usr/bin/env python3
"""WebSocket front-end for the TetraMaster TCP relay (newline-delimited JSON)."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
from collections import defaultdict

import websockets
from websockets.server import WebSocketServerProtocol, serve

RELAY_HOST = os.getenv("TM_WS_RELAY_HOST", "127.0.0.1")
RELAY_PORT = int(os.getenv("TM_WS_RELAY_PORT", "19876"))
BIND_HOST = os.getenv("TM_WS_BIND", "127.0.0.1")
BIND_PORT = int(os.getenv("TM_WS_PORT", "8080"))
MAX_PER_IP = int(os.getenv("TM_WS_MAX_PER_IP", "2"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s ws_bridge: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("ws_bridge")

ip_connections: dict[str, int] = defaultdict(int)
ip_lock = asyncio.Lock()


def get_client_ip(ws: WebSocketServerProtocol) -> str:
    headers = {}
    request = getattr(ws, "request", None)
    if request is not None:
        headers = getattr(request, "headers", None) or {}

    for key in ("cf-connecting-ip", "x-forwarded-for", "x-real-ip"):
        value = headers.get(key)
        if value:
            return value.split(",")[0].strip()

    if ws.remote_address:
        return ws.remote_address[0]
    return "unknown"


async def relay_tcp_to_ws(ws: WebSocketServerProtocol, reader: asyncio.StreamReader) -> None:
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            text = line.decode("utf-8").rstrip("\r\n")
            if text:
                await ws.send(text)
    except asyncio.CancelledError:
        raise
    except Exception as exc:
        log.debug("tcp->ws stopped: %s", exc)


async def relay_ws_to_tcp(ws: WebSocketServerProtocol, writer: asyncio.StreamWriter) -> None:
    try:
        async for message in ws:
            if isinstance(message, bytes):
                message = message.decode("utf-8")
            writer.write((message.rstrip("\r\n") + "\n").encode("utf-8"))
            await writer.drain()
    except asyncio.CancelledError:
        raise
    except Exception as exc:
        log.debug("ws->tcp stopped: %s", exc)


async def send_relay_meta(writer: asyncio.StreamWriter, client_ip: str) -> None:
    meta = json.dumps({"type": "_relay_meta", "client_ip": client_ip}) + "\n"
    writer.write(meta.encode("utf-8"))
    await writer.drain()


async def handler(ws: WebSocketServerProtocol) -> None:
    client_ip = get_client_ip(ws)

    async with ip_lock:
        if ip_connections[client_ip] >= MAX_PER_IP:
            log.warning(
                "reject %s: already %s connections (max %s per IP)",
                client_ip,
                ip_connections[client_ip],
                MAX_PER_IP,
            )
            await ws.close(1008, "too_many_connections_per_ip")
            return
        ip_connections[client_ip] += 1

    log.info("client connected %s (ip=%s)", ws.remote_address, client_ip)
    reader, writer = await asyncio.open_connection(RELAY_HOST, RELAY_PORT)
    await send_relay_meta(writer, client_ip)

    try:
        tasks = [
            asyncio.create_task(relay_tcp_to_ws(ws, reader)),
            asyncio.create_task(relay_ws_to_tcp(ws, writer)),
        ]
        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        async with ip_lock:
            ip_connections[client_ip] = max(0, ip_connections[client_ip] - 1)
            if ip_connections[client_ip] == 0:
                del ip_connections[client_ip]
        log.info("client disconnected %s (ip=%s)", ws.remote_address, client_ip)


async def main() -> None:
    log.info(
        "listening on %s:%s -> tcp %s:%s (max %s connections per IP)",
        BIND_HOST,
        BIND_PORT,
        RELAY_HOST,
        RELAY_PORT,
        MAX_PER_IP,
    )
    async with serve(handler, BIND_HOST, BIND_PORT, ping_interval=20, ping_timeout=20):
        stop = asyncio.Event()

        def _stop(*_: object) -> None:
            stop.set()

        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, _stop)

        await stop.wait()


if __name__ == "__main__":
    asyncio.run(main())
