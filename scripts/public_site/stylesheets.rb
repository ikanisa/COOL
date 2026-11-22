# frozen_string_literal: true

module CollectPublicSite
  SECTION_SELECTOR_PREFIXES = %w[
    content-grid infographic infographic-step supported-groups section-card bullet-list legal-
    group-problem group-workflow group-feature group-accumulation group-use
    problem-list use-case-grid group-journey journey-rail accumulation-panel
    change-compare insurance-work insurance-finance
    insurance-step premium-finance craas- partner- story-grid.five story-grid.six
    story-grid market-grid source-note home-flow section-number localized-
    protection-card readiness-card community-card partner-card
    trust-card policy-card terms-card deletion-card data-card
    activity-list app-list app-segments corridor-map faq-list home-app-card
    ledger- member- proof-grid protection-item record-card shield-mark
    statement- supported-group workflow-stack
  ].freeze

  def minify_css(css)
    # Whitespace before pseudo-classes can be a descendant combinator, and
    # calc() operators require surrounding spaces. Keep both intact.
    css
      .gsub(%r{/\*.*?\*/}m, "")
      .gsub(/\s+/, " ")
      .gsub(/\s*([{};,])\s*/, "\\1")
      .gsub(/;}/, "}")
      .gsub(/\b0+\./, ".")
      .gsub(/(:|\s)0(px|rem|em|%)/, "\\10")
      .gsub("#ffffff", "#fff")
      .strip
  end

  def sectional_rule?(line)
    selector = line.split("{", 2).first.to_s
    SECTION_SELECTOR_PREFIXES.any? { |prefix| selector.include?(prefix) }
  end

  def split_stylesheets(css)
    output = { core: [], sections: [] }
    media_stack = []

    css.each_line do |line|
      stripped = line.strip
      if stripped.start_with?("@media") && stripped.end_with?("{")
        media_stack << { declaration: line, opened: {} }
        next
      end

      if media_stack.any? && stripped == "}"
        frame = media_stack.pop
        frame.fetch(:opened).each_key { |target| output.fetch(target) << "}\n" }
        next
      end

      target = sectional_rule?(stripped) ? :sections : :core
      destination = output.fetch(target)
      media_stack.each do |frame|
        opened = frame.fetch(:opened)
        next if opened[target]

        destination << frame.fetch(:declaration)
        opened[target] = true
      end
      destination << line
    end

    %i[core sections].map { |target| minify_css(output.fetch(target).join) }
  end
end
