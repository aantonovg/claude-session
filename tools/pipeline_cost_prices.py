"""Price table and price_for() shared by pipeline-cost.py and tests/demo-game/session-cost.py (extracted verbatim)."""
import os
PRICES = {
    "claude-fable-5-1": (10e-6, 50e-6, 2.5e-7, 12.5e-6, 20e-6),
    "claude-fable-5": (10e-6, 50e-6, 1e-6, 12.5e-6, 20e-6),
    "claude-opus-5-5": (4e-6, 20e-6, 2e-7, 5e-6, 8e-6),
    "claude-opus-5": (5e-6, 25e-6, 5e-7, 6.25e-6, 10e-6),
    "claude-opus-4-8": (5e-6, 25e-6, 5e-7, 6.25e-6, 10e-6),
    "claude-opus-4-7": (5e-6, 25e-6, 5e-7, 6.25e-6, 10e-6),
    "claude-sonnet-5-5": (2e-6, 10e-6, 1e-7, 2.5e-6, 4e-6),
    "claude-sonnet-5": (2e-6, 10e-6, 2e-7, 2.5e-6, 4e-6),
    "claude-sonnet-4-5": (3e-6, 15e-6, 3e-7, 3.75e-6, 6e-6),
    "claude-haiku-5-5": (1e-7, 5e-7, 1e-8, 1.25e-7, 2e-7),
    "claude-haiku-4-5": (1e-6, 5e-6, 1e-7, 1.25e-6, 2e-6),
}
DEFAULT_PRICE_KEY = "claude-opus-4-8"
# Haiku 5.5 is priced by prompt length: a request whose prompt (input + cache read + cache
# write) is over the threshold pays the long row for every field, output included.
LONG_PROMPT = {"claude-haiku-5-5": (100_000, (5e-7, 2.5e-6, 5e-8, 6.25e-7, 1e-6))}
# Copied from claude-cost codexPricingTable, USD per token: input, cached input, output.
CODEX_PRICES = {
    "gpt-5.6-sol": (4e-6, 4e-7, 20e-6),
    "gpt-5.6-terra": (2e-6, 2e-7, 12e-6),
    "gpt-5.6-luna": (2e-7, 2e-8, 1.2e-6),
    "gpt-reserve": (2e-7, 2e-8, 1.2e-6),  # luna billed against the reserve quota
    # developers.openai.com/api/docs/pricing (2026-10-22), standard rows up to 272K input tokens;
    # a ledger record sums a whole run, so the long-context rows are not applied.
    "gpt-6.1-sol": (2e-6, 1e-7, 10e-6),
    "gpt-6-luna": (1e-7, 1e-8, 5e-7),
    "gpt-6-astra": (10e-6, 1e-6, 50e-6),
}
# Tier to ledger model ids: the first id is the current one, later ids match older ledger rows.
CODEX_TIERS = {"astra": ("gpt-6-astra",), "sol": ("gpt-6.1-sol", "gpt-5.6-sol"),
               "luna": ("gpt-6-luna", "gpt-5.6-luna"), "luna-reserve": ("gpt-reserve",),
               "terra": ("gpt-5.6-terra",)}
CODEX_USAGE = os.path.expanduser("~/.codex/proxy-usage.jsonl")
CODEX_WINDOW_S = 4 * 3600
MISS_DROP = 20_000
MISS_WRITE = 20_000
FIELDS = ("input", "output", "read", "w5", "w1")


def price_for(model, prompt=0):
    best = ""
    for k in PRICES:
        if model and model.startswith(k) and len(k) > len(best):
            best = k
    key = best or DEFAULT_PRICE_KEY
    tier = LONG_PROMPT.get(key)
    if tier and prompt > tier[0]:
        return tier[1], best or None
    return PRICES[key], best or None


