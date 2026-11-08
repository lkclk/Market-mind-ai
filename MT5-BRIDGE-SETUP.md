# MarketMind ↔ HFM MT5 bridge

## Components
- `worker.js`: Cloudflare Worker relay; accepts signed MarketMind signals, queues one short-lived signal, and returns EA execution status.
- `mt5/MarketMindBridgeEA.mq5`: MT5 Expert Advisor that polls the relay, checks account mode, validates stops, calculates volume from broker tick-value data, and submits orders using the logged-in terminal.

## Not connected until deployed and configured
This source code does not itself create an HFM login or host MT5. Deploy the Worker, create a KV namespace, configure secrets, compile/install the EA in desktop MT5, and attach it to a chart. A Windows VPS or Windows computer must remain running. Android MT5 cannot run this EA.

## Cloudflare setup
1. Create a Cloudflare Worker and KV namespace named for this project.
2. Set the KV binding name to `SIGNALS`.
3. Set Worker secrets `MM_TOKEN` and `EA_TOKEN` to two different long random values. Never commit them to GitHub.
4. Set the KV namespace ID in `wrangler.toml`, then deploy with Wrangler.
5. Use the Worker HTTPS URL as `RelayBaseUrl` in the EA.
6. Configure the same `EA_TOKEN` in EA inputs and add the Worker host to MT5 WebRequest allowed URLs.
7. Configure MarketMind with the Worker URL and `MM_TOKEN` in its private settings before signals can be relayed.

## Trading safety
- Demo is enabled by default. Live trading is disabled by default.
- Hard maximum risk is 1% of equity per order; the signal cannot request more.
- One open position per symbol; signals expire after 60 seconds.
- Confirm broker symbol suffixes, tick values, trading hours, stop-level rules, volume step, spreads, and execution settings.
- This is software infrastructure, not a profitable strategy or guaranteed loss cap. Gaps, slippage, commissions and execution failures can increase losses.
