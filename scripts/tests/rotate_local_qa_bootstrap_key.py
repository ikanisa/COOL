#!/usr/bin/env python3
"""Replace the exposed key in the exact disposable Collect QA environment.

Default mode is a metadata-only assessment. Execution requires quiet databases,
empty encrypted source stores, the pinned image/project/volume and an exact
recognized bootstrap. It preserves the named data volume and supports rollback
until source fingerprints and real Vault cryptography have been verified.
Keys and container environment values are never printed or retained in reports.
Generated evidence must use the security plugin's prepared temporary directory.
"""
import argparse
import copy
from contextlib import ExitStack
import hashlib
import http.client
import json
from pathlib import Path
import re
import secrets
import socket
import subprocess
import time
from urllib.parse import quote
import uuid

import local_schema_uat as local

R, U = local.R, local.U
EXPOSED = "4bb72687b307acae07be6ac5d5bea9b76c5da1adfc05db5b399d6544b87f84b8"
IMAGE = "public.ecr.aws/supabase/postgres:17.6.1.095"
IMAGE_ID = "sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a"
PROJECT = "collect_fin_concurrency_qa_20260929"
KEYFILE = "/var/lib/postgresql/data/.collect-pgsodium-root-key"
SYNTHETIC_SECRET = "SYNTHETIC isolated root-key validation; no customer secret"


class Engine:
    def __init__(self):
        p = subprocess.run([U.DOCKER, "context", "inspect"], capture_output=True, text=True)
        if p.returncode:
            raise RuntimeError("local_docker_context_unavailable")
        endpoint = json.loads(p.stdout)[0]["Endpoints"]["docker"]["Host"]
        if not endpoint.startswith("unix://"):
            raise RuntimeError("local_unix_docker_socket_required")
        self.socket_path = endpoint.removeprefix("unix://")

    def call(self, method, path, body=None):
        connection = http.client.HTTPConnection("localhost", timeout=40)
        connection.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.sock.settimeout(40)
        connection.sock.connect(self.socket_path)
        try:
            encoded = json.dumps(body).encode() if body is not None else None
            connection.request(method, path, body=encoded, headers={"Content-Type": "application/json"})
            response = connection.getresponse()
            result = response.read()
            if response.status not in (200, 201, 204, 304):
                # Engine error bodies may echo configuration. Retain only status.
                raise RuntimeError("docker_api_status_" + str(response.status))
            return json.loads(result) if result else None
        finally:
            connection.close()

    def inspect(self, reference):
        try:
            return self.call("GET", "/containers/" + reference + "/json")
        except RuntimeError as error:
            if str(error) == "docker_api_status_404":
                return None
            raise


def json_sql(database, body):
    result = U.psql(database, body, False)
    if result.returncode:
        raise RuntimeError("metadata_sql_failed_" + database)
    return json.loads(result.stdout.strip().splitlines()[-1])


def assess():
    databases = json_sql("postgres", "select to_jsonb(array_agg(datname order by datname)) from pg_database where not datistemplate;")
    active_clients = json_sql("postgres", """select to_jsonb(count(*)) from pg_stat_activity
      where pid<>pg_backend_pid() and backend_type='client backend' and state<>'idle';""")
    source_databases = {"postgres", "_supabase"}
    usage = {}
    for database in sorted(source_databases):
        value = json_sql(database, """select jsonb_build_object(
          'pgsodium_schema',to_regnamespace('pgsodium') is not null,
          'vault_table',to_regclass('vault.secrets') is not null,
          'encrypted_labels',(select count(*) from pg_seclabel where provider='pgsodium'),
          'application_dependencies',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname not in('pg_catalog','information_schema','pgsodium','vault') and p.prosrc ilike '%pgsodium.%'));""")
        value["vault_rows"] = json_sql(database, "select to_jsonb(count(*)) from vault.secrets;") if value["vault_table"] else 0
        usage[database] = value
    return dict(databases=databases, source_databases=sorted(source_databases), crypto_usage=usage,
                other_active_clients=active_clients, quiet_clients=active_clients == 0,
                quiet_database_set=set(databases) == source_databases,
                encrypted_source_empty=all(not x['pgsodium_schema'] and x['encrypted_labels'] == 0
                                          and x['application_dependencies'] == 0 and x['vault_rows'] == 0
                                          for x in usage.values()))


