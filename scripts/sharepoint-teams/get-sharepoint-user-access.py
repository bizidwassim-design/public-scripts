"""
get-sharepoint-user-access.py

SYNOPSIS
    Audits every SharePoint Online site a given user can access (direct, via M365 group,
    via Graph permission or via classic SharePoint group) and exports the result to CSV.

DESCRIPTION
    Authenticates with device code (Graph + SharePoint REST; works with the public
    "Microsoft Graph Command Line Tools" client ID, no secret needed), loads the user's transitive
    groups, enumerates sites (Graph /sites, group sites, mailNickname fallback), checks
    access on every site in parallel (Graph site permissions, SharePoint REST site groups,
    M365 group membership) and writes a semicolon CSV with one row per access path.

NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Python 3.8+ | msal, requests (auto-installed) | an account allowed to read sites (SharePoint admin recommended)
    Impact      : Read-only
    License     : MIT

EXAMPLE
    python get-sharepoint-user-access.py
"""

import sys, os, csv, time, webbrowser
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

# ── Installation automatique ───────────────────────────────
for pkg in ["msal", "requests"]:
    try:
        __import__(pkg)
    except ImportError:
        import subprocess
        print(f"Installation de {pkg}...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", pkg, "-q"])

import msal, requests

# ---- EDIT ME ------------------------------------------------------------
TENANT_ID       = "<TENANT-ID>"
CLIENT_ID       = "<CLIENT-ID>"                          # voir note ci-dessous
USER_EMAIL      = "user@contoso.com"                     # usager a auditer
SP_ROOT_URL     = "https://contoso.sharepoint.com"
SP_ADMIN_URL    = "https://contoso-admin.sharepoint.com"
OUTPUT_DIR      = r"C:\Scripts\Reports"
MAX_WORKERS     = 10   # Appels paralleles
# -------------------------------------------------------------------------

GRAPH_URL       = "https://graph.microsoft.com/v1.0"

# Client ID a utiliser pour le device-code flow. Deux options :
#   - l'app publique Microsoft "Microsoft Graph Command Line Tools" (presente dans tous les tenants,
#     aucun secret requis) : l'ID est affiche par (Get-MgContext).ClientId apres un Connect-MgGraph
#   - ou le Client ID de votre propre app registration (public client, scopes delegues ci-dessous)

GRAPH_SCOPES    = [
    "https://graph.microsoft.com/Sites.Read.All",
    "https://graph.microsoft.com/User.Read.All",
    "https://graph.microsoft.com/Group.Read.All",
    "https://graph.microsoft.com/Directory.Read.All",
]
SP_SCOPES       = [f"{SP_ROOT_URL}/.default"]

# Chemin de sortie
os.makedirs(OUTPUT_DIR, exist_ok=True)
OUTPUT_CSV = os.path.join(OUTPUT_DIR, f"SharePoint_Access_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv")


# ══════════════════════════════════════════════════════════
# AUTHENTIFICATION
# ══════════════════════════════════════════════════════════
def get_token(scopes, app, label=""):
    accounts = app.get_accounts()
    if accounts:
        result = app.acquire_token_silent(scopes, account=accounts[0])
        if result and "access_token" in result:
            return result["access_token"]

    flow = app.initiate_device_flow(scopes=scopes)
    if "user_code" not in flow:
        raise Exception("Erreur device flow")

    print(f"""
  {label}
  1. Aller sur : https://microsoft.com/devicelogin
  2. Code      : {flow['user_code']}
  3. Connecte-toi avec ton compte admin
""")
    webbrowser.open("https://microsoft.com/devicelogin")
    print("  Attente de connexion...")
    result = app.acquire_token_by_device_flow(flow)
    if "access_token" in result:
        print("  OK - Connecte!\n")
        return result["access_token"]
    raise Exception(result.get("error_description", "Echec connexion"))


def authenticate():
    print("\n" + "="*60)
    print("  CONNEXION MICROSOFT 365")
    print("="*60)

    app = msal.PublicClientApplication(
        client_id=CLIENT_ID,
        authority=f"https://login.microsoftonline.com/{TENANT_ID}"
    )

    # Token Graph API
    graph_token = get_token(GRAPH_SCOPES, app, "CONNEXION GRAPH API (Microsoft 365)")

    # Token SharePoint REST API (2e connexion pour accès classiques)
    print("\n  2e connexion pour SharePoint REST API (acces classiques)...")
    try:
        sp_token = get_token(SP_SCOPES, app, "CONNEXION SHAREPOINT REST API")
    except Exception:
        print("  SharePoint REST token non disponible - mode Graph seulement")
        sp_token = None

    return graph_token, sp_token


