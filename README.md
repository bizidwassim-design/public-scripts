# Public Scripts — Windows, Microsoft 365 & SOC automation

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![CI](https://github.com/bizidwassim-design/public-scripts/actions/workflows/ci.yml/badge.svg)](https://github.com/bizidwassim-design/public-scripts/actions/workflows/ci.yml) [![Secret scan](https://img.shields.io/badge/secret%20scan-every%20push-success)](tools/Test-Library.ps1) [![Sanitised](https://img.shields.io/badge/environment%20data-sanitised-informational)](docs/sanitisation.md)

**121 scripts** written over several years of running a security operations and identity programme for a
mid-sized organisation — Active Directory and Entra ID audits, Exchange Online and SharePoint reporting,
Microsoft Defender hunting queries, endpoint administration, network checks and the recurring compliance jobs
that e-mail a report every month. Each script is self-contained, documented in its header, and has every
environment-specific value hoisted into an **`EDIT ME`** block at the top.

> 🇫🇷 Résumé en français en bas de page.

## Catalogue

<!-- catalogue:start -->
| Category | Scripts | Scope |
|----------|--------:|-------|
| [Active Directory](docs/catalogue.md#active-directory) | 42 | users, computers, groups, OUs, GPOs, LAPS, DC event logs, DHCP |
| [Entra ID & Microsoft Graph](docs/catalogue.md#entra-id-microsoft-graph) | 12 | devices, guests, Conditional Access, MFA, sign-ins, licences |
| [Exchange Online](docs/catalogue.md#exchange-online) | 7 | mailboxes, forwarding, delegates, distribution lists, message purge |
| [SharePoint & Teams](docs/catalogue.md#sharepoint-teams) | 3 | sites, owners, access audits |
| [Microsoft Defender — KQL hunting](docs/catalogue.md#microsoft-defender-kql-hunting) | 2 | advanced-hunting queries and MDE health checks |
| [Endpoint administration](docs/catalogue.md#endpoint-administration) | 28 | local admins, registry, software, Windows Update, printers, agents, USB |
| [Network](docs/catalogue.md#network) | 9 | Nmap, open ports, connection monitoring, Meraki, geolocation |
| [Recurring compliance checks](docs/catalogue.md#recurring-compliance-checks) | 10 | scheduled jobs that audit AD/Entra and e-mail a report |
| [Utilities](docs/catalogue.md#utilities) | 8 | CSV, files, Excel-driven updates, backups |
<!-- catalogue:end -->

Full list with one line per script: [docs/catalogue.md](docs/catalogue.md).

## Using a script

```powershell
git clone https://github.com/bizidwassim-design/public-scripts.git
cd public-scripts
Get-Help .\scripts\active-directory\Get-InactiveADUsers.ps1 -Full   # every script has comment-based help
```

1. Open the script and fill in the `# ---- EDIT ME ----` block (SMTP server, report recipient, output path, OU…).
2. Check the `Impact` line in the header: **read-only** scripts can be run as-is; scripts that **modify** AD, Entra ID,
   Exchange or the local machine should be tested in a lab or on a pilot OU first.
3. Required modules are listed under `Requires` (ActiveDirectory, ExchangeOnlineManagement, Microsoft.Graph, ImportExcel…).
4. KQL files (`scripts/defender-kql/*.kql`) are pasted into Microsoft Defender → Advanced hunting.

Recurring checks (`scripts/compliance-audits/`) are designed to run from a scheduled task on a management server
with a least-privilege service account; `scripts/endpoint/New-ScheduledTaskFromPowerShell.ps1` shows how.

## What makes this library safe to reuse

* **Sanitised.** Every company name, domain, OU, hostname, IP, tenant ID, e-mail address and person name was replaced
  by `contoso.com`-style placeholders before publication — see [docs/sanitisation.md](docs/sanitisation.md).
* **Scanned on every push.** `tools/Test-Library.ps1` parses every script (no execution) and fails CI if a private IP,
  a non-example e-mail, a GUID, a password literal, a token or a deny-listed word appears anywhere under `scripts/`.
* **No third-party code.** Microsoft and community scripts that were used alongside these are linked, not copied —
  [docs/third-party.md](docs/third-party.md).
* **No secrets, ever.** Credentials are read from the environment, a vault or an interactive prompt — never stored.

## Contributing

Improvements, fixes and new scripts that follow the same conventions are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Run `pwsh tools/Test-Library.ps1` before opening a pull request.

## Disclaimer

These scripts were written for real operational needs and are shared as-is. Read them before running them:
several change directory objects, mailboxes or local machines. Test in a non-production environment. No warranty.

## License

[MIT](LICENSE).

---

## 🇫🇷 Résumé

Bibliothèque de **121 scripts** PowerShell et KQL issus de plusieurs années d'exploitation d'un programme de
sécurité et d'identité : audits Active Directory et Entra ID, rapports Exchange Online et SharePoint, requêtes
de chasse Microsoft Defender, administration des postes, vérifications réseau et contrôles de conformité
récurrents envoyés par courriel. Chaque script est documenté, ses valeurs d'environnement sont regroupées dans un
bloc `EDIT ME`, et toutes les données identifiantes ont été remplacées par des exemples (`contoso.com`). Un contrôle
automatique en intégration continue vérifie la syntaxe et l'absence de secrets à chaque modification. Licence MIT.