def reviewed_config(container):
    config = container["Config"]
    if not container["State"]["Running"] or config["Image"] != IMAGE or container["Image"] != IMAGE_ID:
        raise RuntimeError("exact_running_qa_image_required")
    if config.get("Labels", {}).get("com.docker.compose.project") != PROJECT:
        raise RuntimeError("exact_qa_project_required")
    mounts = container["Mounts"]
    if (len(mounts) != 1 or mounts[0]["Type"] != "volume" or mounts[0].get("Name") != U.CONTAINER
            or mounts[0]["Destination"] != "/var/lib/postgresql/data" or not mounts[0]["RW"]):
        raise RuntimeError("single_preserved_data_volume_required")
    entry = config.get("Entrypoint")
    if not isinstance(entry, list) or len(entry) != 3 or entry[:2] != ["sh", "-c"] or config.get("Cmd") is not None:
        raise RuntimeError("reviewed_qa_bootstrap_shape_required")
    literals = re.findall(r"(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])", entry[2])
    if len(literals) != 1 or hashlib.sha256(literals[0].encode()).hexdigest() != EXPOSED:
        raise RuntimeError("reviewed_exposed_key_hash_required")
    old_key = literals[0]
    old_command = "cat <<'EOF' > /etc/postgresql-custom/pgsodium_root.key"
    old_document = "\n" + old_key + "\nEOF\n"
    if entry[2].count(old_command) != 1 or entry[2].count(old_document) != 1:
        raise RuntimeError("reviewed_key_heredoc_boundaries_required")
    updated = copy.deepcopy(config)
    wrapper = entry[2].replace(old_command,
        "test -s " + KEYFILE + " && cat " + KEYFILE + " > /etc/postgresql-custom/pgsodium_root.key && "
        "chown postgres:postgres /etc/postgresql-custom/pgsodium_root.key && "
        "chmod 0600 /etc/postgresql-custom/pgsodium_root.key || exit 1", 1).replace(old_document, "\n", 1)
    updated["Entrypoint"] = ["sh", "-c", wrapper]
    if old_key in json.dumps(updated):
        raise RuntimeError("old_key_survives_configuration_replacement")
    checked = subprocess.run(["/bin/sh", "-n"], input=wrapper, capture_output=True, text=True)
    if checked.returncode:
        raise RuntimeError("replacement_shell_syntax_invalid")
    return updated, old_key


def internal_database_fingerprint():
    """Hash internal source rows in SQL; never retrieve their plaintext."""
    tables = json_sql("_supabase", """select coalesce(jsonb_agg(format('%I.%I',n.nspname,c.relname)
      order by n.nspname,c.relname),'[]'::jsonb) from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where c.relkind in('r','p') and n.nspname not like 'pg_%' and n.nspname<>'information_schema';""")
    rows = {table: json_sql("_supabase", "select jsonb_build_object('rows',count(*),'md5',"
            "md5(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''))) from " + table + " t;")
            for table in tables}
    dump = U.command([U.DOCKER, "exec", U.CONTAINER, "pg_dump", "-U", "postgres",
                      "-d", "_supabase", "--schema-only"]).stdout
    # PostgreSQL17 randomly generates psql restrict tokens on each dump. Only
    # those framing lines are removed; owners, grants and all DDL remain bound.
    stable = re.sub(r"^\\(?:un)?restrict [^\n]*\n", "", dump, flags=re.M)
    return dict(tables=rows, schema_sha256=R.sha(stable.encode()))


def replacement_container(engine, original, new_id, rotation_id):
    """Resolve an uncertain create response without touching another container."""
    observed = engine.inspect(new_id or U.CONTAINER)
    if observed is None or observed["Id"] == original["Id"]:
        return None
    if (observed["Config"].get("Labels", {}).get("collect.qa.bootstrap.rotation") != rotation_id
            or observed["Image"] != original["Image"]
            or len(observed["Mounts"]) != 1
            or observed["Mounts"][0].get("Name") != original["Mounts"][0]["Name"]):
        raise RuntimeError("unrecognized_replacement_container")
    return observed


