# Desktop Go integration

Self-serve setup is available with your own provider accounts. **Direct-download Go checkout is available; App Store purchases remain unavailable.** The client integration described below is implemented; payment controls must follow the gateway’s availability response.

## Setup and configuration

Account & usage opens once per app launch until a personal OpenAI key or a server-confirmed subscription is configured. Users can dismiss it to explore for that launch. Existing projects, unrelated vendor keys, and dismissing the optional Welcome Journey do not finish setup. A cached subscription confirmation prevents an outage from restarting onboarding; it never authorizes spending. Sign-out or a successful refresh reporting no current plan clears that confirmation.

Self serve starts with OpenAI Save & Test and explains separate API billing. Additional credentials and compatible endpoint/model overrides live in Advanced providers. Users do not configure hosted graph endpoints or tokens.

The gateway comes from the `LitScenesGoServiceURL` bundle value, defaulting to `https://api.litscenes.ai/v1/desktop`. Development builds can override it with `LITSCENES_GO_SERVICE_URL`; HTTPS is required except for development loopback addresses. Provider secrets and the hosted service implementation are not bundled in the app.

An unconfigured launch, including its automatically opened settings modal, does not contact Go. Choosing a Go option checks availability. Existing accounts reconnect to refresh purchases and jobs. Connection failures offer retry and leave self-serve setup accessible; unknown balances must not appear as zero.

`LitScenesDistribution` selects direct Stripe checkout or native StoreKit. The [packaging script](../scripts/build_litscenes_app.sh) accepts `--distribution direct|app-store`; App Store packaging adds sandbox entitlements, uses the required signing/provisioning inputs, and omits the direct updater feed. StoreKit support in source does not mean App Store subscriptions are available.

## Subscriptions

| Plan | Monthly price | Monthly credits |
| --- | --- | --- |
| Go | $16.80 | 750 |
| Go Plus | $68 | 3,500 |

Both tiers provide the same managed capabilities, including hosted story context. Monthly credits expire at renewal, with no rollover or automatic overages. Existing prepaid balances remain recoverable; monthly credits are spent first. Desktop balances are separate from SMS and mobile balances. Applicable taxes are added at direct checkout; localized App Store prices are authoritative for native purchases.

Active paid subscribers can buy a one-time refill in Account & usage: 1,000 credits for $25 or 10,000 credits for $238, plus applicable tax. Refill credits never expire and are used after monthly credits. Buying a refill preserves the subscription, renewal date, and selected billing source. Refills are absent from initial onboarding and are unavailable in App Store builds.

The gateway advertises `refill_version`, `refills_available`, and `packs`; the account response supplies `refill_eligible`. Monthly offers keep their own version so older clients can continue subscribing. Refill checkout uses the existing authenticated purchase and Keychain recovery flow with its refill offer version. A successful checkout refreshes the account and resumes only previously approved work waiting for credits.

Direct checkout is integrated with Stripe Managed Payments. The client checks the versioned offer before purchase and presents the server’s immediate charge, additional credits, and recurring terms before an upgrade. Paid upgrades retain the renewal date and prorate additional credits; failed payment leaves the current plan intact. Downgrades and cancellation take effect at renewal. Billing remains accessible during generation suspension, including cancellation when a downgrade is scheduled. Each billing provider remains independently manageable.

Native products use configured standard/plus monthly identifiers in one subscription group, with Plus ranked higher. Apple controls native timing and localized prices. New receipts bind to a server-issued opaque purchase token and the expected product; historical receipts must not replace another provider’s active subscription or complete an unrelated checkout. Restore includes historical subscription and consumable purchases. Native transactions finish only after server acknowledgment.

## Provider selection and billing

Go and personal credentials coexist. Saving or testing a vendor key does not select that vendor as payer. Covered models and workflows expose saved Go-credits/My-API-key choices in the existing controls; unsupported managed operations require a supporting personal provider. CivitAI and the explicit OpenAI image stack use personal credentials. There is no automatic fallback between payers.

Choices affect future submissions across projects. Queued and running work retains its captured billing source, prompt, settings, and account identity. Go credit rates and direct provider dollar rates remain separate, including mixed plans. Switching to self serve preserves media and credentials and does not cancel subscription renewal.

Managed image generation and reference edits use the Nano Banana adapter. Masked edits and transparent output require a supporting personal provider. Capabilities in model controls must reflect executable routes and service availability.

## Account security and recovery

Opaque sessions and checkout verifiers use a bundle/service-specific Keychain namespace. Email recovery uses a single-use verified code. Account-bound quote intents use local files with restrictive permissions. The internal routing marker is not a credential and must never reach a provider or arbitrary custom endpoint.

Managed generation requires a server quote and approval of the maximum credit cost. Payment confirmation alone does not initiate new creative work; previously approved work waiting for funds resumes with its existing identity. Retry reuses the original job and result, including after an interrupted project save. Deliberate regeneration creates a new identity. Unknown provider acceptance must not trigger automatic resubmission.

Downloads validate HTTP status, size, and SHA-256 before durable local storage and acknowledgment. Media uploads use the signed PUT/completion contract; account authorization goes only to the gateway. Transfers refuse redirects, and recovery manifests retain local references and hashes rather than signed URLs. Server recovery expires after seven days; local cache and project files survive that window. Reference images fit and pad without cropping, and returned pixels fit the requested canvas.

See [product requirements](REQUIREMENTS.md) for the broader provider and creative-workflow contract.
