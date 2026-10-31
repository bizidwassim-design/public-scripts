# Sanitisation — how this library was made safe to publish

The scripts were written and used in a real environment. Before publication every environment-specific value was
replaced, and a scanner now enforces that nothing of the kind comes back.

## What was replaced

| Original kind of value | Placeholder used |
|------------------------|------------------|
| Organisation name | `Contoso` |
| Public domain / AD forest | `contoso.com` / `corp.contoso.local` |
| OU paths | `OU=Workstations,DC=corp,DC=contoso,DC=local` and similar |
| E-mail addresses | `security@contoso.com`, `it-support@contoso.com`, `user@contoso.com` |
| Servers, domain controllers, sites | `SRV-APP01`, `DC01`, `Site-A`, `smtp.contoso.com` |
| Private IP addresses | hostnames, or RFC 5737 documentation addresses (`192.0.2.x`, `198.51.100.x`) |
| Tenant / application / subscription IDs | `<TENANT-ID>`, `<CLIENT-ID>`, `<SUBSCRIPTION-ID>` |
| API keys, tokens, webhooks, SMTP credentials | `<API-KEY>`, `<SECRET>`, `<WEBHOOK-URL>` — read from a vault or prompt at run time |
| Employee, manager and contractor names | removed or `Jane Doe` |
| Vendor-specific OU / group names | `VendorName` |
| Local paths | `C:\Scripts\...` |

Naming **conventions** that a script depends on (for example laptops named `L-*` and desktops `D-*`) are kept and
documented in the `EDIT ME` block, because the logic needs a pattern — change it to yours.

Product names (Microsoft 365, Entra ID, Defender, Exchange Online, SharePoint, NinjaOne, PDQ Connect, TeamViewer,
Meraki, Terranova, Atlassian, Nmap…) are public products and are kept.

## How it is enforced

`tools/Test-Library.ps1` runs in CI on every push and pull request and fails on:

* any PowerShell syntax error (the file is parsed, never executed);
* private IPv4 addresses, e-mail addresses outside `contoso.com` / `example.*`, GUIDs, `password = "..."` literals,
  bearer or API tokens, Teams/Slack webhook URLs;
* any word listed in `tools/denylist.txt` or in your own git-ignored `tools/denylist.local.txt` — in scripts **and** in the documentation, catalogue and tooling.

If you fork this library for your own organisation, add your company name, domains, site codes and server prefixes to
`tools/denylist.local.txt` (git-ignored) and `tools/denylist.txt` **before** you start committing, and the same check protects you.