def restore_original(engine, original, new_id, rotation_id, renamed, stopped,
                     key_install_attempted, new_key_file_sha256):
    """Idempotent recovery, including create/rename responses lost in transit."""
    replacement = replacement_container(engine, original, new_id, rotation_id)
    if replacement:
        if replacement["State"]["Running"]:
            engine.call("POST", "/containers/" + replacement["Id"] + "/stop?t=30")
        engine.call("DELETE", "/containers/" + replacement["Id"] + "?v=false")
    observed = engine.inspect(original["Id"])
    if observed is None:
        raise RuntimeError("original_recovery_container_missing")
    if renamed and observed["Name"] != "/" + U.CONTAINER:
        engine.call("POST", "/containers/" + original["Id"] + "/rename?name=" + quote(U.CONTAINER))
    if stopped and not observed["State"]["Running"]:
        engine.call("POST", "/containers/" + original["Id"] + "/start")
    wait_ready()
    if key_install_attempted:
        removed = subprocess.run([U.DOCKER, "exec", U.CONTAINER, "sh", "-c",
            "if test -e " + KEYFILE + "; then test \"$(sha256sum " + KEYFILE
            + " | cut -d' ' -f1)\" = " + new_key_file_sha256 + " && rm -- " + KEYFILE + "; fi"],
            capture_output=True, text=True)
        if removed.returncode:
            raise RuntimeError("rollback_fresh_key_file_cleanup_failed")


