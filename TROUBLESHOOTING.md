# Kindle Paperwhite 3 LanguageBreak troubleshooting

Use this page to interpret the recorded PW3 session, not as a universal diagnosis. For current LanguageBreak steps, follow the [upstream README](https://github.com/notmarek/LanguageBreak/blob/master/README.MD). Stop if your device, firmware, or screen differs from the instructions you are following.

## `Update Failed` after the time-sensitive transfer

**Observed once:** `jb` and `patchedUks.sqsh` were zero bytes after the approximately 20-second transfer window was missed. The hotfix then showed `Update Failed`. A later attempt transferred the files during the required window, produced the expected jailbreak log messages, and the `es-MX` hotfix succeeded.

Before retrying, confirm that the source payload is complete and that copied files are not zero bytes. A host-side hash comparison can show whether a particular copied file matches its selected source; it cannot diagnose firmware compatibility or prove that the jailbreak ran. Re-read the upstream recovery steps before retrying. Do not assume every `Update Failed` has this cause.

## A file is already present in the Kindle root

The upstream guide discusses pending update files before installation. Identify any file using the upstream guidance and the device context. Do not remove unrelated `.bin`, `.partial`, or temporary files based only on a filename pattern. If you cannot determine what a file is, stop and preserve it until you can verify its purpose.

The local helper is not designed to clean up the Kindle. It must not delete existing files or silently select an update file for you.

## Do not use the helper for LanguageBreak transfers

The helper refuses existing destination paths and has no overwrite option. The upstream LanguageBreak procedure copies its payload twice and may require replacing files during the second, time-sensitive transfer. Use the [upstream manual transfer instructions](https://github.com/notmarek/LanguageBreak/blob/master/README.MD) for both LanguageBreak copies; the helper is not a full installer.

## The host cannot see USB storage

Check the Kindle's current screen and reconnect only as described by the upstream instructions. The host-side helper does not search for a drive by label or model: the operator must identify the exact mounted device and mount point. If either is ambiguous, do not copy or eject anything.

In the recorded setup, KOReader had to be exited before the Kindle exposed USB mass storage. This is a firsthand observation, not a claim about every software version or configuration.

## PEKI did not appear; KUAL worked through MRPI

In the recorded setup, the PEKI (`KUAL.sh`) entry did not appear in the library. KUAL then worked after opening MRPI with `;log mrpi` and running its booklet. A `kppmainappv2` core dump was also recorded, but it did not prevent KUAL from working. This is a firsthand result from one PW3, not a general compatibility claim. Check current, device-specific KUAL/MRPI documentation before repeating installation steps.

## SimpleUI and `Project: Title`

`Project: Title` was removed after it conflicted with SimpleUI in the recorded setup. This does not establish that all versions conflict. The tested SimpleUI version was 2.7.5; KOReader was v2026.07.1 (`kindlepw2`), and LocalSend was v1.4.5 (`armv7`). These are historical session details, not current-version recommendations.

## Scope limits

- The only device/firmware combination documented as tested here is Kindle Paperwhite 3 (7th generation), firmware 5.16.2.1.1.
- USB file visibility and file hashes do not verify firmware, model compatibility, or internal installation state.
- The upstream LanguageBreak README warns that installation deletes device content. Back up files you need before starting; a USB-visible file backup is not a full-device image.
- The helper cannot perform either LanguageBreak payload transfer because it refuses overwrites; use the upstream manual steps instead.
- KOReader autostart was declined and is not installed by this guide.
