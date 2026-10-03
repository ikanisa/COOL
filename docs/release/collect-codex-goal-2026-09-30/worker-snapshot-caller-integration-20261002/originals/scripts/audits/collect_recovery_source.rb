# Local source identity for the existing encrypted backup and isolated restore.
# Loading/preparing a contract performs no network, credential or vault action.
require 'json'
require 'digest'
require 'pathname'

module CollectRecoverySource
  ROOT = File.expand_path('../..', __dir__).freeze
  PROJECT = 'lhbowpbcpwoiparwnwgt'.freeze
  FORMAT = 'collect-recovery-source-v1'.freeze
  QUERY_PATH = File.join(ROOT, 'scripts/sql/collect_recovery_source_catalog.sql').freeze
  LIMIT = 32 * 1024**2
  HEX = /\A[0-9a-f]{64}\z/
  VERSION = /\A(?:[0-9]{12}|[0-9]{14})\z/
  ROW_LENGTHS = { 'schemas'=>3, 'extensions'=>4, 'roles'=>11, 'memberships'=>6,
    'settings'=>3, 'relations'=>10, 'columns'=>11, 'constraints'=>8, 'indexes'=>6,
    'functions'=>13, 'policies'=>8, 'triggers'=>5, 'default_acls'=>4, 'types'=>9,
    'event_triggers'=>6, 'dependencies'=>7 }.freeze
  DATABASE_KEYS = %w[name owner encoding locale_provider collate ctype locale icu_rules_sha256
    collation_version connection_limit acl].freeze
  class Error < RuntimeError; end
  class StrictObject < Hash
    def []=(key, value)
      raise Error, 'Duplicate recovery JSON key' if key?(key)
      super
    end
  end
  module_function

  def parse(raw)
    raise Error, 'Recovery JSON exceeds size limit' unless raw.is_a?(String) && raw.bytesize <= LIMIT
    JSON.parse(raw, object_class: StrictObject, max_nesting: 64)
  rescue JSON::ParserError, JSON::NestingError, EncodingError
    raise Error, 'Invalid recovery JSON'
  end

  def read(path)
    raise Error, 'Absolute regular recovery file required' unless path.is_a?(String) && Pathname.new(path).absolute?
    before = File.lstat(path)
    raise Error, 'Absolute regular recovery file required' unless before.file? && before.size <= LIMIT
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      now = file.stat
      raise Error, 'Recovery file changed during open' unless now.ino == before.ino && now.dev == before.dev
      data = file.read(LIMIT + 1)
      raise Error, 'Recovery JSON exceeds size limit' if data.bytesize > LIMIT
      data
    end
  rescue SystemCallError
    raise Error, 'Recovery file unavailable'
  end

  def canonical(value)
    case value
    when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array then value.map { |item| canonical(item) }
    when String, Integer, TrueClass, FalseClass, NilClass then value
    else raise Error, 'Invalid recovery JSON value'
    end
  end

  def digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def keys!(value, expected)
    raise Error, 'Recovery object shape mismatch' unless value.is_a?(Hash) && value.keys.sort == expected.sort
  end

  def catalog!(catalog)
    keys!(catalog, ['format','server','database','migrations'] + ROW_LENGTHS.keys)
    raise Error, 'Recovery catalog format mismatch' unless catalog['format'] == 'collect-recovery-catalog-v1'
    keys!(catalog['server'], %w[major version])
    raise Error, 'PostgreSQL17 recovery catalog required' unless catalog.dig('server','major') == 17 &&
      catalog.dig('server','version').is_a?(String) && catalog.dig('server','version').start_with?('17.')
    keys!(catalog['database'], DATABASE_KEYS)
    raise Error, 'Recovery source database mismatch' unless catalog.dig('database','name') == 'postgres'
    versions = catalog['migrations']
    raise Error, 'Invalid recovery migration vector' unless versions.is_a?(Array) && !versions.empty? &&
      versions.all? { |v| v.is_a?(String) && VERSION.match?(v) } && versions == versions.sort && versions.uniq == versions
    ROW_LENGTHS.each do |key, length|
      rows = catalog[key]
      raise Error, 'Recovery catalog row shape mismatch' unless rows.is_a?(Array) &&
        rows.all? { |row| row.is_a?(Array) && row.length == length }
    end
    names = catalog['schemas'].map(&:first)
    raise Error, 'Invalid recovery schema identities' unless names.all? { |n| n.is_a?(String) && !n.empty? } && names == names.sort && names.uniq == names
    canonical(catalog) # Refuse floats/non-JSON objects, including nested values.
    catalog
  end

  def sources(root: ROOT)
    files = Dir.glob(File.join(root, 'supabase/migrations/*.sql')).sort
    raise Error, 'Recovery migration sources absent' if files.empty?
    rows = files.map do |file|
      name = File.basename(file)
      match = /\A([0-9]{12}|[0-9]{14})_[a-zA-Z0-9_]+\.sql\z/.match(name)
      raise Error, 'Invalid recovery migration filename' unless match
      raise Error, 'Migration source must be a regular file' unless File.lstat(file).file?
      { 'path'=>"supabase/migrations/#{name}", 'version'=>match[1], 'sha256'=>Digest::SHA256.file(file).hexdigest }
    end
    raise Error, 'Duplicate recovery migration versions' unless rows.map { |r| r['version'] }.uniq.length == rows.length
    rows
  end

  def build(catalog, root: ROOT)
    catalog!(catalog)
    files = sources(root: root)
    raise Error, 'Catalog and migration source versions differ' unless catalog['migrations'] == files.map { |row| row['version'] }
    { 'format'=>FORMAT, 'project'=>PROJECT, 'catalog_query_sha256'=>Digest::SHA256.file(QUERY_PATH).hexdigest,
      'migration_files'=>files, 'catalog_sha256'=>digest(catalog), 'catalog'=>catalog }
  end

  def load(path, sha256, root: ROOT)
    raise Error, 'Pinned recovery contract hash required' unless sha256.is_a?(String) && HEX.match?(sha256)
    raw = read(path)
    raise Error, 'Recovery contract hash mismatch' unless Digest::SHA256.hexdigest(raw) == sha256
    document = parse(raw)
    keys!(document, %w[format project catalog_query_sha256 migration_files catalog_sha256 catalog])
    raise Error, 'Recovery source contract identity mismatch' unless document['format'] == FORMAT && document['project'] == PROJECT
    expected = build(document.fetch('catalog'), root: root)
    raise Error, 'Recovery source contract differs from current inputs' unless canonical(document) == canonical(expected)
    document
  end

  def association(document, sha256)
    { 'format'=>FORMAT, 'sha256'=>sha256, 'catalog_sha256'=>document.fetch('catalog_sha256'),
      'catalog_query_sha256'=>document.fetch('catalog_query_sha256'),
      'migration_source_sha256'=>digest(document.fetch('migration_files')),
      'migrations'=>document.fetch('migration_files').length }
  end

  def verify_catalog!(document, actual)
    catalog!(actual)
    raise Error, 'Observed recovery source catalog differs from contract' unless digest(actual) == document.fetch('catalog_sha256')
    true
  end

  def check(catalog)
    catalog!(catalog)
    { 'database'=>catalog.dig('database','name'), 'version'=>catalog.dig('server','version'),
      'migrations'=>catalog.fetch('migrations').length, 'catalog_sha256'=>digest(catalog) }
  end

  def query(document)
    raw = File.binread(QUERY_PATH)
    raise Error, 'Recovery catalog query changed' unless Digest::SHA256.hexdigest(raw) == document.fetch('catalog_query_sha256')
    raw
  end

  def verify_extension_metadata!(document, metadata)
    catalog = document.fetch('catalog')
    versions = catalog.fetch('extensions').map { |row| { 'name'=>row[0], 'version'=>row[1] } }
    owners = catalog.fetch('extensions').map { |row| { 'name'=>row[0], 'owner'=>row[3] } }
    wrapper = metadata.is_a?(Hash) && metadata['wrapper']
    hash = metadata.is_a?(Hash) && metadata['definition_sha256']
    functions = catalog.fetch('functions').select { |row| row[0] == 'graphql_public' && row[1] == 'graphql' }
    raise Error, 'Extension recovery metadata differs from source contract' unless metadata.is_a?(Hash) &&
      metadata['project'] == PROJECT && wrapper.is_a?(Hash) && wrapper['installed_extensions'] == versions &&
      wrapper['extension_owners'] == owners && wrapper['owner'] == 'supabase_admin' && wrapper['extension'] == 'pg_graphql' &&
      wrapper['definition'].is_a?(String) && hash.is_a?(String) && HEX.match?(hash) &&
      Digest::SHA256.hexdigest(wrapper['definition']) == hash &&
      functions.any? { |row| row[4] == 'supabase_admin' && row[12] == hash }
    true
  end

  def verify_report!(report, document, sha256, scope)
    raise Error, 'Recovery capture contract association mismatch' unless report.is_a?(Hash) &&
      report['project'] == PROJECT && report['capture_scope'] == scope &&
      report['source_contract'] == association(document, sha256) &&
      report['source_check'] == check(document.fetch('catalog')) && report['source_catalog_after_matches'] == true
    true
  end

  def archive_schemas(toc)
    toc.lines.map do |line|
      # pg_dump omits CREATE SCHEMA for pristine public; its objects still have
      # public as their TOC namespace. Extension-owned empty schemas may have
      # neither entry: only the full restored catalog proves those namespaces.
      line[/\A[0-9]+;\s+[0-9]+\s+[0-9]+\s+SCHEMA - (\S+) \S+\s*\z/,1] ||
        line[/\A[0-9]+;\s+[0-9]+\s+[0-9]+\s+[A-Z][A-Z ]* (\S+) \S+/,1]
    end.compact.reject { |name| name == '-' }.sort.uniq
  end

  # Pair/duplicate/unknown-option refusal happens before any credential prompt.
  def options(argv, kind)
    args = argv.dup
    result = {}
    flags = kind == :backup ? %w[--roles-only] : %w[--rehearse-migrations]
    values = %w[--source-contract --source-contract-sha256]
    values += %w[--database-report --roles-report --extension-metadata] if kind == :restore
    positions = []
    until args.empty?
      item = args.shift
      if flags.include?(item)
        raise Error, 'Duplicate recovery option' if result.key?(item)
        result[item] = true
      elsif values.include?(item)
        raise Error, 'Duplicate or incomplete recovery option' if result.key?(item) || args.empty? || args.first.start_with?('--')
        result[item] = args.shift
      elsif item.start_with?('--') && !(kind == :backup && item == '--approved-ip-129.222.149.205')
        raise Error, 'Unknown recovery option'
      else
        positions << item
      end
    end
    valid = kind == :backup ? positions.length == 2 && positions[0] == '--approved-ip-129.222.149.205' : positions.length == 1
    raise Error, 'Invalid recovery arguments' unless valid
    paired = %w[--source-contract --source-contract-sha256].count { |k| result.key?(k) }
    raise Error, 'Recovery contract path and hash must be paired' unless [0,2].include?(paired)
    if kind == :restore
      explicit = %w[--database-report --roles-report --extension-metadata].count { |k| result.key?(k) }
      raise Error, 'All three recovery inputs must be supplied together' unless [0,3].include?(explicit)
      raise Error, 'Current recovery contract requires explicit archive and extension inputs' if paired == 2 && explicit != 3
      raise Error, 'Historical migration rehearsal cannot accept a current contract' if paired == 2 && result['--rehearse-migrations']
    end
    result['output'] = positions.last
    result
  end

  def selected_contract(options, root: ROOT)
    return nil unless options.key?('--source-contract')
    load(options.fetch('--source-contract'), options.fetch('--source-contract-sha256'), root: root)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise CollectRecoverySource::Error, 'Usage: collect_recovery_source.rb prepare ABS_CATALOG.json NEW_ABS_CONTRACT.json' unless
      ARGV.length == 3 && ARGV[0] == 'prepare' && Pathname.new(ARGV[2]).absolute?
    document = CollectRecoverySource.build(CollectRecoverySource.parse(CollectRecoverySource.read(ARGV[1])))
    encoded = JSON.pretty_generate(document) + "\n"
    File.open(ARGV[2], File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(encoded); file.fsync }
    puts JSON.generate({ source_contract_sha256: Digest::SHA256.hexdigest(encoded), migrations: document['migration_files'].length,
      catalog_sha256: document['catalog_sha256'], network_actions: false, credential_actions: false })
  rescue CollectRecoverySource::Error, SystemCallError
    warn 'Recovery source preparation refused; verify the explicit input, current sources and unused output path.'
    exit 1
  end
end