# ══════════════════════════════════════════════════════════
# HELPERS HTTP
# ══════════════════════════════════════════════════════════
def http_get(url, token, is_sharepoint=False):
    """Appel HTTP simple avec retry"""
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json;odata=verbose" if is_sharepoint else "application/json",
    }
    if not is_sharepoint:
        headers["ConsistencyLevel"] = "eventual"

    for attempt in range(4):
        try:
            r = requests.get(url, headers=headers, timeout=20)
            if r.status_code == 429:
                time.sleep(int(r.headers.get("Retry-After", 20)))
                continue
            if r.status_code in (403, 404, 401):
                return None
            r.raise_for_status()
            return r.json()
        except requests.exceptions.Timeout:
            time.sleep(2)
        except Exception:
            if attempt == 3:
                return None
            time.sleep(2 ** attempt)
    return None


def graph_all_pages(token, path):
    """Recupere toutes les pages Graph API"""
    results = []
    url = f"{GRAPH_URL}{path}" if not path.startswith("http") else path
    while url:
        data = http_get(url, token)
        if not data:
            break
        results.extend(data.get("value", []))
        url = data.get("@odata.nextLink")
    return results


# ══════════════════════════════════════════════════════════
# ETAPE 1 - Info usager + groupes
# ══════════════════════════════════════════════════════════
def get_user_info(graph_token):
    print(f"Recherche usager: {USER_EMAIL}")
    data = http_get(
        f"{GRAPH_URL}/users/{USER_EMAIL}?$select=id,displayName,userPrincipalName,accountEnabled,department,jobTitle",
        graph_token
    )
    if not data or "id" not in data:
        raise Exception(f"Usager {USER_EMAIL} introuvable.")
    print(f"  OK: {data['displayName']} | Actif: {data.get('accountEnabled')} | Dept: {data.get('department','?')}")
    if not data.get("accountEnabled"):
        print("  ATTENTION: Compte DESACTIVE - acces listes quand meme pour audit")
    return data


def get_user_groups(graph_token, user_id):
    print("\nRecuperation des groupes...")
    groups = graph_all_pages(graph_token,
        f"/users/{user_id}/transitiveMemberOf"
        f"?$select=id,displayName,mail,mailNickname,groupTypes,visibility&$top=999"
    )
    m365  = [g for g in groups if "Unified" in g.get("groupTypes", [])]
    other = [g for g in groups if "Unified" not in g.get("groupTypes", [])]
    print(f"  Groupes M365    : {len(m365)}")
    print(f"  Groupes securite: {len(other)}")
    return m365, other, {g["id"] for g in groups if g.get("id")}


# ══════════════════════════════════════════════════════════
# ETAPE 2 - Sites SharePoint (3 methodes combinées)
# ══════════════════════════════════════════════════════════
def fetch_group_site(graph_token, group):
    """Recupere le site d'un groupe M365 - essaie plusieurs endpoints"""
    gid   = group.get("id")
    gname = group.get("displayName", "?")
    alias = group.get("mailNickname", "")

    # Methode A: endpoint officiel
    data = http_get(f"{GRAPH_URL}/groups/{gid}/sites/root?$select=id,displayName,webUrl,createdDateTime,lastModifiedDateTime", graph_token)
    if data and data.get("webUrl"):
        return data, gname, alias

    # Methode B: via le drive du groupe
    drive = http_get(f"{GRAPH_URL}/groups/{gid}/drive?$select=id,webUrl,name", graph_token)
    if drive and drive.get("webUrl"):
        # Construire URL du site depuis URL du drive
        web_url = drive["webUrl"].split("/_layouts")[0].split("/Documents")[0].split("/Shared")[0]
        return {"id": gid, "displayName": gname, "webUrl": web_url, "createdDateTime": "", "lastModifiedDateTime": ""}, gname, alias

    # Methode C: URL construite depuis mailNickname
    if alias:
        candidate = f"{SP_ROOT_URL}/sites/{alias}"
        return {"id": gid, "displayName": gname, "webUrl": candidate, "createdDateTime": "", "lastModifiedDateTime": ""}, gname, alias

    return None, gname, alias


