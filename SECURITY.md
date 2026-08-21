# Security

Omarchy plugins execute unsandboxed inside the long-running `omarchy-shell`
process. Review this repository before installing it.

Please report a suspected vulnerability privately through GitHub's
**Security → Report a vulnerability** flow for this repository. Do not include
credentials, clipboard contents, or other sensitive data in a public issue.

Unified Launcher renders externally controlled strings as `Text.PlainText` and
keeps clipboard and reminder runtime state in Omarchy's standard state and
runtime directories.
