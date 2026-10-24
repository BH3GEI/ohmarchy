# Sending the arm64 patch

`0001-arm64-cpufeature-add-arm64.hmv_idreg_quirk.patch` is against v7.3.
`checkpatch.pl --strict`: no warnings; the only errors are the placeholder
`From:`/`Signed-off-by:` lines, which the submitter replaces with their own.

Recipients (from MAINTAINERS, "ARM64 PORT"; re-check with
`scripts/get_maintainer.pl` on the current tree before sending):

- To: Catalin Marinas, Will Deacon
- Cc: linux-arm-kernel@lists.infradead.org, linux-kernel@vger.kernel.org

```sh
git am 0001-arm64-cpufeature-add-arm64.hmv_idreg_quirk.patch   # on v7.3 or later
# fix From:/Signed-off-by:, then
git send-email --to=... --cc=... HEAD~1
```

Expect pushback on working around one vendor's hypervisor in core arm64
code; the notes below the `---` line offer a generic variant.