def get_all_sites(graph_token, m365_groups):
    print("\n" + "="*60)
    print("RECHERCHE DES SITES SHAREPOINT")
    print("="*60)

    sites_map = {}  # webUrl -> site info

    # ── A: Sites directs via Graph ─────────────────────────
    print("  Recuperation liste sites Graph...")
    for path in [
        "/sites?$select=id,displayName,name,webUrl,createdDateTime,lastModifiedDateTime&$top=500",
        "/sites?search=*&$select=id,displayName,name,webUrl,createdDateTime,lastModifiedDateTime&$top=500",
    ]:
        for s in graph_all_pages(graph_token, path):
            url = s.get("webUrl", "")
            if url and url not in sites_map:
                sites_map[url] = s
    print(f"  -> {len(sites_map)} sites via Graph endpoint")

    # ── B: Sites des groupes M365 (PARALLELE) ─────────────
    print(f"  Recuperation sites des {len(m365_groups)} groupes M365 (parallele)...")

    group_sites = {}  # webUrl -> group_name
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = {ex.submit(fetch_group_site, graph_token, g): g for g in m365_groups}
        done = 0
        for future in as_completed(futures):
            done += 1
            print(f"  Groupes: {done}/{len(m365_groups)}", end="\r")
            site_data, gname, alias = future.result()
            if site_data and site_data.get("webUrl"):
                url = site_data["webUrl"]
                group_sites[url] = gname
                if url not in sites_map:
                    sites_map[url] = site_data

    print(f"\n  -> {len(sites_map)} sites total apres groupes M365")
    return list(sites_map.values()), group_sites


# ══════════════════════════════════════════════════════════
# ETAPE 3 - Verification des acces
# ══════════════════════════════════════════════════════════
def check_access_graph(graph_token, site, user_id, all_group_ids):
    """Verifie acces via Graph API permissions endpoint"""
    site_id = site.get("id", "")
    if not site_id:
        return []

    perms   = graph_all_pages(graph_token, f"/sites/{site_id}/permissions")
    matches = []

    for perm in perms:
        roles = ", ".join(perm.get("roles", []))
        checks = []

        if perm.get("grantedToV2"):
            g2 = perm["grantedToV2"]
            for key in ("user", "group"):
                if g2.get(key):
                    checks.append((key, g2[key]))

        for identity in (perm.get("grantedToIdentitiesV2") or []):
            for key in ("user", "group"):
                if identity.get(key):
                    checks.append((key, identity[key]))

        for ptype, principal in checks:
            pid   = principal.get("id", "")
            email = str(principal.get("email", "")).lower()
            pname = principal.get("displayName", "")

            if ptype == "user" and (pid == user_id or email == USER_EMAIL.lower()):
                matches.append(("Acces Direct", "", roles or "read"))
            elif ptype == "group" and pid in all_group_ids:
                matches.append(("Via Groupe Graph", pname, roles or "read"))

    return matches


def check_access_sharepoint_rest(sp_token, site_url, user_email):
    """
    Verifie acces via SharePoint REST API (couvre les groupes classiques).
    Recupere les groupes SharePoint du site et verifie si l'usager en fait partie.
    """
    if not sp_token:
        return []

    matches = []
    base = site_url.rstrip("/")

    # Recuperer les groupes SharePoint du site
    data = http_get(f"{base}/_api/web/sitegroups?$select=Id,Title,LoginName", sp_token, is_sharepoint=True)
    if not data:
        return []

    groups = data.get("d", {}).get("results", [])

    def check_group_member(group):
        gid    = group.get("Id")
        gtitle = group.get("Title", "")
        users  = http_get(
            f"{base}/_api/web/sitegroups({gid})/users?$select=Email,LoginName,Title",
            sp_token, is_sharepoint=True
        )
        if not users:
            return None
        for u in users.get("d", {}).get("results", []):
            uemail = str(u.get("Email", "")).lower()
            ulogin = str(u.get("LoginName", "")).lower()
            if uemail == user_email.lower() or user_email.lower() in ulogin:
                # Determiner le role depuis le titre du groupe
                role = "Lecture (Visitor)"
                if "owner" in gtitle.lower() or "propriet" in gtitle.lower():
                    role = "Proprietaire (Full Control)"
                elif "member" in gtitle.lower() or "membre" in gtitle.lower() or "edit" in gtitle.lower():
                    role = "Membre (Edit)"
                return (gtitle, role)
        return None

    # Verifier chaque groupe en parallele
    with ThreadPoolExecutor(max_workers=5) as ex:
        futures = {ex.submit(check_group_member, g): g for g in groups}
        for future in as_completed(futures):
            result = future.result()
            if result:
                gtitle, role = result
                matches.append(("Via Groupe SP Classique", gtitle, role))

    return matches


