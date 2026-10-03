#!/usr/bin/env ruby
# frozen_string_literal: true

# Rehearse staged financial SQL only in the task-owned, pristine local Docker
# database. Never accepts a project URL, arbitrary container, or live database.
require 'digest'
require 'json'
require 'time'
require_relative '../qa/fullstack_database_sql'

module FinancialSqlRehearsal
  ROOT = FullstackDatabase::ROOT
  DATABASE = 'collect_financial_revocation_uat_20260928'
  SOURCES = %w[
    deploy/hardening/receipt_security_v2.sql
    deploy/hardening/reconciliation_approval_v2.sql
    scripts/hardening/receipt_v2_uat.sql
    scripts/hardening/reconciliation_revocation_uat.sql
  ].freeze
  MARKERS = %w[RECEIPT_V2_UAT_PASS RECONCILIATION_REVOCATION_UAT_PASS].freeze

  def self.run(output_directory, replay_report: nil)
    raise 'A new evidence directory is required' if File.exist?(output_directory)
    baseline = FullstackDatabaseSql.verified_baseline(replay_report: replay_report)
    files = SOURCES.to_h { |name| [name, Digest::SHA256.file(File.join(ROOT, name)).hexdigest] }
    sql = <<~SQL
      \\set ON_ERROR_STOP on
      do $$ begin
        if current_database() <> '#{DATABASE}'
           or exists(select 1 from public.payments)
           or exists(select 1 from public.raw_payment_sms) then
          raise exception 'Pristine isolated financial rehearsal clone required';
        end if;
      end $$;
      #{File.read(File.join(ROOT, SOURCES[0]))}
      #{File.read(File.join(ROOT, SOURCES[1]))}
      set collect.financial_rehearsal = 'staged-v2';
      #{File.read(File.join(ROOT, SOURCES[2]))}
      #{File.read(File.join(ROOT, SOURCES[3]))}
    SQL
    Dir.mkdir(output_directory, 0o700)
    report = {
      schema_version: 1, status: 'fail', source_files: files,
      executed_sql_sha256: Digest::SHA256.hexdigest(sql),
      replay_report: baseline[:replay_path], target: baseline[:target],
      database: DATABASE, started_at: Time.now.utc.iso8601(6),
      scope: 'isolated synthetic SQL rehearsal only; no provider authenticity or release approval',
      cleanup: {status: 'pending'}
    }
    created = false
    begin
      FullstackDatabase.verify!
      FullstackDatabaseSql.execute!('createdb', '-U', 'postgres', '--template=postgres', DATABASE)
      created = true
      report[:before] = FullstackDatabaseSql.readback(DATABASE)
      stdout, stderr, status = FullstackDatabaseSql.docker(
        'psql', '-XAt', '-U', 'postgres', '-d', DATABASE, '-v', 'ON_ERROR_STOP=1', input: sql
      )
      log = File.join(output_directory, 'reconciliation_revocation_uat.log')
      File.open(log, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(stdout + stderr) }
      report[:log] = log
      report[:log_sha256] = Digest::SHA256.file(log).hexdigest
      report[:exit_code] = status.exitstatus
      report[:markers_found] = MARKERS.to_h { |marker| [marker, stdout.include?(marker)] }
      report[:rollback_count] = stdout.lines.count { |line| line.strip == 'ROLLBACK' }
      report[:after] = FullstackDatabaseSql.readback(DATABASE)
      report[:source_unchanged] = files.all? do |name, sha|
        sha == Digest::SHA256.file(File.join(ROOT, name)).hexdigest
      end
      report[:case_pass] = status.success? && report[:markers_found].values.all? &&
        report[:rollback_count] == 2 && report[:before] == report[:after] && report[:source_unchanged]
    rescue StandardError => error
      report[:error] = error.message
      if error.is_a?(FullstackDatabase::CommandTimeout)
        report[:command_outcome] = 'unverified_after_client_timeout'
        report[:partial_stdout] = error.output
        report[:partial_stderr] = error.error
      end
    ensure
      if created
        begin
          FullstackDatabase.verify!
          FullstackDatabaseSql.execute!('dropdb', '-U', 'postgres', DATABASE)
          report[:cleanup] = {status: 'pass', action: 'dropped_created_clone'}
        rescue StandardError => error
          report[:cleanup] = {status: 'fail', action: 'drop_created_clone', error: error.message}
        end
      else
        report[:cleanup] = {status: 'skipped', action: 'creation_not_confirmed_no_drop'}
      end
      report[:status] = report[:case_pass] && report[:cleanup][:status] == 'pass' ? 'pass' : 'fail'
      report[:finished_at] = Time.now.utc.iso8601(6)
      File.open(File.join(output_directory, 'report.json'), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |f|
        f.write(JSON.pretty_generate(report) + "\n")
      end
    end
    report[:status] == 'pass'
  end
end

if $PROGRAM_NAME == __FILE__
  replay = ARGV.find { |arg| arg.start_with?('--replay-report=') }
  ARGV.delete(replay) if replay
  abort('Usage: rehearse_financial_sql.rb NEW_EVIDENCE_DIRECTORY [--replay-report=PATH]') unless ARGV.length == 1
  begin
    exit(FinancialSqlRehearsal.run(ARGV.first, replay_report: replay&.split('=', 2)&.last) ? 0 : 1)
  rescue StandardError => error
    warn "Financial SQL rehearsal blocked: #{error.message}"
    exit 1
  end
end
