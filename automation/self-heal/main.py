"""self-heal — Alertmanager webhook that mitigates fast error-budget burns.

Flow: alert → webhook → evidence stub → reset payment faults → rollout restart.
"""

from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from kubernetes import client, config
from kubernetes.client.rest import ApiException

NAMESPACE = os.getenv("NAMESPACE", "reliable-app")
TARGET_DEPLOYMENT = os.getenv("TARGET_DEPLOYMENT", "payments-mock")
PAYMENTS_URL = os.getenv("PAYMENTS_URL", "http://payments-mock:8000")
EVIDENCE_DIR = Path(os.getenv("EVIDENCE_DIR", "/evidence"))
COOLDOWN_S = float(os.getenv("SELF_HEAL_COOLDOWN_S", "60"))

app = FastAPI(
    title="self-heal",
    description="Demo self-healing webhook for Reliable App (Kind).",
    version="0.1.0",
)

_last_action_at = 0.0
_actions: list[dict] = []


def _k8s():
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()
    return client.AppsV1Api(), client.CoreV1Api()


def _write_evidence(alert_name: str, payload: dict) -> str:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = EVIDENCE_DIR / f"heal_{stamp}_{alert_name}.json"
    record = {
        "collected_at": datetime.now(timezone.utc).isoformat(),
        "alert_name": alert_name,
        "note": "Stub evidence for portfolio demos (heap dump placeholder).",
        "heap_dump_stub": f"/evidence/heap_{stamp}.stub",
        "alertmanager_payload": payload,
    }
    # Tiny stub file representing a heap dump artifact
    (EVIDENCE_DIR / f"heap_{stamp}.stub").write_text(
        f"heap-dump-stub for {alert_name} at {stamp}\n",
        encoding="utf-8",
    )
    path.write_text(json.dumps(record, indent=2), encoding="utf-8")
    return str(path)


def _reset_payment_faults() -> dict:
    try:
        with httpx.Client(timeout=5.0) as client_http:
            r = client_http.post(
                f"{PAYMENTS_URL.rstrip('/')}/admin/faults",
                json={"latency_ms": 0, "error_rate": 0.0, "timeout": False},
            )
            return {"status_code": r.status_code, "body": r.json() if r.content else {}}
    except Exception as exc:  # noqa: BLE001 — demo resilience
        return {"error": str(exc)}


def _rollout_restart(apps: client.AppsV1Api) -> dict:
    patch = {
        "spec": {
            "template": {
                "metadata": {
                    "annotations": {
                        "reliable-app.io/restartedAt": datetime.now(timezone.utc).isoformat()
                    }
                }
            }
        }
    }
    apps.patch_namespaced_deployment(
        name=TARGET_DEPLOYMENT,
        namespace=NAMESPACE,
        body=patch,
    )
    return {"deployment": TARGET_DEPLOYMENT, "namespace": NAMESPACE, "action": "rollout-restart"}


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/actions")
def list_actions() -> dict:
    return {"count": len(_actions), "actions": _actions[:20]}


@app.get("/evidence")
def list_evidence() -> dict:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(p.name for p in EVIDENCE_DIR.iterdir() if p.is_file())
    return {"dir": str(EVIDENCE_DIR), "files": files}


@app.post("/webhook")
async def webhook(request: Request) -> dict:
    global _last_action_at
    payload = await request.json()
    alerts = payload.get("alerts") or []
    # Alertmanager sends status=firing|resolved
    firing = [
        a
        for a in alerts
        if a.get("status") == "firing"
        and a.get("labels", {}).get("severity") == "page"
    ]
    if not firing:
        return {"ok": True, "action": "ignored", "reason": "no firing page alerts"}

    now = time.monotonic()
    if now - _last_action_at < COOLDOWN_S:
        return {
            "ok": True,
            "action": "skipped",
            "reason": f"cooldown {COOLDOWN_S}s",
            "alerts": [a.get("labels", {}).get("alertname") for a in firing],
        }

    alert_name = firing[0].get("labels", {}).get("alertname", "unknown")
    evidence_path = _write_evidence(alert_name, payload)
    faults = _reset_payment_faults()

    restart: dict
    try:
        apps, _core = _k8s()
        restart = _rollout_restart(apps)
    except ApiException as exc:
        restart = {"error": f"k8s ApiException: {exc.status} {exc.reason}"}
    except Exception as exc:  # noqa: BLE001
        restart = {"error": str(exc)}

    _last_action_at = now
    action = {
        "at": datetime.now(timezone.utc).isoformat(),
        "alert_name": alert_name,
        "evidence": evidence_path,
        "fault_reset": faults,
        "restart": restart,
    }
    _actions.insert(0, action)
    _actions[:] = _actions[:50]
    return {"ok": True, "action": "healed", **action}