def wait_ready():
    for _ in range(180):
        result = U.psql("postgres", "select 1;", False)
        if not result.returncode:
            return
        time.sleep(.5)
    raise RuntimeError("qa_readiness_timeout")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not any(p.name.startswith("codex-security-artifacts-") for p in report.parents):
        parser.error("Fresh output inside plugin-prepared temporary storage required")
    report.mkdir(parents=True, mode=0o700)
    evidence = dict(status="running", execute_requested=args.execute, keys_retained=False,
                    source_rows_copied=False, volume_deleted=False, business_migrations_installed=False)
    engine = Engine()
    original = engine.call("GET", "/containers/" + U.CONTAINER + "/json")
    replacement, old_key = reviewed_config(original)
    metadata = assess()
    evidence.update(assessment=metadata, exposed_key_sha256=EXPOSED,
                    original_container_id=original["Id"], original_image_id=original["Image"],
                    data_volume_name=original["Mounts"][0]["Name"],
                    replacement_contains_old_key=False, replacement_shell_syntax_valid=True,
                    runner_sha256=R.sha(Path(__file__).read_bytes()))
    R.guard(154, "20260930230000")
    if not args.execute:
        evidence.update(status="assessed", replacement_complete=False,
                        execution_allowed=metadata['quiet_database_set'] and metadata['quiet_clients']
                                          and metadata['encrypted_source_empty'])
        R.save(report / "result.json", evidence)
        print(json.dumps(evidence))
        return
    if not metadata['quiet_database_set'] or not metadata['quiet_clients'] or not metadata['encrypted_source_empty']:
        raise RuntimeError("quiet_empty_encrypted_source_required")
    rotation_id = uuid.uuid4().hex
    prior_name = U.CONTAINER + "_prior_key_" + rotation_id[:8]
    replacement.setdefault("Labels", {})["collect.qa.bootstrap.rotation"] = rotation_id
    new_id, renamed, stopped, committed = None, False, False, False
    key_install_attempted, transition_verified = False, False
    internal_before = internal_database_fingerprint()
    new_key = secrets.token_hex(32)
    if hashlib.sha256(new_key.encode()).hexdigest() == EXPOSED:
        raise RuntimeError("fresh_key_required")
    new_key_file_sha256 = R.sha((new_key + "\n").encode())

    def rollback():
        # Restore the original service before the clone manager's cleanup and
        # preservation queries. Its literal bootstrap also restores the old key.
        nonlocal new_id, renamed, stopped, key_install_attempted
        restore_original(engine, original, new_id, rotation_id, renamed, stopped,
                         key_install_attempted, new_key_file_sha256)
        new_id, renamed, stopped, key_install_attempted = None, False, False, False
        evidence["original_container_restored"] = True

    try:
        with ExitStack() as cleanup:
            db = cleanup.enter_context(local.isolated(report, evidence, count=154, latest="20260930230000"))
            cleanup.callback(lambda: rollback() if not transition_verified else None)
            old_secret_id = json_sql(db, "select to_jsonb(vault.create_secret(" + R.literal(SYNTHETIC_SECRET) + "));")
            if json_sql(db, "select to_jsonb(decrypted_secret) from vault.decrypted_secrets where id=" + R.literal(old_secret_id) + ";") != SYNTHETIC_SECRET:
                raise RuntimeError("prior_crypto_positive_control_failed")
            # The secret travels only over stdin. It is absent from process args,
            # Docker configuration, console output and retained evidence.
            staging = "/var/lib/postgresql/data/.collect-key-stage-" + rotation_id
            key_install_attempted = True
            installed = subprocess.run([U.DOCKER, "exec", "-i", U.CONTAINER, "sh", "-c",
                "set -eu; umask 077; test ! -e " + KEYFILE + "; mkdir " + staging
                + "; trap 'rm -f " + staging + "/key; rmdir " + staging + "' EXIT; cat > " + staging
                + "/key; chown postgres:postgres " + staging + "/key; chmod 0600 " + staging
                + "/key; ln " + staging + "/key " + KEYFILE],
                input=new_key + "\n", capture_output=True, text=True)
            if installed.returncode:
                raise RuntimeError("fresh_mounted_key_install_failed")
            stopped = True
            engine.call("POST", "/containers/" + original["Id"] + "/stop?t=30")
            renamed = True
            engine.call("POST", "/containers/" + original["Id"] + "/rename?name=" + quote(prior_name))
            replacement["Image"] = original["Image"]  # immutable existing image ID
            replacement["HostConfig"] = original["HostConfig"]
            created = engine.call("POST", "/containers/create?name=" + quote(U.CONTAINER), replacement)
            new_id = created["Id"]
            engine.call("POST", "/containers/" + new_id + "/start")
            wait_ready()
            R.guard(154, "20260930230000")
            active = replacement_container(engine, original, new_id, rotation_id)
            if active is None or not active["State"]["Running"]:
                raise RuntimeError("active_replacement_container_required")
            if old_key in json.dumps(active["Config"]) or active["Mounts"][0]["Name"] != evidence['data_volume_name']:
                raise RuntimeError("active_startup_key_or_volume_mismatch")
            old_decrypt = U.psql(db, "select decrypted_secret from vault.decrypted_secrets where id=" + R.literal(old_secret_id) + ";", False)
            if not old_decrypt.returncode or not re.search(r"decrypt|cipher|mac",old_decrypt.stderr,re.I):
                raise RuntimeError("old_key_ciphertext_still_decrypts")
            if json_sql(db,"select to_jsonb(count(*)) from vault.secrets where id=" + R.literal(old_secret_id) + ";") != 1:
                raise RuntimeError("old_ciphertext_fixture_not_retained")
            new_secret_id = json_sql(db, "select to_jsonb(vault.create_secret(" + R.literal(SYNTHETIC_SECRET) + "));")
            if json_sql(db, "select to_jsonb(decrypted_secret) from vault.decrypted_secrets where id=" + R.literal(new_secret_id) + ";") != SYNTHETIC_SECRET:
                raise RuntimeError("fresh_crypto_positive_control_failed")
            permissions = subprocess.run([U.DOCKER,"exec",U.CONTAINER,"stat","-c","%a:%U",
                                           KEYFILE,"/etc/postgresql-custom/pgsodium_root.key"],
                                          capture_output=True,text=True)
            if permissions.returncode or permissions.stdout.splitlines() != ["600:postgres","600:postgres"]:
                raise RuntimeError("private_key_file_permissions_required")
            if internal_database_fingerprint() != internal_before:
                raise RuntimeError("internal_database_rows_changed")
            evidence.update(old_key_ciphertext_rejected=True, fresh_crypto_roundtrip=True,
                            new_key_sha256=hashlib.sha256(new_key.encode()).hexdigest(),
                            active_container_id=new_id, active_data_volume_preserved=True,
                            both_key_files_private=True, internal_database_rows_preserved=True)
            transition_verified = True
        if not evidence.get("all_source_tables_catalog_cron_preserved") or not evidence.get("isolated_database_removed"):
            raise RuntimeError("shared_source_preservation_failed")
        # All source/crypto gates have passed. An uncertain old-container DELETE
        # must not attempt rollback to a possibly deleted object. Reconcile the
        # exact ID; retain the verified replacement if final cleanup fails.
        committed = True
        try:
            engine.call("DELETE", "/containers/" + original["Id"] + "?v=false")
        except Exception:
            if engine.inspect(original["Id"]) is not None:
                raise
        if engine.inspect(original["Id"]) is not None:
            raise RuntimeError("old_container_cleanup_incomplete")
        evidence.update(status="pass", replacement_complete=True, old_container_removed=True)
    except Exception as error:
        evidence.update(status="failed", failure_type=type(error).__name__, replacement_complete=False)
        if not committed:
            rollback()
        raise
    finally:
        R.save(report / "result.json", evidence)
    print(json.dumps(evidence))


if __name__ == "__main__":
    main()
