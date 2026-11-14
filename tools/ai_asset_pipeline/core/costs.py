"""Cost estimates from config/provider_pricing.json. Never invent silent prices."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from core.settings import PIPELINE_ROOT


def load_pricing(path: Path | None = None) -> dict:
    target = path or (PIPELINE_ROOT / "config" / "provider_pricing.json")
    return json.loads(target.read_text(encoding="utf-8"))


def _usd(record: dict) -> float | None:
    for key in ("actual_usd", "estimated_usd"):
        value = record.get(key)
        if value is None:
            continue
        try:
            return float(value)
        except (TypeError, ValueError):
            continue
    return None


def summarize_costs(records: list[dict], budgets: dict | None = None) -> dict:
    by_provider: dict[str, float] = {}
    by_operation: dict[str, float] = {}
    by_category: dict[str, float] = {}
    known = 0
    unknown = 0
    total = 0.0
    month_key = datetime.now(timezone.utc).strftime("%Y-%m")
    month_total = 0.0
    for record in records:
        amount = _usd(record)
        if amount is None:
            unknown += 1
            continue
        known += 1
        total += amount
        provider = str(record.get("provider") or "unknown")
        operation = str(record.get("operation") or "unknown")
        category = str(record.get("category") or record.get("workshop_category") or "uncategorized")
        by_provider[provider] = by_provider.get(provider, 0.0) + amount
        by_operation[operation] = by_operation.get(operation, 0.0) + amount
        by_category[category] = by_category.get(category, 0.0) + amount
        created = str(record.get("created_at") or "")
        if created.startswith(month_key):
            month_total += amount
    budgets = budgets or {}
    return {
        "currency": budgets.get("currency") or "USD",
        "total_usd": round(total, 4),
        "month_usd": round(month_total, 4),
        "month": month_key,
        "known_records": known,
        "unknown_records": unknown,
        "by_provider": {key: round(value, 4) for key, value in sorted(by_provider.items())},
        "by_operation": {key: round(value, 4) for key, value in sorted(by_operation.items())},
        "by_category": {key: round(value, 4) for key, value in sorted(by_category.items())},
        "budgets": budgets,
        "within_monthly": (
            True
            if budgets.get("monthly_usd") is None
            else month_total <= float(budgets.get("monthly_usd") or 0)
        ),
    }


def check_budget(
    budgets: dict | None,
    *,
    records: list[dict] | None = None,
    estimated_usd: float | None = None,
    category: str = "",
    workshop_category: str = "",
) -> dict:
    """Soft/hard budget gate. hard_limit false → warn only."""
    budgets = budgets or {}
    summary = summarize_costs(records or [], budgets)
    warnings = []
    blocked = False
    hard = bool(budgets.get("hard_limit"))
    estimate = float(estimated_usd or 0.0)
    monthly = budgets.get("monthly_usd")
    if monthly is not None and (summary["month_usd"] + estimate) > float(monthly):
        message = f"Monthly budget ${float(monthly):.2f} would be exceeded (month ${summary['month_usd']:.2f} + ${estimate:.2f})."
        warnings.append(message)
        if hard:
            blocked = True
    per_job = budgets.get("per_job_usd")
    if per_job is not None and estimate > float(per_job):
        message = f"Job estimate ${estimate:.2f} exceeds per-job budget ${float(per_job):.2f}."
        warnings.append(message)
        if hard:
            blocked = True
    per_category = budgets.get("per_category") or {}
    key = workshop_category or category
    if key and key in per_category:
        spent = float((summary.get("by_category") or {}).get(key) or 0.0)
        limit = float(per_category[key])
        if spent + estimate > limit:
            message = f"Category '{key}' budget ${limit:.2f} would be exceeded (spent ${spent:.2f} + ${estimate:.2f})."
            warnings.append(message)
            if hard:
                blocked = True
    return {
        "ok": not blocked,
        "blocked": blocked,
        "hard_limit": hard,
        "warnings": warnings,
        "summary": summary,
        "estimated_usd": estimate,
    }


def estimate_operation(pricing: dict, provider: str, operation: str, units: int = 1) -> dict:
    """Return an estimate record. Missing prices are marked unknown, not invented."""
    block = (pricing or {}).get(provider) or {}
    ops = block.get("operations") or {}
    entry = ops.get(operation) or {}
    credits = entry.get("credits")
    credit_usd = block.get("credit_usd")
    estimated_usd = None
    known = True
    if credits is None and entry.get("usd_estimate") is None:
        known = False
    else:
        try:
            if credits is not None:
                credits = float(credits) * max(1, int(units))
            if credit_usd is not None and credits is not None:
                estimated_usd = float(credit_usd) * float(credits)
            elif entry.get("usd_estimate") is not None:
                estimated_usd = float(entry["usd_estimate"]) * max(1, int(units))
            else:
                known = credits is not None
        except (TypeError, ValueError):
            known = False
            credits = None
            estimated_usd = None
    return {
        "provider": provider,
        "operation": operation,
        "units": max(1, int(units)),
        "credits": credits,
        "estimated_usd": estimated_usd,
        "currency": pricing.get("currency", "USD"),
        "known": known,
        "notes": entry.get("notes", ""),
    }


def cost_record_from_task(
    *,
    provider: str,
    operation: str,
    asset_id: str = "",
    job_id: str = "",
    generation_task_id: str = "",
    provider_task_id: str = "",
    consumed_credits=None,
    pricing: dict | None = None,
    category: str = "",
) -> dict:
    table = pricing if pricing is not None else load_pricing()
    estimate = estimate_operation(table, provider, operation)
    credits = consumed_credits if consumed_credits is not None else estimate.get("credits")
    actual_usd = None
    credit_usd = ((table.get(provider) or {}).get("credit_usd"))
    if credits is not None and credit_usd is not None:
        try:
            actual_usd = float(credit_usd) * float(credits)
        except (TypeError, ValueError):
            actual_usd = None
    return {
        "provider": provider,
        "operation": operation,
        "asset_id": asset_id,
        "job_id": job_id,
        "generation_task_id": generation_task_id,
        "provider_task_id": provider_task_id,
        "category": category,
        "credits": credits,
        "estimated_usd": estimate.get("estimated_usd"),
        "actual_usd": actual_usd,
        "currency": table.get("currency", "USD"),
        "known": estimate.get("known", False) or consumed_credits is not None,
        "approved": False,
        "notes": estimate.get("notes", ""),
    }
