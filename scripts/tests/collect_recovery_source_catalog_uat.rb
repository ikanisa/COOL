# Synthetic source/restore proof only. Owns two fresh network-none containers;
# does not open hosted connections, encrypted production vaults or credentials.
require_relative 'production_archive_restore'
require 'fileutils'
require 'tmpdir'

module CollectRecoveryCatalogUat
  module_function
  def run(output)
    raise 'New absolute proof directory required' unless Pathname.new(output).absolute? && !File.exist?(output)
    FileUtils.mkdir_p(output, mode: 0o700)
    source_files = %w[scripts/audits/collect_recovery_source.rb scripts/sql/collect_recovery_source_catalog.sql
      scripts/audits/collect_encrypted_database_backup.rb scripts/tests/production_archive_restore.rb
      scripts/tests/collect_recovery_source_test.rb scripts/tests/collect_encrypted_database_backup_test.rb
      scripts/tests/production_archive_restore_test.rb scripts/tests/collect_recovery_source_catalog_uat.rb]
    bindings = source_files.to_h { |file| [file,Digest::SHA256.file(File.join(ROOT,file)).hexdigest] }
    suffix = SecureRandom.hex(5)
    containers = ["collect-catalog-source-#{suffix}","collect-catalog-restore-#{suffix}"]
    created = []
    commands = []
    cases = []
    result = { scope: 'synthetic_recovery_source_catalog_and_dump_roundtrip',
      hosted_changes: false, credentials_read: false, production_vault_opened: false, candidate_replay: false,
      image: IMAGE, source_bindings: bindings, cases: cases, commands: commands, cleanup: {} }
    invoke = lambda do |*args, input: ''|
      out,err,status = Open3.capture3(*args,stdin_data:input,binmode:true)
      index = commands.length + 1
      commands << { index: index, argv: args, stdin_sha256: Digest::SHA256.hexdigest(input), exit_code: status.exitstatus }
      private_write(File.join(output,"command-#{index}-stderr.log"),err)
      raise 'Synthetic recovery command failed; see retained command receipt' unless status.success?
      out
    end
    assertion = lambda do |name,&block|
      raise "Synthetic recovery assertion failed: #{name}" unless block.call
      cases << name
    end
    sql = lambda do |target,text|
      raise 'Unowned synthetic target refused' unless containers.include?(target) && created.include?(target)
      invoke.call('docker','exec','-i',target,'psql','-XqAt','-h','/run/collect','-U','supabase_admin',
        '-d','postgres','-v','ON_ERROR_STOP=1',input:text).strip
    end
    query = File.binread(CollectRecoverySource::QUERY_PATH)
    fixture_root = Dir.mktmpdir('collect-catalog-uat-')
    begin
      invoke.call('docker','image','inspect',IMAGE)
      containers.each do |target|
        start = <<~'SH'
          set -eu
          initdb -D /run/collect/data -U supabase_admin --auth-local=trust --auth-host=reject --no-instructions \
            --encoding=UTF8 --locale-provider=icu --icu-locale=en-US --locale=en_US.UTF-8
          exec postgres -D /run/collect/data -c listen_addresses='' -c unix_socket_directories=/run/collect \
            -c log_statement=none -c log_min_error_statement=panic -c log_error_verbosity=terse
        SH
        invoke.call('docker','run','-d','--name',target,'--label',"collect.recovery=catalog-#{suffix}",
          '--network','none','--read-only','--cap-drop=ALL','--security-opt=no-new-privileges',
          '--memory','512m','--memory-swap','512m','--user','101:102',
          '--tmpfs','/run/collect:rw,noexec,nosuid,size=256m,mode=0700,uid=101,gid=102',
          '--tmpfs','/tmp:rw,noexec,nosuid,size=32m,mode=1777','--entrypoint','sh',IMAGE,'-c',start)
        created << target
        info = JSON.parse(invoke.call('docker','inspect',target)).first
        assertion.call("#{target.include?('-source-') ? 'source' : 'restore'}_network_none_tmpfs_no_ports") do
          info.dig('HostConfig','NetworkMode') == 'none' && info.dig('HostConfig','ReadonlyRootfs') == true &&
            info.dig('HostConfig','Memory') == info.dig('HostConfig','MemorySwap') &&
            info.dig('HostConfig','PortBindings').to_h.empty? && info.fetch('Mounts').all? { |m| m['Type']=='tmpfs' }
        end
        ready = false
        30.times do
          _out,_err,state = Open3.capture3('docker','exec',target,'pg_isready','-h','/run/collect','-U','supabase_admin','-d','postgres')
          if state.success?
            ready = true
            break
          end
          sleep 0.2
        end
        raise 'Synthetic database startup timeout' unless ready
      end
      source,target = containers
      fixture = <<~'SQL'
        CREATE ROLE postgres NOSUPERUSER CREATEROLE CREATEDB LOGIN;
        CREATE ROLE collect_catalog_reader NOLOGIN;
        GRANT collect_catalog_reader TO postgres;
        ALTER DATABASE postgres OWNER TO postgres;
        SET ROLE postgres;
        CREATE SCHEMA supabase_migrations AUTHORIZATION postgres;
        CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY);
        INSERT INTO supabase_migrations.schema_migrations VALUES ('202605230001'),('20261002050000');
        CREATE SCHEMA auth AUTHORIZATION postgres;
        CREATE SCHEMA receipt_worker_private AUTHORIZATION postgres;
        ALTER DEFAULT PRIVILEGES IN SCHEMA receipt_worker_private GRANT SELECT ON TABLES TO collect_catalog_reader;
        CREATE TYPE receipt_worker_private.outcome AS ENUM ('unknown','handled');
        CREATE DOMAIN receipt_worker_private.positive_amount AS bigint CHECK (VALUE>=0);
        CREATE TABLE receipt_worker_private.events(id bigint PRIMARY KEY,amount receipt_worker_private.positive_amount NOT NULL,
          outcome receipt_worker_private.outcome NOT NULL DEFAULT 'unknown');
        CREATE TABLE public.receipts(id bigint PRIMARY KEY,event_id bigint REFERENCES receipt_worker_private.events(id),
          worker_secret text DEFAULT 'SYNTHETIC_CONFIG_SECRET');
        CREATE INDEX receipt_event_idx ON public.receipts(event_id);
        ALTER TABLE receipt_worker_private.events ENABLE ROW LEVEL SECURITY;
        CREATE POLICY reader ON receipt_worker_private.events FOR SELECT TO collect_catalog_reader USING (amount>=0);
        CREATE FUNCTION receipt_worker_private.guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
          SET search_path=pg_catalog AS $$BEGIN RETURN NEW; END$$;
        REVOKE ALL ON FUNCTION receipt_worker_private.guard() FROM PUBLIC;
        CREATE TRIGGER guard BEFORE INSERT ON public.receipts FOR EACH ROW EXECUTE FUNCTION receipt_worker_private.guard();
        CREATE VIEW public.receipt_evidence AS SELECT r.id,e.amount FROM public.receipts r JOIN receipt_worker_private.events e ON e.id=r.event_id;
        INSERT INTO receipt_worker_private.events VALUES (1,500,'handled');
        INSERT INTO public.receipts(id,event_id) VALUES (1,1);
        RESET ROLE;
      SQL
      private_write(File.join(output,'fixture.sql'),fixture)
      sql.call(source,fixture)
      raw = sql.call(source,query)
      catalog = CollectRecoverySource.parse(raw)
      private_write(File.join(output,'source-catalog.json'),raw+"\n")
      assertion.call('actual_postgresql17_catalog_query_and_closed_shapes') { CollectRecoverySource.catalog!(catalog) }
      assertion.call('all_application_schemas_including_worker_seen') do
        %w[auth public receipt_worker_private supabase_migrations] == catalog.fetch('schemas').map(&:first)
      end
      assertion.call('body_default_configuration_values_are_hashed') { !raw.include?('SYNTHETIC_CONFIG_SECRET') && !raw.include?('BEGIN RETURN NEW') }
      assertion.call('repeat_read_catalog_is_stable') { catalog == CollectRecoverySource.parse(sql.call(source,query)) }
      FileUtils.mkdir_p(File.join(fixture_root,'supabase/migrations'))
      File.write(File.join(fixture_root,'supabase/migrations/202605230001_fixture.sql'),'-- fixture source1')
      File.write(File.join(fixture_root,'supabase/migrations/20261002050000_fixture.sql'),'-- fixture source2')
      document = CollectRecoverySource.build(catalog,root:fixture_root)
      private_write(File.join(output,'synthetic-source-contract.json'),JSON.pretty_generate(document)+"\n")
      sql.call(source,"UPDATE receipt_worker_private.events SET amount=600 WHERE id=1;")
      assertion.call('business_row_changes_do_not_masquerade_as_schema_identity') { CollectRecoverySource.verify_catalog!(document,CollectRecoverySource.parse(sql.call(source,query))) }
      mutations = [
        ['table_acl','GRANT SELECT ON public.receipts TO collect_catalog_reader;', 'REVOKE SELECT ON public.receipts FROM collect_catalog_reader;'],
        ['rls','ALTER TABLE receipt_worker_private.events DISABLE ROW LEVEL SECURITY;', 'ALTER TABLE receipt_worker_private.events ENABLE ROW LEVEL SECURITY;'],
        ['owner','ALTER TABLE receipt_worker_private.events OWNER TO supabase_admin;', 'ALTER TABLE receipt_worker_private.events OWNER TO postgres;'],
        ['function_body',"CREATE OR REPLACE FUNCTION receipt_worker_private.guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN RAISE EXCEPTION 'synthetic'; END$$;",
          "CREATE OR REPLACE FUNCTION receipt_worker_private.guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN RETURN NEW; END$$;"],
        ['default_acl','ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA receipt_worker_private GRANT UPDATE ON TABLES TO collect_catalog_reader;',
          'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA receipt_worker_private REVOKE UPDATE ON TABLES FROM collect_catalog_reader;'],
        ['membership','GRANT collect_catalog_reader TO postgres WITH ADMIN OPTION;', 'REVOKE ADMIN OPTION FOR collect_catalog_reader FROM postgres;'],
        ['foreign_key_fence','ALTER TABLE public.receipts DROP CONSTRAINT receipts_event_id_fkey; ALTER TABLE public.receipts ADD CONSTRAINT receipts_event_id_fkey FOREIGN KEY(event_id) REFERENCES receipt_worker_private.events(id) DEFERRABLE INITIALLY DEFERRED;',
          'ALTER TABLE public.receipts DROP CONSTRAINT receipts_event_id_fkey; ALTER TABLE public.receipts ADD CONSTRAINT receipts_event_id_fkey FOREIGN KEY(event_id) REFERENCES receipt_worker_private.events(id);'],
        ['new_worker_relation','CREATE TABLE receipt_worker_private.new_journal(id bigint);','DROP TABLE receipt_worker_private.new_journal;']
      ]
      mutations.each do |name,change,undo|
        sql.call(source,change)
        observed = CollectRecoverySource.parse(sql.call(source,query))
        refused = false
        begin
          CollectRecoverySource.verify_catalog!(document,observed)
        rescue CollectRecoverySource::Error
          refused = true
        end
        assertion.call("#{name}_drift_refused") { refused }
        sql.call(source,undo)
        assertion.call("#{name}_undo_exact_catalog") { CollectRecoverySource.verify_catalog!(document,CollectRecoverySource.parse(sql.call(source,query))) }
      end
      dump = invoke.call('docker','exec',source,'pg_dump','-w','-h','/run/collect','-U','supabase_admin','-d','postgres','--format=custom')
      roles = invoke.call('docker','exec',source,'pg_dumpall','-w','-h','/run/collect','-U','supabase_admin','-l','postgres','--roles-only','--no-role-passwords')
      toc = invoke.call('docker','run','--rm','-i','--read-only','--network','none','--entrypoint','pg_restore',IMAGE,'--list',input:dump)
      private_write(File.join(output,'synthetic.toc'),toc)
      schemas = CollectRecoverySource.archive_schemas(toc)
      assertion.call('dynamic_archive_schema_coverage_matches_catalog') { (catalog['schemas'].map(&:first)-schemas).empty? }
      sql.call(target,roles.sub("CREATE ROLE supabase_admin;\n",''))
      sql.call(target,'ALTER DATABASE postgres OWNER TO postgres;')
      restore = invoke.call('docker','run','--rm','-i','--read-only','--network','none','--entrypoint','pg_restore',IMAGE,'--file=-',input:dump)
      sql.call(target,"BEGIN;\n#{restore}\nCOMMIT;\n")
      restored_raw = sql.call(target,query)
      private_write(File.join(output,'restored-catalog.json'),restored_raw+"\n")
      restored_catalog = CollectRecoverySource.parse(restored_raw)
      result[:restored_catalog_differing_sections] = catalog.keys.select { |key| catalog[key] != restored_catalog[key] }
      assertion.call('actual_dump_restore_catalog_matches_exact_source_contract') do
        CollectRecoverySource.verify_catalog!(document,restored_catalog)
      end
      source_data = invoke.call('docker','exec',source,'pg_dump','-w','-h','/run/collect','-U','supabase_admin','-d','postgres','--data-only')
      target_data = invoke.call('docker','exec',target,'pg_dump','-w','-h','/run/collect','-U','supabase_admin','-d','postgres','--data-only')
      assertion.call('actual_restored_data_values_match_separately') { data_fingerprint(source_data) == data_fingerprint(target_data) }
      result[:catalog_sha256] = document['catalog_sha256']
      result[:archive_sha256] = Digest::SHA256.hexdigest(dump)
      result[:all_candidate_sources_observed_not_replayed] = { count: CollectRecoverySource.sources.length,
        sha256: CollectRecoverySource.digest(CollectRecoverySource.sources) }
      result[:source_bindings_after] = source_files.to_h { |file| [file,Digest::SHA256.file(File.join(ROOT,file)).hexdigest] }
      assertion.call('all_eight_affected_sources_unchanged') { bindings == result[:source_bindings_after] }
      result[:result] = 'PASS_SYNTHETIC_CATALOG_ROUNDTRIP_NOT_CURRENT_CANDIDATE_RECOVERY'
    rescue StandardError => error
      result[:result] = 'FAILED'
      result[:error] = error.message
    ensure
      created.reverse_each do |target|
        begin
          info = JSON.parse(invoke.call('docker','inspect',target)).first
          raise 'Synthetic cleanup ownership mismatch' unless info.dig('Config','Labels','collect.recovery') == "catalog-#{suffix}"
          invoke.call('docker','rm','-f',target)
          result[:cleanup][target] = 'removed'
        rescue StandardError
          result[:cleanup][target] = 'requires_attention'
        end
      end
      FileUtils.remove_entry(fixture_root)
      private_write(File.join(output,'result.json'),JSON.pretty_generate(result)+"\n")
    end
    puts JSON.generate({ result: result[:result], cases: cases.length, commands: commands.length, cleanup: result[:cleanup] })
    result[:result].start_with?('PASS_') && result[:cleanup].values.all? { |state| state=='removed' }
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_recovery_source_catalog_uat.rb --network-none-fixture NEW_ABS_PROOF_DIRECTORY') unless
    ARGV.length==2 && ARGV[0]=='--network-none-fixture'
  exit(CollectRecoveryCatalogUat.run(ARGV[1]) ? 0 : 1)
end
