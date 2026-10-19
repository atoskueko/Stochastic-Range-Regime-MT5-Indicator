# Compatibility and validation scope — 1.00

This file records source-review observations for the current uploaded build. The screenshots show example MT5 states and a 1.00 settings window. No native compiler log, exact source/binary correspondence, alert-delivery trace, or matched-data Pine replay was supplied or independently repeated for this package.

## Current implementation

- 49 inputs, 17 buffers, one color-candle plot. Most additional buffers are marked as internal calculations; there is no dedicated BUY/SELL/exit event-buffer interface documented by this build.
- Dashboard is top-left; the original selectable dashboard corners are not implemented here.
- Standard ENUM_APPLIED_PRICE choices are supported. Arbitrary external Pine plots and an OHLC4 choice are not offered by those enums.
- `InpMaxBars=5000` limits the historical virtual-plan replay, not every stochastic/strength calculation.
- Popup is true and push false by default. Live events also print payload text to the Experts journal. Push uses SendNotification and requires the terminal's notification setup. The supplied popup image is not evidence of push delivery.
- Action-word payloads are text; no HTTP webhook transport or broker-order API is implemented. Custom payload strings are not escaped, so quotes/control characters can make custom JSON text invalid.

## Interpretation limits

- Targets are ATR distances, not multiples of the stop's risk distance. TP1/TP2 action messages do not execute partial closes.
- The stop uses a completed close beyond its level, not a wick or broker stop fill. TP3 is handled before a same-bar stop condition.
- Current dashboard ATR can differ from the ATR frozen into an earlier plan's levels.
- Native history, feed data, timestamps, smoothing startup, and settings can change reconstructed output. No exact cross-platform parity claim is made.

## Review before relying on the output

- Parameter ranges are not comprehensively validated. Keep documented positive periods and valid settings; zero/negative periods can break loops or divisions.
- Chronological-order assumptions and capped/shifted chart history need native checks; price/time arrays are not explicitly normalized with ArraySetAsSeries in OnCalculate.
- Stochastic SMA uses strict missing-sample handling; adaptive RMA and ADX have implementation-specific seeding. These require direct comparison before first-bar/whole-history parity statements.
- HTF cache uses up to 3000 bars. Missing and neutral states both return zero, blocking agreement. Loading data later does not explicitly trigger a full local virtual-history reconstruction.
- `_Point` is used for minimum distance and level equality; it can differ from a symbol's contract trade-tick size.
- All chart objects use a shared SRR_ naming prefix. Use one copy per chart to avoid overlap/deletion between copies.

These are maintenance and interpretation notes, not reported failed native tests. Detailed demonstrations belong on the primary AlgoToolbox guide. The earlier port's 26 portable kernel checks do not validate this different implementation.
