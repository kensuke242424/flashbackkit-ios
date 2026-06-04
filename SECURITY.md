# Security Policy

FlashbackKit records the device screen, so a security issue here can directly affect
**privacy** (captured clips, leaked sensitive content, secure-field bypass). We take
reports seriously and appreciate responsible disclosure.

> **Status:** PoC / WIP, pre-1.0. Fixes are best-effort.

## Supported versions

Being pre-1.0, only the **latest `0.1.x` release** receives security fixes. Please
reproduce on the latest version before reporting.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately via GitHub's **[Report a vulnerability](https://github.com/kensuke242424/flashbackkit-ios/security/advisories/new)**
(repository **Security** tab → **Advisories** → *Report a vulnerability*). Private
vulnerability reporting is enabled for this repository.

When reporting, please include:

- affected version (and commit if building from `main`),
- iOS version and device,
- a clear description and, ideally, reproduction steps or a proof of concept,
- the impact you observed (e.g. a clip containing data that should have been excluded).

### In scope

- The screen-recording / ring-buffer pipeline leaking content it shouldn't.
- Bypass of iOS's automatic exclusion of secure text fields.
- Exported clips or device info being written/shared somewhere unexpected.

### Out of scope

- Masking of non-secure on-screen content — this is the **host app's responsibility**
  by design (see the README's *Privacy* section).
- Issues that require a jailbroken device or a malicious app already running with elevated
  privileges.

## Disclosure

We aim to acknowledge a valid report and discuss a fix and disclosure timeline through the
private advisory. Thanks for helping keep testers' data safe.
