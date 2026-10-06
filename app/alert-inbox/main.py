"""alert-inbox — capture Alertmanager webhooks for Reliable App demos.

P1 (page)  → POST /pager
P2 (ticket) → POST /ticket
Inspect     → GET  /inbox
"""

from collections import defaultdict
from datetime import datetime, timezone

from fastapi import FastAPI, Request

app = FastAPI(
    title="alert-inbox",
    description="Demo sink for Alertmanager P1/P2 webhooks (not a real pager).",
    version="0.1.0",
)

_inbox: dict[str, list] = defaultdict(list)
_MAX = 50


def _stamp(payload: dict) -> dict:
    return {
        "received_at": datetime.now(timezone.utc).isoformat(),
        "payload": payload,
    }


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/pager")
async def pager(request: Request) -> dict:
    body = await request.json()
    _inbox["pager"].insert(0, _stamp(body))
    _inbox["pager"] = _inbox["pager"][:_MAX]
    return {"ok": True, "queue": "pager", "size": len(_inbox["pager"])}


@app.post("/ticket")
async def ticket(request: Request) -> dict:
    body = await request.json()
    _inbox["ticket"].insert(0, _stamp(body))
    _inbox["ticket"] = _inbox["ticket"][:_MAX]
    return {"ok": True, "queue": "ticket", "size": len(_inbox["ticket"])}


@app.get("/inbox")
def inbox() -> dict:
    return {
        "pager": _inbox["pager"],
        "ticket": _inbox["ticket"],
        "pager_count": len(_inbox["pager"]),
        "ticket_count": len(_inbox["ticket"]),
    }


@app.delete("/inbox")
def clear_inbox() -> dict:
    _inbox.clear()
    return {"ok": True}
