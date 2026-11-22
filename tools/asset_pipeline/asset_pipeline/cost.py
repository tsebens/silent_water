"""The cost ledger: what each paid backend call cost, appended to the asset manifest's `costs` list.

Prices come from prices.yaml (config, not code). An entry stores the unit price it used, so a later price
change never rewrites history. Unknown is never silently zero: a call that cannot be priced records `usd: null`.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any, Callable

import yaml

from .manifest import CostRecord as CostEntry
from .manifest import Manifest

PRICES_PATH = Path(__file__).resolve().parent.parent / "prices.yaml"
BASES = ("reported", "estimated", "mock", "unknown", "subscription")
# Keys in a provider's `last_usage` that are not units.
REPORTED_USD = "reported_usd"
API_EQUIVALENT_USD = "api_equivalent_usd"


def load_prices(path: Path | None = None) -> dict[str, Any]:
    return yaml.safe_load((path or PRICES_PATH).read_text()) or {}


def price_for(prices: dict[str, Any], kind: str, provider: str, model: str) -> dict[str, Any] | None:
    """The entry for `model`: under the named provider first, else under any provider of that kind
    (a provider alias such as google-pro shares its adapter's prices)."""
    by_provider = prices.get(kind) or {}
    hit = (by_provider.get(provider) or {}).get(model)
    if hit is None:
        for models in by_provider.values():
            if isinstance(models, dict) and model in models:
                hit = models[model]
                break
    return hit if isinstance(hit, dict) else None


def _rates(price: dict[str, Any], *keys: str) -> dict[str, float]:
    return {k: price[k] for k in keys if isinstance(price.get(k), (int, float))}


def _num(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def compute(price: dict[str, Any] | None, units: dict[str, Any], reported_usd: float | None = None
            ) -> tuple[float | None, str, dict[str, Any]]:
    """(usd, basis, unit_price used). `reported` when the provider gave a cost or credit charge,
    `estimated` when usage or the request is multiplied by a table price, `unknown` when neither works."""
    if reported_usd is not None:
        return round(float(reported_usd), 6), "reported", {}
    if price is None:
        return None, "unknown", {}
    if _num(units.get("credits")) and "usd_per_credit" in price:
        return round(units["credits"] * price["usd_per_credit"], 6), "reported", _rates(price, "usd_per_credit")
    parts: list[float] = []
    used: dict[str, float] = {}
    for unit, key in (("input_tokens", "usd_per_mtok_input"), ("output_tokens", "usd_per_mtok_output")):
        if _num(units.get(unit)) and key in price:
            parts.append(units[unit] * price[key] / 1e6)
            used |= _rates(price, key)
    if not parts and _num(units.get("total_tokens")) and "usd_per_mtok_total" in price:
        parts.append(units["total_tokens"] * price["usd_per_mtok_total"] / 1e6)
        used |= _rates(price, "usd_per_mtok_total")
    if parts:  # token usage the provider reported wins over the flat per-image price
        return round(sum(parts), 6), "estimated", used
    for count_key, rate_key in (("images", "usd_per_image"), ("generations", "usd_per_generation")):
        if _num(units.get(count_key)) and rate_key in price:
            return round(units[count_key] * price[rate_key], 6), "estimated", _rates(price, rate_key)
    return None, "unknown", {}


def entry_for(prov: Any, kind: str, prices: dict[str, Any], *, command: str, stage: str,
              lineage: str | None = None, error: str = "") -> CostEntry:
    """Build the ledger entry for one finished call from what `prov` recorded in `last_usage`."""
    usage = dict(getattr(prov, "last_usage", None) or {})
    reported = usage.pop(REPORTED_USD, None)
    api_eq = usage.pop(API_EQUIVALENT_USD, None)
    base = dict(command=command, stage=stage, provider=prov.name, model=prov.model, lineage=lineage, error=error)
    billing = getattr(prov, "billing", "paid")
    if billing == "mock":
        return CostEntry(**base, usd=0.0, basis="mock", units=usage)
    if billing == "subscription":
        return CostEntry(**base, usd=0.0, basis="subscription", units=usage,
                         api_equivalent_usd=round(float(api_eq), 6) if _num(api_eq) else None)
    usd, basis, unit_price = compute(price_for(prices, kind, prov.name, prov.model), usage, reported)
    return CostEntry(**base, usd=usd, basis=basis, units=usage, unit_price=unit_price)


def paid_call(m: Manifest, prov: Any, kind: str, prices: dict[str, Any], fn: Callable[[], Any], *,
              command: str, stage: str, lineage: str | None = None) -> Any:
    """Run one backend call and append its ledger entry. A call that raises after the provider reported
    usage (billed but unusable, e.g. a reply with no image) is recorded too, then the error propagates.
    A call that fails before any usage was reported (auth, HTTP, network) was not billed and records nothing."""
    prov.last_usage = None
    try:
        result = fn()
    except Exception as e:
        if prov.last_usage is not None:
            m.costs.append(entry_for(prov, kind, prices, command=command, stage=stage, error=str(e)[:300]))
        raise
    m.costs.append(entry_for(prov, kind, prices, command=command, stage=stage, lineage=lineage))
    return result


def total_usd(m: Manifest) -> float:
    """Spend so far: every entry with a USD figure except `subscription` ones (which are always 0)."""
    return round(sum(c.usd for c in m.costs if c.usd is not None and c.basis != "subscription"), 6)
