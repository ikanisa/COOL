# frozen_string_literal: true

module CollectPublicLegalRendering
  module Values
    REFERENCE_KEYS = %w[subprocessor_link link cookie_policy_link privacy_request].freeze

    def legal_label(key)
      key.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
    end

    def legal_value_html(value)
      case value
      when String, Numeric
        text = value.to_s.strip
        return "" if text.empty?

        %(<p>#{esc(text)}</p>)
      when Array
        legal_array_html(value)
      when Hash
        legal_hash_html(value)
      else
        ""
      end
    end

    def legal_array_html(items)
      items = Array(items).compact
      return "" if items.empty?

      if items.all? { |item| item.is_a?(String) || item.is_a?(Numeric) }
        %(<ul class="bullet-list">#{items.map { |item| %(<li>#{esc(item)}</li>) }.join}</ul>)
      else
        %(<div class="legal-card-grid">#{items.map { |item| legal_hash_card_html(item) }.join}</div>)
      end
    end

    def legal_hash_card_html(item)
      return %(<article class="legal-card">#{legal_value_html(item)}</article>) unless item.is_a?(Hash)

      title = item["title"] || item["heading"] || item["label"] || item["name"]
      body_parts = item.reject { |key, _| %w[id title heading label name type required options].include?(key.to_s) }
      <<~HTML
        <article class="legal-card">
          #{title ? %(<h3>#{esc(title)}</h3>) : ""}
          #{body_parts.map { |key, value| legal_named_value_html(key, value) }.join}
        </article>
      HTML
    end

    def legal_hash_html(hash)
      heading = hash["heading"] || hash["title"]
      body = hash.reject { |key, _| %w[heading title].include?(key.to_s) || legal_internal_key?(key) }
      seen_contacts = {}
      body = body.reject do |key, value|
        next false unless legal_contact_key?(key) && value.is_a?(String)

        duplicate = seen_contacts[value.strip]
        seen_contacts[value.strip] = true
        duplicate
      end
      <<~HTML
        #{heading ? %(<h3>#{esc(heading)}</h3>) : ""}
        #{body.map { |key, value| legal_named_value_html(key, value) }.join}
      HTML
    end

    def legal_details_html(details)
      seen = {}
      rows = details.reject { |key, value| legal_internal_key?(key) || %w[heading title].include?(key.to_s) || value.to_s.strip.empty? }.map do |key, value|
        label = legal_contact_key?(key) ? "Email" : key.to_s == "privacy_request" ? "Privacy requests" : legal_label(key)
        dedupe_key = [label, value.to_s.strip]
        next if seen[dedupe_key]

        seen[dedupe_key] = true
        href = REFERENCE_KEYS.include?(key.to_s) ? normalized_legal_href(value) : nil
        content = if legal_contact_key?(key)
          legal_email_html(value)
        elsif href
          legal_inline_anchor_html(key, href)
        else
          esc(value)
        end
        %(<dt>#{esc(label)}</dt><dd>#{content}</dd>)
      end.compact
      return "" if rows.empty?

      %(<dl class="legal-details">#{rows.join}</dl>)
    end

    def legal_contact_key?(key)
      %w[email privacy_email support_email general_support privacy complaints partnerships].include?(key.to_s)
    end

    def legal_email_html(value)
      %(<a class="legal-inline-link" href="mailto:#{esc(value)}">#{esc(value)}</a>)
    end

    def legal_named_value_html(key, value)
      return "" if legal_internal_key?(key) || value.nil? || value.respond_to?(:empty?) && value.empty?
      return %(<p><strong>Email:</strong> #{legal_email_html(value)}</p>) if legal_contact_key?(key) && !value.is_a?(Hash) && !value.is_a?(Array)

      case key.to_s
      when "heading"
        ""
      when "body"
        Array(value).map { |item| %(<p>#{esc(item)}</p>) }.join
      when "intro", "closing", "risk_statement", "trust_statement", "important_notice",
           "service_target", "copy", "clarification", "zero_fee_clarification",
           "non_exclusion", "priority_rule"
        %(<p>#{esc(value)}</p>)
      when "details"
        legal_details_html(value)
      when "delete_without_app"
        heading = value["heading"] || value["title"]
        body = legal_hash_html(value)
        original = %(<h3>#{esc(heading)}</h3>)
        raise "Expected one outside-app deletion heading" unless heading && body.scan(original).length == 1

        linked = %(<h3><a class="legal-inline-link" href="#{account_deletion_portal_url}">#{esc(heading)}</a></h3>)
        %(<div>#{body.sub(original, linked)}</div>)
      when "contact"
        heading = value["heading"] || value["title"]
        %(<div>#{heading ? %(<h3>#{esc(heading)}</h3>) : ""}#{legal_details_html(value)}</div>)
      when "bullets", "steps", "uses", "not_final_decision_for", "additional_terms_may_include",
           "availability_may_be_limited_by", "collect_does_not_guarantee",
           "member_obligations", "group_leader_obligations", "transaction_may_remain_subject_to",
           "collect_may_support", "credit_readiness_is_not", "providers_may_include",
           "pre_acceptance_information", "partner_lender_controls", "insurer_controls",
           "where_available", "fees_may_include", "acceptable_use", "may_apply_to",
           "request_channels", "before_deletion_you_may_need_to", "deletion_does_not_cancel",
           "availability_may_be_affected_by", "not_constitute",
           "to_extent_permitted_collect_not_responsible_for", "updates_may_reflect",
           "trust_commitments"
        legal_array_html(value)
      when "subsections"
        Array(value).map { |section| legal_section_html(section) }.join
      when "links"
        legal_links_html(value)
      when *REFERENCE_KEYS
        legal_inline_link_html(key, value)
      when "support_information"
        %(<h3>#{esc(value.fetch("heading"))}</h3><p>#{esc(value.fetch("copy"))}</p>#{legal_form_fields_html(value.fetch("fields"))})
      when "path"
        %(<p><span class="legal-path">#{esc(value)}</span></p>)
      when "fields"
        legal_form_fields_html(value)
      else
        if value.is_a?(Array)
          %(<h3>#{esc(legal_label(key))}</h3>#{legal_array_html(value)})
        elsif value.is_a?(Hash)
          %(<div>#{value["heading"] || value["title"] ? "" : %(<h3>#{esc(legal_label(key))}</h3>)}#{legal_hash_html(value)}</div>)
        else
          %(<p><strong>#{esc(legal_label(key))}:</strong> #{esc(value)}</p>)
        end
      end
    end

    def normalized_legal_href(value)
      href = value.to_s.strip
      return href if href == mailto_url("Collect privacy request")
      return nil unless href.start_with?("/") && !href.start_with?("//")

      path, fragment = href.split("#", 2)
      path = "#{path}/" unless path.end_with?("/")
      fragment ? "#{path}##{fragment}" : path
    end

    def legal_inline_link_html(key, value)
      href = normalized_legal_href(value)
      return %(<p><strong>#{esc(legal_label(key))}:</strong> #{esc(value)}</p>) unless href

      %(<p>#{legal_inline_anchor_html(key, href)}</p>)
    end

    def legal_inline_anchor_html(key, href)
      %(<a class="legal-inline-link" href="#{esc(href)}">#{esc(legal_inline_link_label(key, href))}</a>)
    end

    def legal_inline_link_label(key, href)
      case key.to_s
      when "subprocessor_link" then "Read about service providers and data sharing"
      when "privacy_request" then "Email #{support_email} about a privacy request"
      when "cookie_policy_link" then "Read the cookie and website technology notice"
      when "link"
        if href.start_with?("/account-deletion/")
          "Open the account-deletion page"
        elsif href == "/privacy/#cookies"
          "Read about cookies and website analytics"
        else
          "Open the referenced page"
        end
      else
        "Open the referenced page"
      end
    end

    def legal_internal_key?(key)
      %w[id slug seo hero legal_review_note must_be_finalised_for].include?(key.to_s)
    end

    def legal_links_html(links)
      items = links.map do |label, href|
        href_display = normalized_legal_href(href)
        content = href_display ? %(<a href="#{esc(href_display)}">#{esc(legal_label(label))}</a>) : esc(legal_label(label))
        %(<li>#{content}</li>)
      end
      %(<ul class="bullet-list">#{items.join}</ul>)
    end

    def legal_form_fields_html(fields)
      cards = Array(fields).map do |field|
        label = field["label"] || legal_label(field["name"])
        required = case field["required"]
        when true then "Required"
        when false then "Optional"
        end
        options = Array(field["options"])
        <<~HTML
          <article class="legal-card">
            <h3>#{esc(label)}</h3>
            #{required ? %(<p>#{esc(required)} field.</p>) : ""}
            #{options.empty? ? "" : legal_array_html(options)}
          </article>
        HTML
      end.join
      %(<div class="legal-card-grid">#{cards}</div>)
    end
  end
end
