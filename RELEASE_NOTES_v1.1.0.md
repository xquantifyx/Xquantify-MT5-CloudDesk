## Xquantify-MT5-CloudDesk v1.1.0 — Broker cache + Bybit

**New**
- Added **downloads cache** on host (default `~/mt5downloads`) to store multiple MT5 installers.
- Introduced **broker presets**: `metaquotes, exness, icmarkets, pepperstone, xm, bybit`.
- NEW: **Bybit** support — `--broker bybit` installs from Bybit's official MT5 URL.
- New flags:
  - `--download-dir <path>` — cache location
  - `--broker <key>` — choose preset
  - `--list-brokers` — show all presets
  - `--mt5-url <url>` — override with custom installer URL

**Examples**
```bash
sudo ./install_mt5_headless.sh --broker bybit --name mt5_bybit   --data-dir ~/mt5data_bybit --http-port 6082 --vnc-port 5903 --vnc-pass BybitPass
```

**Notes**
- Reuses cached installers across servers, speeding up provisioning.
