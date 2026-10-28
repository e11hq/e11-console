# App Store screenshots (6.9", 1320×2868)

Made from the App Review demo (made-up clients, people and pictures — never real data):

1. Load the demo into a scratch folder and serve it with the developer sign-in:
   `REVIEW_PASSWORD=anything-long DATA_DIR=/tmp/demo PORT=8771 timeout 8 node server/src/index.js`
   then `AUTH_DEV=1 DATA_DIR=/tmp/demo PORT=8772 node server/src/index.js`
2. `mkdir -p appstore-out/shots appstore-out/appstore && OUT=appstore-out python3 scripts/appstore/shots.py` — phone screens (Playwright, 440×956 @3x)
3. `OUT=appstore-out python3 scripts/appstore/compose.py` — headline + screen → `appstore-out/appstore/*.png`
