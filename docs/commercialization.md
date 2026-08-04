# Commercialization plan

PiP Tidy will use a public-beta-to-private-commercial model.

## Public beta

- Beta builds are free and do not expire.
- Public beta source is released under the repository's MIT License.
- The beta exists to validate repeat use, placement quality, performance, onboarding, and browser/display compatibility—not to simulate a paid product prematurely.
- No trial countdown, payment prompt, license key, or activation network request belongs in the public beta.

Anything already distributed under MIT remains available under MIT. Making a repository private later cannot revoke existing copies, forks, or license grants.

## Transition to commercial development

When the beta has enough repeat users to justify a paid release:

1. Resolve all release-blocking security and privacy issues.
2. Publish a final public beta release and immutable version tag.
3. Clearly document that it is the last planned open-source application release.
4. Archive the public repository so existing issues, source, and license remain visible.
5. Create a separate private repository from the final beta snapshot for commercial 1.0 development.
6. Keep signing certificates, notarization credentials, payment credentials, license-signing private keys, and customer data out of both repositories.

The public repository should not be deleted merely to obscure its history; copies will already exist, and preserving the project is clearer for users and contributors.

## Planned 1.0 offer

- Fourteen-day unrestricted trial, starting on first successful use rather than installation.
- $15 USD one-time purchase.
- The purchased version continues working indefinitely.
- No subscription while the product has no recurring online service cost.
- Settings, license recovery, purchase access, and uninstall instructions remain available after trial expiration.
- Activation should tolerate temporary network outages and should never interrupt an active video session abruptly.

The payment and licensing provider remains a later implementation decision. Before choosing one, evaluate merchant-of-record tax handling, license APIs, refunds, fees on a $15 purchase, privacy terms, provider failure behavior, and exportability of customer/license records.

## Evidence needed before the transition

Do not close development merely because the app has downloads. Look for:

- At least 20–30 outside testers.
- Several testers using Live Placement repeatedly over multiple weeks.
- Placement and performance failures captured with reproducible diagnostics.
- A clear answer to “Would you pay $15 for this?” from actual repeat users.
- Stable onboarding, permissions, browser detection, multi-display behavior, signing, notarization, updates, and support contact paths.

The commercial transition should be a deliberate release decision, not an automatic date.
