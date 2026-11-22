# frozen_string_literal: true

require "yaml"

module CollectPublicLegalRendering
  module Content
    LEGAL_CONTENT_DIR = File.expand_path("../../content/legal", __dir__)
    LEGAL_BUNDLE = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_legal_pages_bundle.yaml"))
    LEGAL_PRIVACY = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_privacy_policy.yaml")).fetch("page")
    LEGAL_TERMS = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_terms_of_use.yaml")).fetch("page")
    LEGAL_DELETE_ACCOUNT = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_delete_account.yaml")).fetch("page")

    def legal_content_for(page)
      case page[:legal_key]
      when :privacy
        LEGAL_PRIVACY.merge("sections" => Array(LEGAL_PRIVACY["sections"]).map { |section| current_deletion_section(section) })
      when :terms
        LEGAL_TERMS.merge("sections" => Array(LEGAL_TERMS["sections"]).map { |section| current_deletion_terms_section(section) })
      when :account_deletion
        LEGAL_DELETE_ACCOUNT.merge(
          "delete_in_app" => current_deletion_app_content(LEGAL_DELETE_ACCOUNT["delete_in_app"]),
          "delete_without_app" => current_deletion_support_content(LEGAL_DELETE_ACCOUNT["delete_without_app"])
        )
      when :data_deletion
        {
          "title" => "Data Deletion",
          "important_notice" => LEGAL_DELETE_ACCOUNT["important_notice"],
          "sections" => [
            privacy_section("account-and-data-deletion"),
            keyed_section("What happens next", LEGAL_DELETE_ACCOUNT["what_happens_next"]),
            keyed_section("Data we may retain", LEGAL_DELETE_ACCOUNT["data_we_may_retain"]).merge("id" => "retained-data-summary"),
            keyed_section("Products provided by partners", LEGAL_DELETE_ACCOUNT["partner_products"]),
            keyed_section("Need help?", LEGAL_DELETE_ACCOUNT["contact"])
          ].compact
        }
      when :trust
        {
          "title" => "Trust and Security",
          "sections" => [
            {
              "heading" => "How Collect protects customer information",
              "body" => [
                "Collect limits access to customer data by role and reason, protects data in transit, keeps operational audit trails, and minimises raw sensitive records where possible."
              ],
              "trust_commitments" => [
                "Personal data is not sold.",
                "Customer funds are not held on Collect's own balance sheet.",
                "Banks and insurers make their own regulated decisions.",
                "Customer deletion and correction routes are available through app and support channels."
              ]
            },
            {
              "heading" => "What Collect will not do",
              "body" => [
                "Collect does not make final loan, pricing, policy or claim decisions for regulated providers, and it does not expose private credit-readiness documents to group members."
              ],
              "trust_commitments" => [
                "No public training of private customer financial documents.",
                "No sale of personal data.",
                "No public promise of automatic credit, insurance or payout approval.",
                "No unrestricted access to sensitive support records."
              ]
            },
            {
              "heading" => "Partner and regulated-product boundary",
              "body" => [
                "Collect supports records, preparation, communication and customer-requested workflows. Licensed banks, insurers or approved providers remain responsible for their own KYC, AML/CFT, eligibility, pricing, approval, disbursement, claim and regulatory obligations."
              ],
              "trust_commitments" => [
                "Provider review remains separate from Collect public marketing copy.",
                "Funds are handled through regulated financial-service partners where approved arrangements apply.",
                "Partner handoff requires an appropriate legal basis and customer workflow."
              ]
            },
            {
              "heading" => "Customer rights and deletion support",
              "body" => [
                "Customers can request access, correction, account deletion or data deletion. Some ledger, security, dispute, payment, tax, audit, legal or regulatory records may need limited retention."
              ],
              "trust_commitments" => [
                "Use the in-app account deletion request where available.",
                "Contact WhatsApp support at +250 795 588 248.",
                "Email info@ikanisa.com for privacy or deletion questions.",
                "Support can confirm request status and explain retained record categories."
              ]
            }
          ].compact
        }
      end
    end

    def privacy_section(id)
      current_deletion_section(Array(LEGAL_PRIVACY["sections"]).find { |section| section["id"] == id })
    end

    def current_deletion_app_content(content)
      canonical = LEGAL_DELETE_ACCOUNT.fetch("delete_in_app")
      content.merge(
        "path" => canonical.fetch("path"),
        "steps" => canonical.fetch("steps")
      )
    end

    def current_deletion_support_content(content)
      canonical = LEGAL_DELETE_ACCOUNT.fetch("delete_without_app")
      content.merge(
        "copy" => canonical.fetch("copy"),
        "email" => canonical.fetch("email")
      )
    end

    def current_deletion_terms_section(section)
      return section unless section.is_a?(Hash) && section["id"] == "closing-or-deleting"

      section.merge("request_channels" => Array(section["request_channels"]).map do |channel|
        channel.start_with?("In the app under ") ? "In the app under #{LEGAL_DELETE_ACCOUNT.fetch("delete_in_app").fetch("path")}" : channel
      end)
    end

    def current_deletion_section(section)
      return section unless section.is_a?(Hash) && section["id"] == "account-and-data-deletion"

      section.merge("subsections" => Array(section["subsections"]).map do |subsection|
        case subsection["heading"]
        when "Delete your account in the Collect app"
          current_deletion_app_content(subsection)
        when "Request deletion without the app"
          support = current_deletion_support_content(subsection)
          support.merge(
            "id" => subsection.fetch("id"),
            "body" => support["copy"]
          ).reject { |key, _| key == "copy" }
        else
          subsection
        end
      end)
    end

    def keyed_section(heading, content)
      return nil unless content.is_a?(Hash)

      content.merge("heading" => heading)
    end
  end
end
