#!/usr/bin/env python3
"""WebSocket front-end for the TetraMaster TCP relay (newline-delimited JSON)."""

from __future__ import annotations

import asyncio
import logging
import os
import signal

import websockets
from websockets.server import WebSocketServerProtocol, serve

RELAY_HOST = os.getenv("TM_WS_RELAY_HOST", "127.0.0.1")
RELAY_PORT = int(os.getenv("TM_WS_RELAY_PORT", "19876"))
BIND_HOST = os.getenv("TM_WS_BIND", "127.0.0.1")
BIND_PORT = int(os.getenv("TM_WS_PORT", "8080"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s ws_bridge: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("ws_bridge")


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


async def handler(ws: WebSocketServerProtocol) -> None:
    peer = ws.remote_address
    log.info("client connected %s", peer)
    reader, writer = await asyncio.open_connection(RELAY_HOST, RELAY_PORT)
    tasks = [
        asyncio.create_task(relay_tcp_to_ws(ws, reader)),
        asyncio.create_task(relay_ws_to_tcp(ws, writer)),
    ]
    done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    for task in pending:
        task.cancel()
    await asyncio.gather(*pending, return_exceptions=True)
    writer.close()
    try:
        await writer.wait_closed()
    except Exception:
        pass
    log.info("client disconnected %s", peer)


async def main() -> None:
    log.info("listening on %s:%s -> tcp %s:%s", BIND_HOST, BIND_PORT, RELAY_HOST, RELAY_PORT)
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
