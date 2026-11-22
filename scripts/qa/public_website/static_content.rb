# frozen_string_literal: true

require_relative "../public_capability_contract"
require_relative "../public_content_contract"
require_relative "../../public_app_media"

module PublicWebsiteStaticContent
  private

  def check_route_copy(checks, build_dir, root_html, stylesheet, product_capabilities)
    privacy_text = read(route_index(build_dir, "/privacy/"))
    policy_ok = privacy_text.include?("Privacy Policy") &&
      privacy_text.include?("We do not sell personal data") &&
      privacy_text.include?("Account deletion and data deletion") &&
      privacy_text.include?("info@ikanisa.com") &&
      !privacy_text.match?(/\b(?:privacy|support|complaints|partnerships)@ikanisa\.com\b/) &&
      !privacy_text.match?(/\[[A-Za-z][A-Za-z ]+\]/)
    check(
      checks,
      "policy_content",
      policy_ok,
      policy_ok ? "Policy route contains Play deletion contact content." : "Policy route lacks required deletion/contact content."
    )

    conversion = home_conversion_evidence(product_capabilities, root_html)
    public_app_and_whatsapp_support = home_conversion_ok?(product_capabilities, root_html, conversion)
    check(
      checks,
      "public_app_and_whatsapp_support_conversion",
      public_app_and_whatsapp_support,
      public_app_and_whatsapp_support ? "Root exposes the canonical Android app/group actions, email support and existing WhatsApp contact without an email form." : "Root is missing a canonical capability action or supported contact, or exposes an unsupported support form.",
      conversion
    )

    links = privacy_link_evidence(privacy_text)
    semantic_privacy_links_ok = links.values.all?(&:empty?)
    check(
      checks,
      "privacy_semantic_links",
      semantic_privacy_links_ok,
      semantic_privacy_links_ok ? "Privacy policy exposes clearly named links to existing policy sections, account deletion and the supported email request channel." : "Privacy policy is missing a clearly named supported destination or links to an absent route.",
      links
    )

    all_html_paths = Dir.glob(File.join(build_dir, "**", "*.html")).select { |path| File.file?(path) }
    stray_brace_files = all_html_paths.select do |path|
      read(path).lines.any? { |line| line.match?(/\A\s*}\s*\z/) }
    end
    check(
      checks,
      "no_stray_template_brace",
      stray_brace_files.empty?,
      stray_brace_files.empty? ? "Generated public HTML has no visible standalone template brace." : "Generated public HTML contains standalone template brace text.",
      "files" => stray_brace_files.map { |path| path.delete_prefix(build_dir + "/") }
    )

    # Exact historical hashes remain in the dated baseline. Current product copy
    # requires the additive itemized engineering review and its bound source bytes.
    generated_routes = all_html_paths.map do |path|
      relative = path.delete_prefix(build_dir).delete_suffix("index.html")
      relative.empty? ? "/" : relative
    end.reject { |route| ["/app/", "/c/", "/group-link/"].include?(route) }.sort
    content_pages = generated_routes.to_h { |route| [route, read(route_index(build_dir, route))] }
    current_content = PublicContentContract.evaluate(root: Dir.pwd, pages: content_pages, routes: generated_routes)
    check(
      checks,
      "pre_audit_content_parity",
      current_content.fetch('status') == 'pass',
      current_content['status'] == 'pass' ? "Public routes match the reviewed current Collect product-copy contract; historical evidence is retained." : "Public content or its reviewed source evidence changed.",
      current_content
    )

    trust_text = read(route_index(build_dir, "/trust/"))
    trust_page_ok = trust_text.include?("How Collect protects customer information") &&
      trust_text.include?("What Collect will not do") &&
      trust_text.include?("Partner and regulated-product boundary") &&
      trust_text.include?("Customer rights and deletion support") &&
      !trust_text.include?("13. Security and trust") &&
      !trust_text.include?("9. AI and automated processing") &&
      !trust_text.include?("Recommended Trust Commitment Subject To Technical Confirmation")
    check(
      checks,
      "trust_center_standalone",
      trust_page_ok,
      trust_page_ok ? "Trust route is a standalone trust center, not a Privacy Policy duplicate." : "Trust route still duplicates numbered Privacy Policy sections or lacks trust-center content."
    )

    trust_sidebar_removed_ok = trust_text.include?('class="legal-layout no-sidebar"') &&
      !trust_text.include?('class="legal-sidebar"') &&
      !trust_text.include?('class="legal-toc"') &&
      !trust_text.include?("On this page") &&
      stylesheet.include?(".legal-layout.no-sidebar")
    check(
      checks,
      "trust_sidebar_removed",
      trust_sidebar_removed_ok,
      trust_sidebar_removed_ok ? "Trust route omits the legal sidebar/table-of-contents requested for deletion." : "Trust route still exposes the legal sidebar/table-of-contents or lacks the no-sidebar layout.",
      "has_no_sidebar_class" => trust_text.include?('class="legal-layout no-sidebar"'),
      "has_legal_sidebar" => trust_text.include?('class="legal-sidebar"'),
      "has_legal_toc" => trust_text.include?('class="legal-toc"')
    )

    privacy_text = read(route_index(build_dir, "/privacy/"))
    privacy_sidebar_removed_ok = privacy_text.include?('class="legal-layout no-sidebar"') &&
      !privacy_text.include?('class="legal-sidebar"') &&
      !privacy_text.include?('class="legal-toc"') &&
      !privacy_text.include?("On this page") &&
      stylesheet.include?(".legal-layout.no-sidebar")
    check(
      checks,
      "privacy_sidebar_removed",
      privacy_sidebar_removed_ok,
      privacy_sidebar_removed_ok ? "Privacy route omits the legal sidebar/table-of-contents requested for deletion." : "Privacy route still exposes the legal sidebar/table-of-contents or lacks the no-sidebar layout.",
      "has_no_sidebar_class" => privacy_text.include?('class="legal-layout no-sidebar"'),
      "has_legal_sidebar" => privacy_text.include?('class="legal-sidebar"'),
      "has_legal_toc" => privacy_text.include?('class="legal-toc"')
    )

    terms_text = read(route_index(build_dir, "/terms/"))
    terms_sidebar_removed_ok = terms_text.include?('class="legal-layout no-sidebar"') &&
      !terms_text.include?('class="legal-sidebar"') &&
      !terms_text.include?('class="legal-toc"') &&
      !terms_text.include?("On this page") &&
      stylesheet.include?(".legal-layout.no-sidebar")
    check(
      checks,
      "terms_sidebar_removed",
      terms_sidebar_removed_ok,
      terms_sidebar_removed_ok ? "Terms route omits the legal sidebar/table-of-contents requested for deletion." : "Terms route still exposes the legal sidebar/table-of-contents or lacks the no-sidebar layout.",
      "has_no_sidebar_class" => terms_text.include?('class="legal-layout no-sidebar"'),
      "has_legal_sidebar" => terms_text.include?('class="legal-sidebar"'),
      "has_legal_toc" => terms_text.include?('class="legal-toc"')
    )

    partners_text = read(route_index(build_dir, "/our-partners/"))
    deleted_partner_phrases = [
      "Mobile app and USSD access",
      "Member and group accounts",
      "Purpose-based savings",
      "Automated ledger reconciliation",
      "National community mobilisation",
      "Monthly repayment structures often do not match informal-sector cash flow",
      "Automated split between repayment and savings",
      "Reduced branch and collection-agent dependence",
      "Up to 365 repayment data points per borrower annually",
      "More accurate portfolio monitoring",
      "regulated country partner bank",
      "Daily repayment visibility",
      "Contribution history",
      "Group accountability",
      "The addressable Rwandan diaspora market is 300,000+ people",
      "Initial eligibility and requirement mapping",
      "Business-document and financial-record checklist",
      "Contribution, savings and repayment-history packaging",
      "Gap closure before formal bank review",
      "Cleaner applicant summary for credit teams",
      "Less rework between customer, adviser and bank",
      "Statements and contribution records",
      "Group savings collateral workflow",
      "Loan application preparation",
      "Savings mobilisation support",
      "Transaction reconciliation",
      "Collections and recovery",
      "Final loan approval",
      "Regulatory reporting",
      "Collateral documentation",
      "Account and product approval",
      "Green and productive-asset finance",
      "Net interest income",
      "Lower application rework",
      "Insurance-premium financing",
      "Purpose-controlled loan disbursement",
    ]
    deleted_partner_phrase_hits = deleted_partner_phrases.select { |phrase| partners_text.include?(phrase) }
    partner_specific_content_removed_ok = deleted_partner_phrase_hits.empty? &&
      partners_text.include?("Prospective opportunities for licensed providers") &&
      partners_text.include?(CGI.escapeHTML(product_capabilities.detail("partner_engine_intro"))) &&
      partners_text.include?(CGI.escapeHTML(product_capabilities.detail("partner_collect_heading"))) &&
      partners_text.include?("What each side brings") &&
      partners_text.include?("partner-market-section") &&
      partners_text.include?("partner-operating-section") &&
      !partners_text.include?("content-grid content-grid-our-partners")
    check(
      checks,
      "partners_specific_content_removed",
      partner_specific_content_removed_ok,
      partner_specific_content_removed_ok ? "Partners sections are restored and the copied phrases are absent." : "Partners sections are missing or still render copied phrases marked for deletion.",
      "hits" => deleted_partner_phrase_hits
    )

    cta_hierarchy_failures = PublicCapabilityContract.action_failures(product_capabilities, "/our-partners/", partners_text)
    cta_hierarchy_ok = cta_hierarchy_failures.empty? &&
      !partners_text.include?("Talk to our team") &&
      !partners_text.include?("Get Support") &&
      !partners_text.include?("Talk to us about starting a group") &&
      !partners_text.include?(">Create Group<")
    footer_trust_ok = root_html.include?("<strong>Collect by IKANISA</strong>") &&
      root_html.include?("IKANISA Ltd.") &&
      root_html.include?("Support:") &&
      root_html.include?("info@ikanisa.com") &&
      root_html.match?(/<a class="whatsapp-contact" href="https:\/\/wa\.me\/250795588248\?text=[^"]+">/) &&
      root_html.include?('<span class="sr-only">WhatsApp</span>') &&
      !root_html.include?("whatsapp-mark") &&
      !root_html.include?("· WhatsApp") &&
      !root_html.include?("No financial institution is presented on this website as a live Collect partner") &&
      root_html.include?("©")
    check(
      checks,
      "cta_and_footer_trust_hierarchy",
      cta_hierarchy_ok && footer_trust_ok,
      cta_hierarchy_ok && footer_trust_ok ? "Capability-specific CTA hierarchy and footer trust signals are complete." : "CTA hierarchy or footer trust signals are incomplete.",
      "cta_hierarchy_ok" => cta_hierarchy_ok,
      "capability_action_failures" => cta_hierarchy_failures,
      "footer_trust_ok" => footer_trust_ok
    )

    cta_failures = route_action_failures(product_capabilities, content_pages)
    check(
      checks,
      "consistent_ctas_without_disclaimer_labels",
      cta_failures.empty?,
      cta_failures.empty? ? "All public routes expose the canonical supported app/group or planned/provider inquiry actions and email support." : "A public route has a missing, unsupported or incorrect capability action.",
      "failures" => cta_failures
    )

    partner_status_disclaimer_absent = !partners_text.include?("Current public status") &&
      !partners_text.include?("No institution is presented here as a live Collect partner yet.") &&
      !partners_text.include?("No financial institution is presented on this website as a live Collect partner yet.") &&
      !partners_text.include?("Partner names, regulators, and licence references will be published only after") &&
      !partners_text.include?("It is not presented here as a bank, deposit taker, lender or insurer") &&
      !root_html.include?("No financial institution is presented on this website as a live Collect partner until")
    public_evidence_disclaimer_absent = [root_html, partners_text].all? do |html|
      !html.include?("Evidence boundary") &&
        !html.include?("Public evidence and market context") &&
        !html.include?("Collect-specific traction figures and named institutional partnerships are not yet published")
    end
    fee_disclaimer_absent = !root_html.include?("Fee clarity") &&
      !root_html.include?("How Collect makes money") &&
      !root_html.include?("When Collect describes microsavings as zero-fee")
    app_media_error = nil
    begin
      verified_app_media = PublicAppMedia.new(Dir.pwd).screens
      authentic_app_media_ok = verified_app_media.length >= 7 && !stylesheet.include?(".phone-screen") &&
        Dir.glob(File.join(build_dir, "**/*.html")).none? { |path| read(path).include?('class="phone-shell"') }
    rescue StandardError => error
      app_media_error = error.message
      authentic_app_media_ok = false
    end
    check(checks, "partner_status_disclaimer_absent", partner_status_disclaimer_absent, partner_status_disclaimer_absent ? "The internal partner-status disclaimer is absent from public routes." : "The removed partner-status disclaimer is still present.")
    check(checks, "public_evidence_disclaimer_absent", public_evidence_disclaimer_absent, public_evidence_disclaimer_absent ? "The redundant public-evidence disclaimer block is absent." : "The removed public-evidence disclaimer block is still present.")
    check(checks, "fee_disclaimer_absent", fee_disclaimer_absent, fee_disclaimer_absent ? "The redundant fee disclaimer block is absent." : "The removed fee disclaimer block is still present.")
    check(checks, "authentic_app_media", authentic_app_media_ok, authentic_app_media_ok ? "App media matches reviewed captures and current runtime source; invented phone UI is absent." : "App screenshot provenance failed: #{app_media_error}")
  end

  def check_claims(checks, build_dir, root_html, product_capabilities)
    credit_readiness_ok = root_html.downcase.include?("credit-readiness") &&
      root_html.include?("Payments work. Financial progress still does not.") &&
      root_html.include?("Credit-readiness gap") &&
      root_html.downcase.include?("bank-ready loan files")
    check(
      checks,
      "credit_readiness_explainer",
      credit_readiness_ok,
      credit_readiness_ok ? "Credit-readiness and provider boundaries are explained on the home page." : "Missing credit-readiness or provider-boundary explanation."
    )

    source_backed_market_context_ok = root_html.include?("96%") &&
      root_html.include?("85%") &&
      root_html.include?("72%") &&
      root_html.include?("24%")
    check(
      checks,
      "source_backed_market_context",
      source_backed_market_context_ok,
      source_backed_market_context_ok ? "Home market figures are present." : "Home market figures are missing."
    )

    craas_text = read(route_index(build_dir, "/craas/"))
    craas_bank_benefit_cleanup_ok = !craas_text.include?("Cleaner application pipeline") &&
      craas_text.include?("Less administrative rework") &&
      craas_text.include?("More consistent files")
    check(
      checks,
      "craas_bank_benefit_cleanup",
      craas_bank_benefit_cleanup_ok,
      craas_bank_benefit_cleanup_ok ? "CRaaS bank-benefit list no longer includes the deleted first bullet." : "CRaaS bank-benefit list still includes the deleted bullet or lost adjacent benefits."
    )

    legal_route_prefixes = %w[
      privacy terms account-deletion data-deletion trust security subprocessors privacy-request cookies
    ]
    public_html_paths = Dir.glob(File.join(build_dir, "**", "*.html")).select { |path| File.file?(path) }.reject do |path|
      relative = path.delete_prefix(build_dir + "/")
      legal_route_prefixes.any? { |prefix| relative == "#{prefix}/index.html" }
    end
    banned_public_claim_patterns = {
      "email_form_or_unapproved_contact" => /type=["']email["']|name=["']email["']|\b(?:privacy|support|complaints|partnerships)@ikanisa\.com\b/i,
      "projection_or_scenario" => /projection|scenario|estimate/i,
      "unsupported_partner_names" => /Malta|three Rwanda banks/i,
      "deck_only_market_figures" => /RWF 50|150B|300K|100K|35B|3-5x|US\$0\.5B|864M|19,807B|351\.3B|169,570|7,169,324|67\.6B|26\.2%|25,000|70,000|~60%|~0%/i,
    }
    public_claim_failures = []
    public_html_paths.each do |path|
      html = read(path)
      PublicCapabilityContract.claim_failures(product_capabilities, html).each do |failure|
        public_claim_failures << { "file" => path.delete_prefix(build_dir + "/") }.merge(failure)
      end
      banned_public_claim_patterns.each do |id, pattern|
        next unless html.match?(pattern)

        public_claim_failures << { "file" => path.delete_prefix(build_dir + "/"), "pattern" => id }
      end
    end
    check(
      checks,
      "public_claim_guard",
      public_claim_failures.empty?,
      public_claim_failures.empty? ? "Generated public HTML preserves exact qualified capability limitations and rejects unsupported financial/platform claims, unapproved contact/forms and deck-only projections." : "Generated public HTML contains banned public-claim content.",
      "failures" => public_claim_failures
    )
  end
end
