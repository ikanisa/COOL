part of 'public_content.dart';

const _publicMarketingPages = <CollectPublicPageData>[
  CollectPublicPageData(
    path: '/group-savings',
    navLabel: 'Group Savings',
    title: 'Your group already has trust. Collect adds structure.',
    intro:
        "Every contribution is recorded, every member has a statement, and your group's savings discipline becomes something a bank can understand.",
    imageAsset: 'assets/brand/collect_runtime/media/group-momentum.png',
    metricA: 'Setup',
    metricALabel: 'Group rules',
    metricB: 'Statements',
    metricBLabel: 'Member visibility',
    sections: [
      CollectPublicSectionData(
        title: 'Trusted savings should not remain invisible.',
        body:
            "Many groups still depend on cash, notebooks, spreadsheets, WhatsApp messages or one person's mobile-money account. This makes reconciliation difficult, weakens transparency and prevents years of savings discipline from becoming a recognised financial record.",
        bullets: [
          'Manual contribution tracking',
          'Missing or disputed records',
          'Cash-handling and fraud risk',
          'No independent member statements',
          'Capital repeatedly distributed rather than accumulated',
          'Limited visibility for banks and other partners',
        ],
      ),
      CollectPublicSectionData(
        title: 'How Collect works',
        body:
            'Create the group, invite members, contribute with proof, build financial history, and connect to partners where eligible.',
        bullets: [
          '01 - Create the group: define its purpose, leadership, rules and contribution schedule',
          '02 - Invite members: onboard members through the app or supported assisted channels',
          '03 - Contribute and get proof: members save through the app, mobile money, or USSD and receive confirmation',
          '04 - Build financial history: contribution consistency becomes a verified record',
          '05 - Connect to partners: eligible groups may access partner-led credit, insurance or purpose-based finance',
        ],
      ),
      CollectPublicSectionData(
        title: 'Features for groups that save together',
        body:
            'Collect gives leaders and members a cleaner operating record without replacing the trust and rules the group already has.',
        bullets: [
          'Transparent group ledger and member statements',
          'Flexible contribution schedules and group roles',
          'Purpose-based goals for insurance, school fees, assets, property, agriculture and mobility',
          "Funds are held by regulated financial-service partners, not on Collect's own balance sheet",
          'Credit-readiness record from contribution discipline',
        ],
      ),
      CollectPublicSectionData(
        title:
            'From rotation to accumulation - keep the trust, grow the capital.',
        body:
            'Traditional rotational groups help members access a periodic lump sum, but the group capital is repeatedly distributed and depleted. Collect allows groups to add an accumulating model in which savings remain visible and can support shared goals, collateral arrangements and longer-term investment.',
        bullets: [
          'Each group chooses its rules',
          'Collect does not force groups to abandon existing culture or governance',
          'Savings remain visible for members and leaders',
        ],
      ),
      CollectPublicSectionData(
        title: 'Do more with your group savings.',
        body: 'Give every contribution a clear purpose and a trusted record.',
        bullets: [
          'Business working-capital readiness',
          'Insurance and compliance savings',
          'School-fee and family goals',
          'Agricultural inputs and equipment',
          'Property and construction',
          'Moto-taxi insurance and licensing',
          'Green mobility and productive assets',
          'Emergency and resilience funds',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/diaspora',
    navLabel: 'Diaspora',
    title: 'Group savings that strengthen access to bank credit.',
    intro:
        'Diaspora groups save through a bank in the host country. The bank holds the savings and can lend to members against the pooled group savings as collateral.',
    imageAsset: 'assets/brand/collect_runtime/media/qr-share.png',
    metricA: 'Group records',
    metricALabel: 'Member contributions',
    metricB: 'Preparation',
    metricBLabel: 'Rwanda discussions',
    sections: [
      CollectPublicSectionData(
        title: 'Diaspora savers face their own barriers to credit.',
        body:
            'Diaspora borrowers can be strong savers while still facing host-country lending requirements that make individual applications harder.',
        bullets: [
          'Mobility and recovery risk',
          'Thin or no host-country credit history',
          'Informal or unstable employment',
          'Insufficient acceptable security',
        ],
      ),
      CollectPublicSectionData(
        title: 'How the diaspora use Collect',
        body:
            'Members create a savings group, save regularly, build the group pool, agree collateral rules, apply for credit, and invest at home.',
        bullets: [
          'Create a savings group with purpose, contribution amount, leadership and rules',
          'Save regularly through Collect into the host-country partner bank',
          'Build the group pool while Collect maintains the ledger',
          'Agree what share may be pledged or ring-fenced',
          'Apply for credit through the host-country partner bank',
          'Use the loan to invest in property or a business in Rwanda',
        ],
      ),
      CollectPublicSectionData(
        title: 'Without Collect',
        body:
            'The individual borrower is assessed without group support, controlled collateral, or enough transaction evidence.',
        bullets: [
          'Informal savings circle',
          'Limited transaction evidence',
          'Savings held outside the lending bank',
          'No controlled collateral arrangement',
        ],
      ),
      CollectPublicSectionData(
        title: 'With Collect and the partner bank',
        body:
            'The group keeps verified contribution history, bank-held savings, agreed collateral structure, and clearer support for investing back home.',
        bullets: [
          'Verified contribution history',
          'Savings held by the potential lender',
          'Group rules and accountability',
          'Structured support for Rwanda investment',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/insurance',
    navLabel: 'Insurance',
    title: 'Protection that fits how people earn.',
    intro:
        'Collect works with licensed insurers on simple protection products, flexible micro-payments, and transparent claims - built for informal and variable-income earners.',
    imageAsset:
        'assets/brand/collect_runtime/media/mobile-money-ussd-signal.png',
    metricA: 'Records',
    metricALabel: 'Customer support',
    metricB: 'Providers',
    metricBLabel: 'Final decisions',
    sections: [
      CollectPublicSectionData(
        title: 'Why current insurance misses informal earners',
        body:
            'Annual risks cannot always be funded with one large annual payment. Informal earners may understand the need for insurance but struggle with premiums and processes designed around regular monthly salaries.',
        bullets: [
          'Premiums do not match daily cash flow',
          'Policies are difficult to understand',
          'Insurance access is concentrated in formal channels',
          'Small payments are costly to collect',
          'Claims processes can weaken trust',
          'Credit is exposed when income stops',
        ],
      ),
      CollectPublicSectionData(
        title: 'Protection products',
        body:
            'Collect supports simple protection records with licensed insurers and keeps product boundaries clear.',
        bullets: [
          "Income Protection - pays a short-term benefit when a covered member's income is verifiably interrupted",
          'Credit Life Protection - settles an eligible loan balance if the covered borrower dies or becomes permanently disabled',
          'Credit Repayment Protection - covers scheduled repayments after a verified temporary loss of income',
          'Group Savings Protection - covers a scheduled contribution after a verified temporary loss of income',
        ],
      ),
      CollectPublicSectionData(
        title: 'How it works',
        body:
            'The customer sees eligible cover, reviews the terms, pays on a flexible schedule, receives proof, and can get support when a claim notification is needed.',
        bullets: [
          'Product terms, exclusions, price and insurer are displayed',
          'Premium is collected daily or through a flexible schedule',
          'The member receives digital proof of cover',
          'Collect supports claim notification and evidence collection',
        ],
      ),
      CollectPublicSectionData(
        title: 'Provider decision boundary',
        body:
            "Protection should not lapse because today's balance is short, but the insurer remains responsible for the claims decision and valid claim payment.",
        bullets: [
          'Licensed insurer issues the cover',
          'Collect supports records and communication',
          'Claims decisions stay with the insurer',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/craas',
    navLabel: 'CRaaS',
    title: 'From loan inquiry to bank-ready file.',
    intro:
        'CRaaS helps a business understand what a lender needs, close the gaps, and submit one complete, bank-ready application file.',
    imageAsset:
        'assets/brand/collect_runtime/media/mobile-money-ussd-signal.png',
    metricA: 'Readiness',
    metricALabel: 'File support',
    metricB: 'Provider',
    metricBLabel: 'Final decision',
    sections: [
      CollectPublicSectionData(
        title: 'Payment access is widespread. Loan preparation support is not.',
        body:
            'Small businesses often need finance but do not know exactly what a bank requires. Many lack structured records, cash-flow forecasts, collateral evidence or corporate documentation.',
        bullets: [
          'Unclear lender and product requirements',
          'Missing or expired documents',
          'Weak business and cash-flow records',
          'Expensive professional preparation services',
          'Rejection before full credit analysis begins',
        ],
      ),
      CollectPublicSectionData(
        title: 'What banks face',
        body:
            'Bank teams often receive incomplete files, inconsistent applicant quality, manual document checks, delayed analyst review, and high origination cost for small-business files.',
        bullets: [
          'Incomplete files',
          'Inconsistent applicant quality',
          'Manual document checking',
          'Delayed analyst review',
          'High cost of small-business origination',
        ],
      ),
      CollectPublicSectionData(
        title: 'How CRaaS works',
        body:
            'CRaaS moves a business from loan inquiry to intake, requirement mapping, document preparation, service coordination, and bank-ready packaging.',
        bullets: [
          'Loan inquiry and Collect intake',
          'Requirement mapping against bank and product needs',
          'Document preparation and service coordination',
          'Completed application indexed for final bank review',
        ],
      ),
      CollectPublicSectionData(
        title: 'Specialist support services',
        body:
            'Support is grouped so businesses can see the difference between financial readiness and legal or asset readiness.',
        bullets: [
          'Financial readiness: accounting, business plan and tax advisory',
          'Legal and asset readiness: notaries, legal services, collateral documents and property valuation',
          'Customer summary and indexed document folder',
          'Readiness review with gaps and next steps',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/community-groups',
    navLabel: 'Community Groups',
    title: 'Finance works better when communities lead.',
    intro:
        'Collect adds digital tools without changing how your group already leads itself - same relationships, same governance, same rules.',
    imageAsset: 'assets/brand/collect_runtime/media/group-momentum.png',
    metricA: 'Group',
    metricALabel: 'Member records',
    metricB: 'Mobile app',
    metricBLabel: 'Group operations',
    sections: [
      CollectPublicSectionData(
        title: 'What the app enables for group leaders',
        body:
            'Leaders get clearer records for running the group without replacing the existing leadership structure.',
        bullets: [
          'Create and manage the group',
          'Set contribution rules',
          'Assign leadership roles',
          'Track activity and missed contributions',
          'Produce transparent statements',
        ],
      ),
      CollectPublicSectionData(
        title: 'What the app enables for members',
        body:
            'Members can contribute, receive proof, understand group rules, and build a verified contribution history.',
        bullets: [
          'Contribute through app or USSD',
          'Receive proof of each contribution',
          'View personal and group progress',
          'Understand group rules',
          'Access bank credit and insurance where eligible',
        ],
      ),
      CollectPublicSectionData(
        title: 'Community use cases',
        body:
            'Collect supports groups that already organize around work, family, savings, faith, business, agriculture and diaspora ties.',
        bullets: [
          'Moto-taxi groups - save toward insurance, taxes, licensing and green-mobility assets',
          'Agricultural cooperatives - accumulate capital for inputs, equipment, storage and working capital',
          'Women and youth groups - build verified savings histories and access structured business-readiness support',
          'MSME associations - prepare members for business loans and coordinate professional services',
          'Diaspora associations - create partner-bank-linked group savings and eligible collateral arrangements',
        ],
      ),
      CollectPublicSectionData(
        title: 'Collect supports community groups',
        body:
            'Use groups as trusted channels for saving, support, records, credit-readiness and protection journeys.',
        bullets: [
          'Community and faith: ibimina, religious and neighbourhood associations, family savings groups',
          'Economic: cooperatives, trade and business associations, agricultural groups, employer and professional groups',
          'Demographic: women-led groups, youth savings groups, diaspora associations',
        ],
      ),
    ],
  ),
  CollectPublicPageData(
    path: '/our-partners',
    navLabel: 'Our Partners',
    title: "The banking opportunity in Rwanda's informal economy.",
    intro:
        'These customers already earn, save, and borrow - just outside the formal system. Collect turns that existing discipline into deposits, data, and bankable credit relationships.',
    imageAsset:
        'assets/brand/collect_runtime/media/mobile-money-ussd-signal.png',
    metricA: 'RWF 288B+',
    metricALabel: 'Annual ibimina savings flow',
    metricB: '4.8M',
    metricBLabel: 'Informal and group savers',
    sections: [
      CollectPublicSectionData(
        title:
            'A large savings and credit market already exists, mostly outside formal banking.',
        body:
            'Informal saving and borrowing are already active. The opportunity is to convert existing discipline into formal deposits, reliable data and bankable credit relationships.',
        bullets: [
          'RWF 288B+ informal savings market',
          '4.8M active savers',
          '94,000+ savings groups',
        ],
      ),
      CollectPublicSectionData(
        title: 'Low-cost deposit mobilisation',
        body:
            'Reach millions of informal savers through existing ibimina, cooperatives and community networks.',
        bullets: [
          'Mobile app and USSD access',
          'Member and group accounts',
          'Purpose-based savings',
          'Automated ledger reconciliation',
        ],
      ),
      CollectPublicSectionData(
        title: 'Daily-income lending and repayment',
        body:
            'Collect helps banks design loans around how customers actually earn rather than forcing daily earners into a monthly salary model.',
        bullets: [
          'Daily or periodic micro-repayments',
          'Up to 365 repayment data points per borrower annually',
          'Earlier visibility of repayment stress',
          'More accurate portfolio monitoring',
        ],
      ),
      CollectPublicSectionData(
        title: 'Group-backed and diaspora lending',
        body:
            'Verified group savings can provide an additional risk-control layer for eligible lending, including diaspora savings-to-credit models subject to bank policy and approval. The addressable Rwandan diaspora market is 300,000+ people across Europe, the United Kingdom, North America and other corridors.',
        bullets: [
          'Bank-held savings collateral',
          'Group accountability',
          'Contribution history',
          'Purpose-controlled disbursement',
        ],
      ),
      CollectPublicSectionData(
        title: 'Stronger MSME credit origination',
        body:
            'Collect Credit Readiness-as-a-Service prepares applicants before formal bank review so credit teams receive more complete, structured and decision-ready MSME files.',
        bullets: [
          'Requirement mapping',
          'Business-document checklist',
          'Gap closure before bank review',
          'Cleaner applicant summary',
        ],
      ),
    ],
  ),
];
