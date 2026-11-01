# Contributing

## Conventions every script follows

1. **Comment-based help** at the top: `.SYNOPSIS`, `.DESCRIPTION`, `.NOTES` (Requires, Impact), `.EXAMPLE`.
2. **`# ---- EDIT ME ----` block** right after the help: every value an operator must change (SMTP server, recipients,
   paths, OUs, group names, thresholds). No environment value anywhere else in the file.
3. **Impact is stated honestly**: `Read-only`, or `Modifies <what>` with the exact actions.
4. **Approved PowerShell verbs** and `Verb-Noun.ps1` file names; KQL files are `kebab-case.kql`.
5. **No secrets, no real identifiers.** Use `contoso.com`, `corp.contoso.local`, `192.0.2.x`, `<TENANT-ID>`, `<API-KEY>`.
6. **One job per script.** Prefer a second script over a flag that changes behaviour.

## Before you open a pull request

```powershell
pwsh tools/Test-Library.ps1            # parse + secret/identifier scan (same as CI)
python tools/build_catalogue.py         # after adding a row to docs/catalogue.csv
```

A new script needs a row in `docs/catalogue.csv` (`category,file,title,description,requires,impact`).

## What is welcome

* Fixes, Graph-API migrations (MSOnline / AzureAD → Microsoft.Graph), PowerShell 7 compatibility.
* New scripts that solve a real recurring task for an identity / SOC / IT-ops team.
* Translations of headers and comments.

## Ground rules

* No real company data, incident details, customer names or IOCs. Fictional examples only.
* Submit only code you wrote yourself.
* Respect the [Code of Conduct](CODE_OF_CONDUCT.md). Contributions are released under the [MIT License](LICENSE).