def check_site_access(args):
    """Fonction pour appel parallele"""
    graph_token, sp_token, site, user_id, all_group_ids, group_sites = args
    site_url  = site.get("webUrl", "")
    site_name = site.get("displayName") or site.get("name") or "?"

    all_matches = []

    # Methode 1: Graph permissions
    gmatches = check_access_graph(graph_token, site, user_id, all_group_ids)
    all_matches.extend(gmatches)

    # Methode 2: SharePoint REST (groupes classiques)
    if sp_token and site_url.startswith("https://"):
        smatches = check_access_sharepoint_rest(sp_token, site_url, USER_EMAIL)
        all_matches.extend(smatches)

    # Methode 3: Le site appartient a un groupe dont l'usager est membre
    if site_url in group_sites and not all_matches:
        gname = group_sites[site_url]
        all_matches.append(("Via Groupe M365", gname, "Membre"))

    return site, all_matches


# ══════════════════════════════════════════════════════════
# PROGRAMME PRINCIPAL
# ══════════════════════════════════════════════════════════
def main():
    print(f"""
+----------------------------------------------------------+
|  Audit Acces SharePoint (RAPIDE)                         |
|  Usager : {USER_EMAIL:<46} |
+----------------------------------------------------------+
""")
    start = datetime.now()

    # 1. Connexion
    graph_token, sp_token = authenticate()

    # 2. Usager
    user    = get_user_info(graph_token)
    user_id = user["id"]

    # 3. Groupes
    m365_groups, other_groups, all_group_ids = get_user_groups(graph_token, user_id)

    # 4. Sites
    all_sites, group_sites = get_all_sites(graph_token, m365_groups)

    # 5. Verification acces (PARALLELE)
    print("\n" + "="*60)
    print(f"VERIFICATION DES ACCES SUR {len(all_sites)} SITES (parallele)")
    print("="*60)

    rows      = []
    done      = 0
    found     = 0

    args_list = [
        (graph_token, sp_token, site, user_id, all_group_ids, group_sites)
        for site in all_sites
    ]

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = {ex.submit(check_site_access, args): args for args in args_list}

        for future in as_completed(futures):
            done += 1
            site, matches = future.result()
            site_name = site.get("displayName") or site.get("name") or "?"
            print(f"  Progres: {done}/{len(all_sites)} sites analyses", end="\r")

            if matches:
                found += 1
                print(f"\n  ACCES: {site_name}")

                # Deduplication
                seen = set()
                for access_type, principal, roles in matches:
                    key = (access_type, principal, roles)
                    if key in seen:
                        continue
                    seen.add(key)

                    rows.append({
                        "Site"              : site_name,
                        "URL"               : site.get("webUrl", ""),
                        "Cree le"           : site.get("createdDateTime", "")[:10],
                        "Modifie le"        : site.get("lastModifiedDateTime", "")[:10],
                        "Usager"            : USER_EMAIL,
                        "Nom"               : user.get("displayName", ""),
                        "Compte Actif"      : user.get("accountEnabled"),
                        "Departement"       : user.get("department", ""),
                        "Acces via"         : access_type,
                        "Groupe / Principal": principal,
                        "Role / Permission" : roles,
                        "Date Audit"        : datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    })

    # 6. Export
    print(f"\n\n{'='*60}")
    print("  RESULTATS")
    print(f"{'='*60}")
    print(f"  Sites analyses  : {len(all_sites)}")
    print(f"  Sites avec acces: {found}")
    print(f"  Lignes CSV      : {len(rows)}")

    if rows:
        rows.sort(key=lambda x: x["Site"].lower())

        with open(OUTPUT_CSV, "w", newline="", encoding="utf-8-sig") as f:
            writer = csv.DictWriter(f, fieldnames=rows[0].keys(), delimiter=";")
            writer.writeheader()
            writer.writerows(rows)

        print(f"\n  CSV : {OUTPUT_CSV}\n")
        print(f"  {'SITE':<45} {'ACCES':<25} {'ROLE'}")
        print(f"  {'-'*85}")
        for r in rows:
            print(f"  {r['Site'][:44]:<45} {r['Acces via'][:24]:<25} {r['Role / Permission']}")

        os.startfile(OUTPUT_CSV)
    else:
        print("\n  Aucun acces trouve.")
        print("  Essayer de se connecter comme admin SharePoint lors de la 2e connexion.")

    duration = (datetime.now() - start).seconds
    print(f"\n  Duree totale: {duration//60}m {duration%60}s")
    print("="*60)
    input("\n  ENTREE pour fermer...")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAnnule.")
    except Exception as e:
        print(f"\n  ERREUR: {e}")
        input("  ENTREE pour fermer...")
