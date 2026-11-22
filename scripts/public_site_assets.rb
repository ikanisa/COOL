# frozen_string_literal: true

require_relative "public_site/stylesheets"
require_relative "public_site/site_script"

module CollectPublicSite
  ICON_ASSET = "assets/brand/collect_runtime/app_icons/app-icon-rule.png"
  TYPEFACE_ASSETS = %w[
    assets/typefaces/Inter-Variable.ttf
  ].freeze
  TYPEFACE_LICENSE = "assets/typefaces/OFL-Inter.txt"

  def stylesheet
    File.read(File.join(ROOT, "web/public/layout.css"))
  end

  def copy_public_well_known(source_root, build_root)
    source_directory = File.join(source_root, "web", ".well-known")
    return unless Dir.exist?(source_directory)

    target_directory = File.join(build_root, ".well-known")
    FileUtils.mkdir_p(target_directory)
    Dir.children(source_directory).sort.each do |entry|
      next if entry.start_with?("._") || entry == ".DS_Store"

      source = File.join(source_directory, entry)
      next unless File.file?(source)

      FileUtils.cp(source, File.join(target_directory, entry))
    end
  end

  def copy_public_asset(source, relative_destination, build_dir:)
    destination = File.join(build_dir, relative_destination)
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.cp(source, destination)
  end

  def write_assets(photography, public_app_screens, build_dir: BUILD_DIR)
    core_stylesheet, section_stylesheet = split_stylesheets(stylesheet)
    write_file(File.join(build_dir, "styles.css"), core_stylesheet)
    write_file(File.join(build_dir, "sections.css"), section_stylesheet)
    write_file(File.join(build_dir, "revolut.css"), photography.prepare_css(File.read(File.join(ROOT, "web/public/revolut.css"))))
    write_file(File.join(build_dir, "site.js"), site_js)

    assets = [
      ICON_ASSET,
      *TYPEFACE_ASSETS,
      TYPEFACE_LICENSE,
      *Dir.glob("assets/marketing/rwanda/*.png", base: ROOT)
    ]
    assets.each do |asset|
      source = File.join(ROOT, asset)
      next unless File.file?(source)

      copy_public_asset(source, asset, build_dir: build_dir)
    end
    photography.copy_to(build_dir)

    public_app_screens.each_value do |media|
      copy_public_asset(media.fetch("source"), media.fetch("url").delete_prefix("/"), build_dir: build_dir)
    end

    copy_public_asset(File.join(ROOT, ICON_ASSET), "icons/collect.png", build_dir: build_dir)

    copy_public_well_known(ROOT, build_dir)
  end
end
