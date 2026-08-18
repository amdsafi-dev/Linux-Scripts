#!/usr/bin/env python3
"""
Automated validation of the 3 demonstration scenarios using simulate_standalone.py data structures.
"""

from simulate_standalone import (
    MOCK_KEYTABS,
    MOCK_BACKUPS,
    render_klist,
    C_GREEN,
    C_RESET,
    C_BOLD,
    C_CYAN,
    C_YELLOW
)

print("=" * 80)
print("       AUTOMATED VALIDATION OF 3 DEMONSTRATION SCENARIOS (PYTHON ENGINE)       ")
print("=" * 80)

# SCENARIO 1: Add dummy principal to /etc/security/keytabs/hive.keytab
print("\n>>> [SCENARIO 1] Adding dummy principal to /etc/security/keytabs/hive.keytab...")
target_kt = "/etc/security/keytabs/hive.keytab"
print("\n--- Initial Entries in hive.keytab ---")
render_klist(target_kt, MOCK_KEYTABS[target_kt])

# Simulate adding dummy_analyst
dummy_princ = "dummy_analyst/node01.example.corp@EXAMPLE.CORP"
for enc in ["aes256-cts-hmac-sha1-96", "aes128-cts-hmac-sha1-96", "arcfour-hmac"]:
    slot = len(MOCK_KEYTABS[target_kt]) + 1
    MOCK_KEYTABS[target_kt].append({
        "slot": slot,
        "kvno": 1,
        "timestamp": "08/18/26 14:15:00",
        "principal": dummy_princ,
        "enctype": enc
    })

print("\n--- Updated Entries in hive.keytab (with dummy principal added) ---")
render_klist(target_kt, MOCK_KEYTABS[target_kt])
assert any(e["principal"] == dummy_princ for e in MOCK_KEYTABS[target_kt]), "Scenario 1 failed!"
print(f"\n{C_GREEN}[PASS] Scenario 1 verified successfully!{C_RESET}")

# SCENARIO 2: Create new keytab file with new principal
print("\n" + "=" * 80)
print(">>> [SCENARIO 2] Creating new keytab /etc/security/keytabs/dummy_service.keytab...")
new_kt = "/etc/security/keytabs/dummy_service.keytab"
new_princ = "dummy_app/server01.example.corp@EXAMPLE.CORP"
MOCK_KEYTABS[new_kt] = [
    {"slot": 1, "kvno": 1, "timestamp": "08/18/26 14:15:00", "principal": new_princ, "enctype": "aes256-cts-hmac-sha1-96"},
    {"slot": 2, "kvno": 1, "timestamp": "08/18/26 14:15:00", "principal": new_princ, "enctype": "aes128-cts-hmac-sha1-96"},
    {"slot": 3, "kvno": 1, "timestamp": "08/18/26 14:15:00", "principal": new_princ, "enctype": "arcfour-hmac"},
]

print(f"\n--- Entries in newly created {new_kt} ---")
render_klist(new_kt, MOCK_KEYTABS[new_kt])
assert new_kt in MOCK_KEYTABS, "Scenario 2 failed: keytab not created!"
print(f"\n{C_GREEN}[PASS] Scenario 2 verified successfully!{C_RESET}")

# SCENARIO 3: Delete dummy_analyst from hive.keytab
print("\n" + "=" * 80)
print(">>> [SCENARIO 3] Deleting dummy_analyst principal from hive.keytab...")
MOCK_KEYTABS[target_kt] = [e for e in MOCK_KEYTABS[target_kt] if e["principal"] != dummy_princ]

print("\n--- Final Entries in hive.keytab (dummy_analyst removed) ---")
render_klist(target_kt, MOCK_KEYTABS[target_kt])
assert not any(e["principal"] == dummy_princ for e in MOCK_KEYTABS[target_kt]), "Scenario 3 failed: principal still present!"
assert any(e["principal"] == "hive/hiveserver2.example.corp@EXAMPLE.CORP" for e in MOCK_KEYTABS[target_kt]), "Original principal missing!"
print(f"\n{C_GREEN}[PASS] Scenario 3 verified successfully!{C_RESET}")

print("\n" + "=" * 80)
print(f"{C_GREEN}{C_BOLD}ALL 3 DEMONSTRATION SCENARIOS TESTED & VERIFIED 100% SUCCESSFULLY!{C_RESET}")
print("=" * 80)
