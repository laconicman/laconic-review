# Token setup — one-time per machine

Read this only when a `laconic-review` call fails on auth (`missingToken` /
`KeychainTokenError`). Happy path needs nothing here.

## Resolution order

1. **Env var first** — `GITLAB_TOKEN` or `GITHUB_TOKEN` (per the remote's
   forge), `--token-env <VAR>` overrides the name. An exported var always wins.
2. **Keychain fallback** — only when the var is unset *or empty*, and only if
   `--token-keychain <service>` was passed. There is no persisted setting:
   the flag must ride on **every** `laconic-review` call in the review flow
   (`resolve`, `fetch`, `publish`, `lint`, …).

## Keychain item

`<service>` is the forge host — `gitlab.flat.lab`, `github.com`, your GHES
hostname. One item per host; they coexist.

```bash
security add-generic-password -a "$USER" -s <service> -w
# prompts for the token — never put it on argv
```

- `-a` (account) is required; `$USER` matches the partner-ios convention.
- Reads are scoped to `security default-keychain` — where the add command
  writes. If you keep tokens in a different keychain, pass its path or use
  env vars instead.
- Verify: `laconic-review whoami --token-keychain <service>`.
- Locked keychain → "User interaction is not allowed"; unlock via Keychain
  Access or fall back to the env var.

The CLI reads via `/usr/bin/security find-generic-password`, not
`SecItemCopyMatching` — items added by `add-generic-password` trust that tool,
so reads stay prompt-free in headless agent shells. Do not "fix" this to a
Security-framework call.
