# frozen_string_literal: true

module CollectPublicSite
  def numbered_journey_html(steps)
    steps.each_with_index.map do |(title, body), index|
      %(<article><span>#{format("%02d", index + 1)}</span><strong>#{esc(title)}</strong><p>#{esc(body)}</p></article>)
    end.join
  end

  def optional_list_html(items)
    items = Array(items)
    return "" if items.empty?

    %(<ul>#{list_items_html(items)}</ul>)
  end

  def home_credit_readiness_html
    <<~HTML
      <section class="market-context" aria-labelledby="market-context-heading">
        <div>
          <p class="section-kicker">Finance built around real income</p>
          <h2 id="market-context-heading">People earn daily. Finance still works monthly.</h2>
          <p>Around 90% of employment in Rwanda is informal. Many people earn small, irregular amounts each day, while conventional savings, credit and insurance products are structured around monthly salaries, larger deposits and lump-sum repayments.</p>
        </div>
        <div class="market-grid" aria-label="Source-backed Rwanda financial inclusion context">
          <article><strong>96%</strong><span>Rwandan adults financially included</span></article>
          <article><strong>85%</strong><span>Adults saved formally or informally</span></article>
          <article><strong>72%</strong><span>Adults using informal mechanisms</span></article>
          <article><strong>24%</strong><span>Adults using formal borrowing</span></article>
        </div>
      </section>
    HTML
  end

  def original_home_sections_html
    <<~HTML
      <section class="original-story home-journey" aria-labelledby="daily-rhythm-heading">
        <div class="story-copy">
          <h2 id="daily-rhythm-heading">#{esc(PRODUCT_CAPABILITIES.detail("home_journey_heading"))}</h2>
        </div>
        <div class="journey-rail" aria-label="Collect contribution journey">
          #{numbered_journey_html(PRODUCT_CAPABILITIES.detail("home_journey"))}
        </div>
      </section>

      <section class="original-story" aria-labelledby="ibimina-heading">
        <div class="story-copy">
          <h2 id="ibimina-heading">Everything Collect brings together</h2>
        </div>
        <div class="story-grid four home-product-grid">
          #{PRODUCT_CAPABILITIES.detail("home_products").map { |title, body, href, label| %(<article><strong>#{esc(title)}</strong><span>#{esc(body)}</span><a href="#{esc(href)}">#{esc(label)}</a></article>) }.join}
        </div>
      </section>

      <section class="original-story" aria-labelledby="rwanda-community-heading">
        <div class="story-copy">
          <h2 id="rwanda-community-heading">Built for people who earn, save, and borrow differently</h2>
        </div>
        <div class="story-grid four">
          <article><strong>Ibimina</strong><span>Rotating and accumulating groups that need readable activity records.</span></article>
          <article><strong>Daily earners</strong><span>People saving in small amounts around daily or irregular income.</span></article>
          <article><strong>MSMEs</strong><span>#{esc(PRODUCT_CAPABILITIES.detail("msme_summary"))}</span></article>
        </div>
      </section>

      <section class="original-story" aria-labelledby="credit-boundary-heading">
        <div class="story-copy">
          <h2 id="credit-boundary-heading">Payments work. Financial progress still does not.</h2>
        </div>
        <div class="story-grid problem-grid">
          <article><strong>Daily-income mismatch</strong><span>90% of employment is informal, yet finance is designed around monthly salaries and lump-sum payments.</span></article>
          <article><strong>Invisible group savings</strong><span>52% of adults save through ibimina, but many records remain manual and cannot support formal credit.</span></article>
          <article><strong>Credit-readiness gap</strong><span>Rwanda has extensive payment agents, but no scalable last-mile service helping MSMEs prepare complete, bank-ready loan files.</span></article>
          <article><strong>Microinsurance gap</strong><span>Premiums and claims processes rarely match small, irregular daily incomes.</span></article>
        </div>
      </section>
    HTML
  end

  def group_savings_page_html
    how_steps = PRODUCT_CAPABILITIES.detail("group_how_steps")
    features = PRODUCT_CAPABILITIES.detail("group_features")
    use_cases = [
      "Business working-capital readiness",
      "Insurance and compliance savings",
      "School-fee and family goals",
      "Agricultural inputs and equipment",
      "Property and construction",
      "Moto-taxi insurance and licensing",
      "Green mobility and productive assets",
      "Emergency and resilience funds"
    ]

    <<~HTML
      <section class="group-problem-section" aria-labelledby="group-problems-heading">
        <div class="story-copy">
          <h2 id="group-problems-heading">Trusted savings should not remain invisible.</h2>
          <p>Many groups still depend on cash, notebooks, spreadsheets, WhatsApp messages or one person's mobile-money account. This makes reconciliation difficult, weakens transparency and prevents years of savings discipline from becoming a recognised financial record.</p>
        </div>
        <div class="problem-list compact" aria-label="What groups struggle with today">
          <article>Manual contribution tracking</article>
          <article>Missing or disputed records</article>
          <article>Cash-handling and fraud risk</article>
          <article>No independent member statements</article>
          <article>Capital repeatedly distributed rather than accumulated</article>
          <article>Limited visibility for banks and other partners</article>
        </div>
      </section>

      <section class="group-workflow-section" aria-labelledby="group-workflow-heading">
        <div class="story-copy">
          <h2 id="group-workflow-heading">How Collect works</h2>
        </div>
        <div class="journey-rail group-journey" aria-label="Group savings workflow">
          #{numbered_journey_html(how_steps)}
        </div>
      </section>

      <section class="group-feature-section" aria-labelledby="group-features-heading">
        <div class="story-copy">
          <h2 id="group-features-heading">Features for groups that save together</h2>
        </div>
        <div class="story-grid four group-feature-grid">
          #{features.map { |(title, body)| %(<article><strong>#{esc(title)}</strong><span>#{esc(body)}</span></article>) }.join}
        </div>
      </section>

      <section class="group-accumulation-section" aria-labelledby="group-accumulation-heading">
        <div class="story-copy">
          <h2 id="group-accumulation-heading">From rotation to accumulation - keep the trust, grow the capital.</h2>
        </div>
        <div class="accumulation-panel">
          <p>#{esc(PRODUCT_CAPABILITIES.detail("accumulation_summary"))}</p>
          <strong>Each group chooses its rules.</strong>
          <span>Collect does not force groups to abandon their existing culture or governance.</span>
        </div>
      </section>

      <section class="group-use-section" aria-labelledby="group-use-heading">
        <div class="story-copy">
          <h2 id="group-use-heading">Do more with your group savings.</h2>
        </div>
        <div class="use-case-grid" aria-label="Group savings use cases">
          #{use_cases.map { |item| %(<article>#{esc(item)}</article>) }.join}
        </div>
      </section>
    HTML
  end

  def insurance_page_html
    how_steps = PRODUCT_CAPABILITIES.detail("insurance_how_steps")

    <<~HTML
      <section class="insurance-work-section" aria-labelledby="insurance-work-heading">
        <div class="story-copy">
          <h2 id="insurance-work-heading">Proposed journey, not an available service</h2>
        </div>
        <div class="insurance-step-grid" aria-label="Insurance product journey">
          #{how_steps.each_with_index.map { |body, index| %(<article><span>#{format("%02d", index + 1)}</span><p>#{esc(body)}</p></article>) }.join}
        </div>
      </section>

      <section class="insurance-finance-section" aria-labelledby="insurance-finance-heading">
        <div class="story-copy">
          <p class="section-kicker">Premium finance</p>
          <h2 id="insurance-finance-heading">Protection should not lapse because today's balance is short.</h2>
        </div>
        <div class="premium-finance-panel">
          <p>#{esc(PRODUCT_CAPABILITIES.detail("premium_finance"))}</p>
        </div>
      </section>
    HTML
  end

  def craas_page_html
    specialist_services = [
      "Accounting",
      "Business plan",
      "Tax advisory",
      "Notaries",
      "Legal services",
      "Insurers",
      "Collateral documents",
      "Property valuation"
    ]

    bank_receives = [
      "Business profile summary",
      "Loan request summary",
      "Product-specific checklist",
      "Indexed document folder",
      "Financial evidence summary",
      "Repayment and cash-flow notes",
      "KYC/KYB support file",
      "Identified gaps and next steps",
      "Readiness review",
      "Draft credit memo and working note"
    ]

    business_benefits = [
      "Clearer requirements",
      "Less confusion",
      "Fewer unnecessary visits",
      "Better file quality",
      "Greater confidence",
      "Faster handoff to a lender"
    ]

    bank_benefits = [
      "Less administrative rework",
      "More consistent files",
      "Faster pre-credit preparation",
      "Better productivity",
      "Improved applicant experience"
    ]

    <<~HTML
      <section class="craas-specialist-section" aria-labelledby="craas-specialist-heading">
        <div class="story-copy">
          <h2 id="craas-specialist-heading">#{esc(PRODUCT_CAPABILITIES.detail("craas_specialist_heading"))}</h2>
        </div>
        <div class="craas-service-grid" aria-label="Specialist support services">
          #{specialist_services.map { |item| %(<article><strong>#{esc(item)}</strong></article>) }.join}
        </div>
      </section>

      <section class="craas-bank-section" aria-labelledby="craas-bank-heading">
        <div class="story-copy">
          <h2 id="craas-bank-heading">#{esc(PRODUCT_CAPABILITIES.detail("craas_bank_heading"))}</h2>
        </div>
        <div class="craas-list-panel">
          <ul>
            #{list_items_html(bank_receives)}
          </ul>
        </div>
      </section>

      <section class="craas-benefits-section" aria-labelledby="craas-benefits-heading">
        <div class="story-copy">
          <h2 id="craas-benefits-heading">#{esc(PRODUCT_CAPABILITIES.detail("craas_benefits_heading"))}</h2>
        </div>
        <div class="craas-benefit-grid">
          <article>
            <h3>For businesses</h3>
            <ul>
              #{list_items_html(business_benefits)}
            </ul>
          </article>
          <article>
            <h3>For banks</h3>
            <ul>
              #{list_items_html(bank_benefits)}
            </ul>
          </article>
        </div>
      </section>
    HTML
  end

  def partner_page_html
    opportunity_metrics = [
      ["RWF 288B+", "Annual ibimina savings flow"],
      ["4.8M", "Informal and group savers"],
      ["94,000", "Savings groups nationwide"],
      ["90.4%", "Employment operating informally"]
    ]
    deposit_mobilisation = [
      "Daily and periodic microsavings"
    ]

    daily_income_lending = [
      "Daily or periodic micro-repayments",
      "Earlier visibility of repayment stress"
    ]

    collect_provides = PRODUCT_CAPABILITIES.detail("partner_collect_provides")

    bank_provides = [
      "Regulated savings accounts and account operations",
      "KYC, KYB and AML/CFT controls",
      "Credit assessment and pricing",
      "Loan disbursement"
    ]

    bank_value = [
      "Growth in low-cost deposits",
      "New retail and MSME customers",
      "Increased loan origination",
      "Reduced pre-credit administration"
    ]

    <<~HTML
      <section class="partner-opportunity-section" aria-labelledby="partner-opportunity-heading">
        <div class="story-copy">
          <h2 id="partner-opportunity-heading">A large savings and credit market already exists, mostly outside formal banking.</h2>
        </div>
        <div class="partner-metric-grid" aria-label="Banking opportunity metrics">
          #{opportunity_metrics.map { |value, label| %(<article><strong#{value.include?("RWF") ? ' class="currency-value"' : ""}>#{esc(value)}</strong><span>#{esc(label)}</span></article>) }.join}
        </div>
      </section>

      <section class="partner-market-section" aria-labelledby="partner-growth-heading">
        <div class="story-copy">
          <h2 id="partner-growth-heading">Prospective opportunities for licensed providers</h2>
          <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_engine_intro"))}</p>
        </div>
        <div class="partner-engine-grid" aria-label="Growth engines for partner banks">
          <article>
            <strong>Low-cost deposit mobilisation</strong>
            <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_deposits"))}</p>
            #{optional_list_html(deposit_mobilisation)}
          </article>
          <article>
            <strong>Daily-income lending and repayment</strong>
            <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_lending"))}</p>
            #{optional_list_html(daily_income_lending)}
          </article>
          <article>
            <strong>Rwanda group savings records</strong>
            <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_records"))}</p>
          </article>
          <article>
            <strong>Stronger MSME credit origination</strong>
            <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_credit_readiness"))}</p>
          </article>
        </div>
      </section>

      <section class="partner-operating-section" aria-labelledby="partner-operating-heading">
        <div class="story-copy">
          <h2 id="partner-operating-heading">What each side brings</h2>
        </div>
        <div class="partner-operating-grid">
          <article>
            <h3>#{esc(PRODUCT_CAPABILITIES.detail("partner_collect_heading"))}</h3>
            #{optional_list_html(collect_provides)}
          </article>
          <article>
            <h3>#{esc(PRODUCT_CAPABILITIES.detail("partner_bank_heading"))}</h3>
            #{optional_list_html(bank_provides)}
          </article>
          <article>
            <h3>#{esc(PRODUCT_CAPABILITIES.detail("partner_value_heading"))}</h3>
            <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_value_intro"))}</p>
            #{optional_list_html(bank_value)}
          </article>
        </div>
      </section>
    HTML
  end
end
