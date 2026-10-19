# Stochastic Range Regime MT5 Port

MetaTrader 5 adaptation of **Stochastic Range Regime [MarkitTick]**: stochastic range conditions plus a trend SMA, optional HTF/ADX confirmation, regime-colored candles, and virtual ATR entry/stop/target levels.

## Primary project page

**Detailed MT5 documentation and chart examples:**

### [Stochastic Range Regime MT5 on AlgoToolbox](https://algotoolbox.com/products/stochastic-range-regime-mt5/)

AlgoToolbox is the primary documentation home; this repository is the secondary code repository. **The article is being prepared**, so the approved page address may currently return a not-found page.

## Version and installation

- **Source version:** `1.00`.
- **MT5 adaptation:** AlgoToolbox (atoskueko).
- **License:** **CC BY-NC-SA 4.0** — attribution, noncommercial use, ShareAlike.

1. Put `Stochastic Range Regime.mq5` in `MQL5/Indicators/`.
2. Open it in MetaEditor, press **F7**, and review compiler messages.
3. After successful compilation, refresh Navigator and attach to a standard OHLC chart with sufficient history.
4. Begin with defaults and use one copy per chart. Pop-up alerts are on by default; optional push notifications are off and require terminal notification setup.

No compiled EX5 is included in this source package. The provided screenshots show example MT5 output and a 1.00 Inputs window; this package does not claim an independently repeated native build, runtime test, or matched-data Pine comparison.

## Important behavior

The indicator does not send broker orders or size positions. Targets are **ATR multiples, not R multiples**. Target touches use highs/lows; the virtual stop requires a completed-bar close beyond its level. Hit labels and percentage moves are not account P/L. Read [COMPATIBILITY.md](COMPATIBILITY.md) for implementation limits before relying on the output.

## Origin and terms

Original: [Stochastic Range Regime [MarkitTick]](https://www.tradingview.com/script/hSH66dWe-Stochastic-Range-Regime-MarkitTick/), **© MarkitTick**. The AlgoToolbox guide does not replace that original publication or authorship.

This adaptation retains **[CC BY-NC-SA 4.0](LICENSE)**. See [NOTICE.md](NOTICE.md). No separate commercial-use permission is supplied; do not treat this as cleared for sale or monetized distribution. Detailed settings, calculations, screenshots, and evaluation belong on the primary site page rather than being duplicated here.
