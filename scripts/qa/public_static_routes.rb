# frozen_string_literal: true

require 'json'
require 'ripper'

# Read Ruby syntax as data. Requiring/evaluating the builder would validate media
# and replace a build directory, which route discovery must never do.
module PublicStaticRoutes
  ROOT = File.expand_path('../..', __dir__)
  SOURCE = 'scripts/public_static_site_build.rb'.freeze

  def self.walk(node, &block)
    return unless node.is_a?(Array)
    yield node
    node.each { |child| walk(child, &block) if child.is_a?(Array) }
  end

  def self.literal(node)
    parts = node.is_a?(Array) && node[0] == :string_literal && node[1]
    unless parts && parts[0] == :string_content && parts.length == 2 && parts[1][0] == :@tstring_content
      raise 'Literal route strings required; interpolated or dynamic paths need explicit review'
    end
    [parts[1][1], parts[1][2][0]]
  end

  def self.arguments(node)
    args = node.dig(2, 1)
    raise 'Explicit call arguments required' unless args && args[0] == :args_add_block && args[2] == false
    args[1]
  end

  def self.call?(node, name)
    node.is_a?(Array) && node[0] == :method_add_arg && node.dig(1, 0) == :fcall && node.dig(1, 1, 1) == name
  end

  def self.build_path_arguments(node)
    unless node.is_a?(Array) && node[0] == :method_add_arg && node.dig(1, 0) == :call &&
           node.dig(1, 1, 1, 1) == 'File' && node.dig(1, 3, 1) == 'join'
      return nil
    end
    args = arguments(node)
    return nil unless args.first&.first == :var_ref && args.first.dig(1, 1) == 'BUILD_DIR'
    args.drop(1)
  end

  def self.extract(text)
    tree = Ripper.sexp(text) or raise 'Static website builder has invalid Ruby syntax'
    assignments = []
    walk(tree) { |node| assignments << node if node[0] == :assign && node.dig(1, 1, 1) == 'PAGES' }
    raise 'Exactly one static PAGES declaration required' unless assignments.length == 1
    value = assignments.first[2]
    value = value[1] if value[0] == :call && value.dig(3, 1) == 'freeze'
    raise 'Static PAGES array required' unless value[0] == :array && value[1]&.any?
    routes = []
    value[1].each do |page|
      raise 'Literal page records required' unless page[0] == :hash
      fields = {}
      (page.dig(1, 1) || []).each do |pair|
        raise 'Named page fields required' unless pair[0] == :assoc_new && pair.dig(1, 0) == :@label
        key = pair[1][1].delete_suffix(':')
        raise "Duplicate page field: #{key}" if fields.key?(key)
        fields[key] = pair[2]
      end
      path, line = literal(fields.fetch('path'))
      routes << { path: path, line: line, kind: 'page', primary_route: path }
      if fields['aliases']
        raise 'Literal alias array required' unless fields['aliases'][0] == :array
        (fields['aliases'][1] || []).each do |item|
          alias_path, alias_line = literal(item)
          routes << { path: alias_path, line: alias_line, kind: 'alias', primary_route: path }
        end
      end
    end
    walk(tree) do |node|
      next unless call?(node, 'write_file')
      args = arguments(node)
      path_args = build_path_arguments(args[0])
      if call?(args[1], 'share_landing_page_html')
        raise 'Explicit share landing build path required' unless path_args
        destination = path_args.map { |part| literal(part) }
        unless destination.length >= 2 && destination.last[0] == 'index.html'
          raise 'Share landing must write a named route index.html'
        end
        path = '/' + destination[0...-1].map(&:first).join('/') + '/'
        routes << { path: path, line: destination.first[1], kind: 'share_landing' }
      elsif path_args&.length == 1 && path_args.first.dig(0) == :string_literal &&
            path_args.first.dig(1, 1, 1) == '_redirects'
        literal(path_args.first)
        rules, line = literal(args[1])
        rules.gsub('\\n', "\n").lines.each do |rule|
          next if rule.strip.empty?
          source, target, status, extra = rule.split
          unless source && target&.start_with?('/') && status&.match?(/\A30[1278]\z/) && !extra
            raise 'Unexpected static redirect rule'
          end
          routes << { path: source, line: line, kind: 'redirect_pattern', redirect_target: target, redirect_status: status.to_i }
        end
      end
    end
    paths = routes.map { |route| route.fetch(:path) }
    raise 'Duplicate static route' unless paths.uniq == paths
    raise 'Unexpected route path' unless paths.all? { |path| path.match?(%r{\A/[a-zA-Z0-9_/*-]*\z}) }
    routes
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: public_static_routes.rb') unless ARGV.empty?
  puts JSON.pretty_generate(PublicStaticRoutes.extract(File.read(File.join(PublicStaticRoutes::ROOT, PublicStaticRoutes::SOURCE))))
end
