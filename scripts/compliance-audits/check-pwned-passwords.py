"""
SYNOPSIS
    Check a list of exported passwords against the Have I Been Pwned (k-anonymity) API.

DESCRIPTION
    Reads an Excel sheet containing a "Password" column, hashes each password with SHA-1 and
    queries https://api.pwnedpasswords.com/range/<first 5 chars> (only the prefix leaves the
    machine). Adds a "Pwned" column (Yes / No / N/A) and writes the result to a CSV.

    Suggested workflow:
      1. Export passwords from the password manager to an Excel sheet (passwords.xlsx).
      2. Optionally add a "compliant" column with the Excel formula below to rate strength
         (D2 = password cell): Weak (<14 chars), Strong (>18), Acceptable (has digit + upper
         + lower + symbol), otherwise Weak.
         =IF(LEN(D2)<14,"Weak",IF(LEN(D2)>18,"Strong",IF(AND(
            SUMPRODUCT(--ISNUMBER(FIND(MID(D2,ROW(INDIRECT("1:"&LEN(D2))),1),"0123456789")))>0,
            SUMPRODUCT(--ISNUMBER(FIND(MID(D2,ROW(INDIRECT("1:"&LEN(D2))),1),"ABCDEFGHIJKLMNOPQRSTUVWXYZ")))>0,
            SUMPRODUCT(--ISNUMBER(FIND(MID(D2,ROW(INDIRECT("1:"&LEN(D2))),1),"abcdefghijklmnopqrstuvwxyz")))>0,
            SUMPRODUCT(--ISNUMBER(FIND(MID(D2,ROW(INDIRECT("1:"&LEN(D2))),1),"!@#$%^&*(),.?""`:{}|<>")))>0),
            "Acceptable","Weak")))
      3. python check-pwned-passwords.py
      4. Review passwords_checked.csv, then delete both files securely.

NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Python 3, pandas, openpyxl, requests
    Impact      : Read-only (sends 5-char SHA-1 prefixes to the HIBP API)
    License     : MIT

EXAMPLE
    python check-pwned-passwords.py
"""

import pandas as pd
import requests
import hashlib

# ---- EDIT ME ------------------------------------------------------------
input_file_path = r'C:\Scripts\PasswordAudit\passwords.xlsx'
output_file_path = r'C:\Scripts\PasswordAudit\passwords_checked.csv'
# -------------------------------------------------------------------------


# Function to check password against the Have I Been Pwned API
def check_password(password):
    # Ensure the password is a string before encoding
    if isinstance(password, str) and password:
        sha1_hash = hashlib.sha1(password.encode('utf-8')).hexdigest().upper()
        response = requests.get(f'https://api.pwnedpasswords.com/range/{sha1_hash[:5]}')
        if response.status_code == 200:
            hashes = response.text.splitlines()
            for hash_entry in hashes:
                if hash_entry.startswith(sha1_hash[5:]):
                    return True
    return False


# Read the Excel file, keeping all columns
df = pd.read_excel(input_file_path, engine='openpyxl')

# Initialize the 'Pwned' column with 'N/A' for rows with empty passwords
df['Pwned'] = 'N/A'

# Check each password and store results in the 'Pwned' column, skipping empty passwords
df.loc[df['Password'].notna(), 'Pwned'] = df['Password'].apply(lambda password: 'Yes' if check_password(password) else 'No')

# Write the updated DataFrame with the new column to a CSV file
df.to_csv(output_file_path, index=False)

print(f"Password checking complete. Results saved to '{output_file_path}'.")
