# Guide and helper decisions

These constraints keep this repository useful without turning one successful PW3 session into a general jailbreak product.

| Decision | Reason |
|---|---|
| Document only the PW3 (7th generation), firmware 5.16.2.1.1 session as tested. | One firsthand run is not evidence for other models, firmware versions, or software combinations. |
| Link to the upstream LanguageBreak README for the full procedure and current releases. | Upstream owns the exploit instructions and warns that the process deletes device content; copying the full procedure would create a stale fork. |
| Keep the file backup distinct from a device or firmware image. | USB-visible files are not a complete representation of Kindle firmware or all recoverable state. |
| Require the operator to name the source payload, exact mounted device, and mount point. | Labels and model strings can select the wrong disk; ambiguity must stop the operation. USB does not verify firmware. |
| Refuse to overwrite existing destination files and never delete device files. | Existing files may be unrelated or valuable. The operator must resolve conflicts deliberately instead of relying on recursive overwrite or filename cleanup. |
| Limit the helper to host-side check, copy, byte verification, and safe removal. | No automatic mounting, jailbreak execution, payload download, update cleanup, Kindle-side commands, or autostart is in scope. |
| Keep third-party payloads and personal backups out of the repository. | The public repository should contain instructions and helper code, not private data or redistributed binaries. |
| Do not add a license without an explicit license choice. | License terms should not be inferred from the subject matter or from a convenient template. |

The helper's verification result is intentionally narrow: matching source/destination bytes confirm only that file copy, not firmware compatibility or successful installation.
