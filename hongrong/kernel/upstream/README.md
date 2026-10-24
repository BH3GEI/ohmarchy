# Upstream submissions (drafts, not sent)

Nothing here has been submitted. Sending needs the owner's go-ahead, and the
`Signed-off-by` lines must be added by the person submitting: it is their
Developer Certificate of Origin, not something a tool can sign for them.

| Target | Directory | Content |
|---|---|---|
| Arch Linux ARM, `core/linux-aarch64` (github.com/archlinuxarm/PKGBUILDs) | [alarm/](alarm/) | PR: two patches + PKGBUILD change, [PR.md](alarm/PR.md) |
| Linux mainline (arm64) | [lkml/](lkml/) | one patch against v7.3, [send notes](lkml/README.md) |

Both are opt-in: without `arm64.hmv_idreg_quirk` on the command line the
kernel behaves exactly as before.
