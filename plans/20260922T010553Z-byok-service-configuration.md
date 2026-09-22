# BYOK setup and server announcements

Approved implementation: preserve Go behind server-controlled membership availability. Share one anonymous GET /v1/desktop/config across launch, Welcome, Settings and Notices; fetch on launch and foreground after five minutes, coalesce concurrent requests and use a five-second timeout. Missing or unavailable configuration defaults to personal provider keys. No enabled feature state is persisted across launches.

When memberships are disabled, show expanded personal-key setup in Welcome and the API keys Settings tab, retain Advanced providers, hide purchasing/balance/refill/funding controls, and skip automatic account and StoreKit traffic. New actions use personal credentials; preserve stored preferences and captured billing snapshots, and never silently reroute pending managed work. Explicit server enable restores existing Go UI and purchase/quote approvals.

Read announcements from the same response as stable id, title, plain-text body and optional HTTPS url. Show them in server order in the existing Notices tray with a combined unread/storage dot. Opening the tray acknowledges displayed IDs in the existing notices document; read items remain visible while published. Add backward-compatible defaults and preserve disk usage state. No targeting, scheduling, blocking dialogs or admin editor.

Validate off/on/unknown configuration, duplicate fetches, stale billing preferences, pending actions, malformed announcements, acknowledgment persistence and legacy notice documents. Run existing Swift tests, build, source hygiene and REUSE validation when available. Do not add test files, make paid provider calls, publish source, create commits or advance consumer pins without authorization.
