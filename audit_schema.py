import os
import re

MIGRATIONS_DIR = "/Volumes/PRO-G40/COOL/supabase/migrations"

if not os.path.exists(MIGRATIONS_DIR):
    print(f"Error: {MIGRATIONS_DIR} does not exist.")
    exit(1)

tables = set()
rpc_funcs = set()
policies = {}

# Regexes
re_table = re.compile(r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-zA-Z0-9_]+)", re.IGNORECASE)
re_rpc = re.compile(r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-zA-Z0-9_]+)", re.IGNORECASE)
re_policy = re.compile(r"create\s+policy\s+(?:\"|')?([^\"']+)[\"']?\s+on\s+(?:public\.)?([a-zA-Z0-9_]+)", re.IGNORECASE)

for root, _, files in os.walk(MIGRATIONS_DIR):
    for f in files:
        if f.endswith(".sql"):
            with open(os.path.join(root, f), 'r') as file:
                content = file.read()
                
                # Tables
                for match in re_table.finditer(content):
                    tables.add(match.group(1).lower())
                    
                # RPCs
                for match in re_rpc.finditer(content):
                    rpc_funcs.add(match.group(1).lower())
                    
                # Policies
                for match in re_policy.finditer(content):
                    policy_name = match.group(1)
                    table_name = match.group(2).lower()
                    if table_name not in policies:
                        policies[table_name] = []
                    policies[table_name].append(policy_name)

print("--- TABLES ---")
for t in sorted(tables):
    print(t)
    
print("\n--- RPCS ---")
for r in sorted(rpc_funcs):
    print(r)
    
print("\n--- POLICIES ---")
for t in sorted(policies.keys()):
    print(f"{t}: {len(policies[t])} policies")
