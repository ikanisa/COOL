#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"
require "time"
require "yaml"

ROOT = File.expand_path("..", __dir__)
BUILD_DIR = File.expand_path(ENV.fetch("PUBLIC_BUILD_DIR", "build/public_web"), ROOT)
PUBLIC_URL = "https://collect.ikanisa.com"
ASSET_VERSION = "20260623-mobile-fix"
APP_DOWNLOAD_URL = "https://play.google.com/store/apps/details?id=app.cool.mobile"
WHATSAPP_NUMBER = "250795588248"
DISPLAY_PHONE = "+250 795 588 248"
USSD_CODE = "*182*8*1*41258*2000#"
SUPPORT_EMAIL = "info@ikanisa.com"
REGISTERED_ENTITY = "IKANISA Ltd."
REGULATORY_FOOTER_NOTE = "IKANISA Ltd. is a registered technology company. Savings, credit and insurance products are provided by licensed partner institutions where approved arrangements apply."
BRAND_ASSET = "assets/brand/collect_runtime/media/group-momentum.png"
MOMO_ASSET = "assets/brand/collect_runtime/media/mobile-money-ussd-signal.png"
QR_ASSET = "assets/brand/collect_runtime/media/qr-share.png"
ICON_ASSET = "assets/brand/collect_runtime/app_icons/app-icon-rule.png"
INDEXNOW_KEY = ENV.fetch("PUBLIC_INDEXNOW_KEY", "").strip
INDEXNOW_KEY_PATTERN = /\A[A-Za-z0-9-]{8,128}\z/
LEGAL_CONTENT_DIR = File.join(ROOT, "content/legal")
LEGAL_BUNDLE = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_legal_pages_bundle.yaml"))
LEGAL_PRIVACY = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_privacy_policy.yaml")).fetch("page")
LEGAL_TERMS = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_terms_of_use.yaml")).fetch("page")
LEGAL_DELETE_ACCOUNT = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_delete_account.yaml")).fetch("page")

GOOGLE_PLAY_PROOF = [
  ["Google Play listing", "Collect is publicly listed on Google Play under package app.cool.mobile by IKANISA in the Finance category."],
  ["Public app signal", "The listing showed 5+ downloads and a June 21, 2026 update when this page was prepared on June 29, 2026."],
  ["Data-safety signal", "The listing presents data-safety and deletion-request information, matching the public Privacy and Account Deletion routes."],
  ["Crawl-ready web proof", "This public site ships raw HTML, canonical URLs, robots.txt, sitemap.xml, structured data, security headers and static assets without a Flutter critical path."]
].freeze

PUBLIC_FAQS = {
  "/" => [
    ["What is Collect?", "Collect helps savings groups and daily earners keep clearer contribution records, prepare credit-readiness files, and connect to approved provider workflows where eligible."],
    ["Does Collect hold customer deposits?", "No. Where regulated products are involved, funds and financial products are provided through licensed partner institutions."],
    ["Can I use Collect without a smartphone?", "The public product direction includes supported USSD and assisted channels so basic-phone users are not excluded."],
    ["Is credit guaranteed?", "No. Collect can help prepare records and files, but banks and approved providers make their own final decisions."]
  ],
  "/group-savings/" => [
    ["Can an existing ibimina use Collect?", "Yes. Collect is designed to add records, statements and structure without forcing the group to abandon its own rules."],
    ["Can groups keep rotating rules?", "Yes. Groups can keep their culture and add accumulating goals where members agree."],
    ["Who sees member records?", "Members and authorised leaders see the information needed for group transparency; private documents are not automatically visible to other members."],
    ["How does a group start?", "The current assisted path is to talk to IKANISA support about starting a group, then complete setup through the app or supported channels."]
  ],
  "/diaspora/" => [
    ["Who is the diaspora page for?", "It is for Rwandan diaspora groups that save together and want clearer records for host-country bank discussions and Rwanda investment goals."],
    ["Does Collect approve diaspora loans?", "No. A partner bank or lender makes its own credit decision under its policy."],
    ["Why do group records matter?", "Verified contribution history can help explain savings discipline, group rules and collateral arrangements during provider review."],
    ["Is French support planned?", "French public content is now available for the diaspora and partner pages; human legal review is still recommended before using translated wording externally in regulated materials."]
  ],
  "/insurance/" => [
    ["Does Collect issue insurance?", "No. Licensed insurers issue cover and make claim decisions. Collect supports records, communication and customer workflows."],
    ["Why daily premiums?", "Daily or flexible micro-payments can better match the way informal earners receive income."],
    ["What happens during a claim?", "Collect can help organise notification and evidence collection, but the insurer remains responsible for the final claim decision."],
    ["Is every customer eligible?", "No. Eligibility, pricing, exclusions and claim rules depend on the insurer and product terms."]
  ],
  "/craas/" => [
    ["What does CRaaS mean?", "Credit Readiness-as-a-Service helps a business understand lender requirements, close document gaps and package a bank-ready file."],
    ["Does CRaaS replace a bank credit team?", "No. It improves preparation before bank review; the bank remains responsible for assessment, pricing and approval."],
    ["Which services can be coordinated?", "Accounting, tax, business-plan, legal, notarial, valuation and collateral-document support can be coordinated where relevant."],
    ["Who should use CRaaS?", "MSMEs and informal businesses that need a clearer loan file before approaching a lender."]
  ],
  "/community-groups/" => [
    ["Which groups can use Collect?", "Ibimina, faith groups, family savings groups, cooperatives, trade associations, youth groups, women-led groups and diaspora associations can use the group-record model."],
    ["Does Collect replace group leaders?", "No. Group leaders and members keep their governance; Collect supports clearer records and operations."],
    ["Can groups save for specific goals?", "Yes. Groups can track purpose-based goals such as school fees, agricultural inputs, insurance, business assets or emergency funds."],
    ["Can members use USSD?", "Supported USSD and assisted channels are part of the inclusion model for members without smartphones."]
  ],
  "/our-partners/" => [
    ["What does a partner bank get?", "Cleaner deposit mobilisation, group ledgers, customer records, readiness files and clearer provider-review workflows."],
    ["Does Collect take over regulated obligations?", "No. Banks and insurers keep KYC, AML/CFT, eligibility, pricing, approval, disbursement, recovery and reporting obligations."],
    ["Are the market numbers Collect traction?", "No. Market figures describe the opportunity. Collect-specific public proof is shown separately and should not be read as customer-volume traction."],
    ["How should an institution start?", "The right first step is to talk to the IKANISA team about product scope, risk boundaries and provider responsibilities."]
  ],
  "/trust/" => [
    ["Does Collect sell personal data?", "No. The public trust and privacy pages state that personal data is not sold."],
    ["Does AI make final financial decisions?", "No. AI may assist preparation or support workflows, but banks and insurers make their own final decisions."],
    ["How do customers request deletion?", "Customers can use the in-app deletion path where available, WhatsApp support, or info@ikanisa.com."],
    ["Why does limited retention exist?", "Ledger, security, dispute, payment, tax, audit, legal or regulatory records may need limited retention."]
  ]
}.freeze

LOCALIZED_PAGES = [
  {
    path: "/rw/",
    lang: "rw",
    title: "Collect mu Kinyarwanda | Ibimina n'ubwizigame bwa buri munsi",
    description: "Collect ifasha ibimina n'abinjiza amafaranga ya buri munsi kugira inyandiko zisobanutse, kwizigamira no kwitegura dosiye ishobora gusuzumwa n'abatanga serivisi.",
    h1: "Ibimina n'ubwizigame bwa buri munsi bifite inyandiko zisobanutse",
    intro: "Collect yongerera amatsinda uburyo bwo kubika inyandiko, kureba imisanzu no gutegura amakuru asabwa mbere y'isuzuma ry'umufatanyabikorwa wemerewe.",
    cta: "Bona app",
    secondary_cta: "Vugana natwe ku gutangiza itsinda",
    sections: [
      ["Icyo Collect ikora", "Ifasha amatsinda kubika imisanzu, amategeko y'itsinda, inshingano z'abayobozi n'amateka y'ubwizigame mu buryo busomeka."],
      ["Uburyo bwo gutangira", "Itsinda rishobora kuvugana na IKANISA, gushyiraho intego n'amategeko, hanyuma rikoresha app cyangwa inzira zifashijwe."],
      ["Icyitonderwa ku nguzanyo", "Collect itegura inyandiko n'amakuru. Banki cyangwa umufatanyabikorwa wemerewe ni we ufata icyemezo cya nyuma."]
    ],
    faqs: [
      ["Collect isimbura ubuyobozi bw'itsinda?", "Oya. Itsinda rikomeza amategeko n'ubuyobozi bwaryo; Collect yongeraho inyandiko n'uburyo bwo gukurikirana."],
      ["Abadafite smartphone bazakoresha iki?", "Uburyo bwa USSD n'inzira zifashijwe ziri mu cyerekezo cya serivisi kugira ngo abantu badafite smartphone batavamo."],
      ["Collect isezeranya inguzanyo?", "Oya. Itanga inyandiko zifasha kwitegura; umutanga serivisi ni we usuzuma kandi agafata icyemezo."]
    ]
  },
  {
    path: "/rw/group-savings/",
    lang: "rw",
    title: "Ibimina | Collect mu Kinyarwanda",
    description: "Collect ifasha ibimina n'amatsinda yo kwizigamira kugira amategeko, imisanzu, inyandiko n'amateka y'ubwizigame bisobanutse.",
    h1: "Itsinda ryanyu rifite icyizere. Collect yongeraho imiterere.",
    intro: "Buri musanzu ubikwa, buri munyamuryango akabona ishusho y'uruhare rwe, kandi amateka y'itsinda akagira inyandiko ishobora gusomwa.",
    cta: "Bona app",
    secondary_cta: "Vugana natwe ku gutangiza itsinda",
    sections: [
      ["Icyizere gisanzwe", "Collect ntikuraho umuco w'ibimina. Yongeraho uburyo bwo kwandika, gukurikirana no gusobanurira abanyamuryango ibyabaye."],
      ["Uruhare rw'abanyamuryango", "Abanyamuryango bashobora kubona imisanzu, intego n'amategeko y'itsinda aho bishoboka."],
      ["Inyandiko zishobora gufasha ejo", "Amateka y'ubwizigame ashobora gufasha mu kiganiro n'abafatanyabikorwa, ariko icyemezo cya nyuma kiguma kuri bo."]
    ],
    faqs: [
      ["Itsinda rishobora kuguma ku buryo busanzwe?", "Yego. Collect ifasha itsinda kongera imiterere aho rishaka, itabahatira guhindura umuco wabo."],
      ["Amafaranga abikwa na Collect?", "Oya. Aho serivisi z'imari zigenzurwa zikoreshwa, zicungwa n'abafatanyabikorwa babifitiye uburenganzira."],
      ["Tangira ute?", "Vugana na IKANISA kugira ngo hasuzumwe intego, amategeko n'uburyo bukwiriye itsinda."]
    ]
  },
  {
    path: "/rw/community-groups/",
    lang: "rw",
    title: "Amatsinda y'abaturage | Collect mu Kinyarwanda",
    description: "Collect yongerera amatsinda y'abaturage ibikoresho bya digitale ataretse imiyoborere n'icyizere asanzwe afite.",
    h1: "Imari ikora neza iyo abaturage bayiyoboye.",
    intro: "Amatsinda akomeza imiyoborere, amategeko n'umubano wayo. Collect yongeraho inyandiko zisobanutse, intego n'uburyo bwo gukurikirana.",
    cta: "Bona app",
    secondary_cta: "Vugana natwe ku itsinda",
    sections: [
      ["Ku bayobozi b'amatsinda", "Gushyiraho itsinda, amategeko, inshingano, gukurikirana imisanzu no gutanga ishusho isobanutse."],
      ["Ku banyamuryango", "Gutanga umusanzu, kubona gihamya, gusobanukirwa amategeko n'iterambere ry'itsinda."],
      ["Amatsinda akenerwa", "Ibimina, amatsinda y'imiryango, amadini, amakoperative, urubyiruko, abagore n'amatsinda ya diaspora."]
    ],
    faqs: [
      ["Ni ayahe matsinda akwiye Collect?", "Ibimina, amakoperative, amatsinda y'imiryango, ay'urubyiruko, ay'abagore, ay'abahinzi n'aya diaspora."],
      ["Collect ihindura abayobozi?", "Oya. Ifasha abayobozi n'abanyamuryango kubona inyandiko n'imiterere myiza."],
      ["Intego zishobora gutandukana?", "Yego. Ishuri, ubuhinzi, ubwishingizi, ubucuruzi, ibikoresho cyangwa ikigega cyihutirwa bishobora gukurikiranwa."]
    ]
  },
  {
    path: "/fr/diaspora/",
    lang: "fr",
    title: "Epargne diaspora | Collect par IKANISA",
    description: "Collect aide les groupes de la diaspora rwandaise a organiser leur epargne, leurs preuves de contribution et leurs discussions bancaires.",
    h1: "Une epargne de groupe qui renforce l'acces au credit bancaire.",
    intro: "Les groupes de la diaspora peuvent conserver des traces claires de contribution, definir des regles de garantie et preparer des projets d'investissement au Rwanda pour revue bancaire.",
    cta: "Parler a l'equipe",
    secondary_cta: "Voir l'app Android",
    sections: [
      ["Pour qui", "La page s'adresse aux groupes de la diaspora rwandaise en Europe, au Royaume-Uni, en Amerique du Nord et dans d'autres corridors."],
      ["Ce que Collect clarifie", "Historique de contribution, regles de groupe, epargne detenue par le partenaire bancaire et documents utiles a la revue."],
      ["Limite importante", "Collect ne prend pas la decision de credit. La banque partenaire applique ses propres regles de risque, KYC, prix et approbation."]
    ],
    faqs: [
      ["Collect accorde-t-il le pret?", "Non. La decision finale appartient a la banque ou au preteur partenaire."],
      ["Pourquoi l'epargne de groupe compte?", "Elle rend visible la discipline d'epargne et les regles du groupe avant la revue bancaire."],
      ["Le contenu francais remplace-t-il les documents legaux?", "Non. Les pages juridiques anglaises restent la reference publique jusqu'a validation juridique traduite."]
    ]
  },
  {
    path: "/fr/our-partners/",
    lang: "fr",
    title: "Partenaires bancaires | Collect par IKANISA",
    description: "Collect aide les institutions financieres a transformer une discipline d'epargne informelle en dossiers, depots et relations bancaires plus lisibles.",
    h1: "L'opportunite bancaire dans l'economie informelle rwandaise.",
    intro: "Collect aide les banques et assureurs a lire les flux d'epargne existants, sans transferer leurs obligations reglementaires ou decisions finales a Collect.",
    cta: "Parler a l'equipe",
    secondary_cta: "Voir l'app Android",
    sections: [
      ["Ce que Collect apporte", "Mobilisation d'epargne, dossiers de groupe, historique de contribution, preparation de dossiers et support client."],
      ["Ce que le partenaire conserve", "KYC, AML/CFT, eligibilite, prix, approbation, decaissement, recouvrement, sinistres et reporting reglementaire."],
      ["Preuves publiques actuelles", "Application Android publique, routes de confidentialite et suppression, sitemap, robots.txt et donnees structurees deployees."]
    ],
    faqs: [
      ["Les chiffres de marche sont-ils la traction de Collect?", "Non. Ils decrivent le marche. Les preuves propres a Collect sont presentees separement."],
      ["Collect remplace-t-il le credit scoring bancaire?", "Non. Collect prepare les dossiers; le partenaire decide."],
      ["Comment commencer?", "La premiere etape est une discussion avec IKANISA sur le perimetre, les responsabilites et les controles."]
    ]
  }
].freeze

PRIMARY_NAV = [
  ["Group Savings", "/group-savings/"],
  ["Diaspora", "/diaspora/"],
  ["Insurance", "/insurance/"],
  ["CRaaS", "/craas/"],
  ["Community Groups", "/community-groups/"],
  ["Our Partners", "/our-partners/"],
  ["Trust & Security", "/trust/"]
].freeze

PAGES = [
  {
    path: "/",
    title: "Collect by IKANISA | Microsavings and Group Savings",
    description: "Collect helps daily earners and savings groups organize microsavings, daily savings, ledgers, credit-readiness support, and provider-review files through a public app and supported USSD journeys.",
    h1: "Microsavings and group savings for daily earners",
    intro: "Collect helps ibimina, community groups, and daily earners turn daily savings into capital accumulation, clearer ledgers, credit-readiness support files, and access to loans.",
    asset: BRAND_ASSET,
    metrics: [
      ["96%", "Rwandan adults financially included"],
      ["85%", "Adults saved formally or informally"],
      ["24%", "Adults using formal borrowing"]
    ],
    sections: [
      ["Microsavings and daily savings", "Support small, regular contributions for people who earn daily and save in practical amounts.", ["Daily earners", "Supported USSD paths", "Low-friction records"]],
      ["Group savings", "Set up a savings group, organize members and roles, and keep contribution activity easier to review.", ["Group setup", "Member roles", "Contribution history"]],
      ["Credit-readiness support", "Prepare contribution history, documents, and request summaries before a financial provider reviews the file.", ["Readiness files", "Missing-item support", "Provider review boundary"]],
      ["Access to capital and loans", "Organize records that may support capital-access and loan conversations with the relevant provider.", ["Provider-review files", "Capital access preparation", "No approval promise"]],
      ["Microinsurance support", "Keep insurance-related records organized where approved providers are involved.", ["Protection records", "Support history", "Provider decision boundary"]],
      ["Diaspora credit and collateral support", "Prepare group savings records for diaspora credit or group savings collateral support discussions, where a provider review is required.", ["Diaspora preparation", "Group savings collateral support", "Provider decision boundary"]]
    ]
  },
  {
    path: "/group-savings/",
    title: "Group Savings | Collect by IKANISA",
    description: "Every contribution is recorded, every member has a statement, and group savings discipline becomes something a bank can understand.",
    h1: "Your group already has trust. Collect adds structure.",
    intro: "Every contribution is recorded, every member has a statement, and your group's savings discipline becomes something a bank can understand.",
    start_heading: "Give every contribution a clear purpose and a trusted record.",
    asset: BRAND_ASSET,
    nav_label: "Group Savings",
    sections: []
  },
  {
    path: "/diaspora/",
    title: "Diaspora Savings | Collect by IKANISA",
    description: "Diaspora groups save through a bank in the host country. The bank holds the savings and can lend to members against the pooled group savings as collateral.",
    h1: "Group savings that strengthen access to bank credit.",
    intro: "Diaspora groups save through a bank in the host country. The bank holds the savings and can lend to members against the pooled group savings as collateral.",
    asset: QR_ASSET,
    nav_label: "Diaspora",
    summary_label: "Diaspora group records",
    metrics: [
      ["Group records", "Member contributions"],
      ["Preparation", "Rwanda discussions"]
    ],
    infographic: {
      title: "Diaspora savers face their own barriers to credit.",
      body: "",
      steps: [
        ["Mobility and recovery risk", "Host-country banks may fear that a borrower could relocate or return to Rwanda before fully repaying a loan, making recovery and enforcement more difficult."],
        ["Thin or no host-country credit history", "Credit history built in Rwanda is generally not portable, while newer migrants may not yet have enough local borrowing history or credit-score depth."],
        ["Informal or unstable employment", "Temporary, gig, part-time, self-employed and variable-income work may not meet a bank's preference for permanent contracts and predictable monthly income."],
        ["Insufficient acceptable security", "Individual applicants may lack locally recognised collateral, guarantees or pledged deposits that the host-country bank can control."]
      ]
    },
    sections_heading: "How the diaspora use Collect",
    sections: [
      ["Create a savings group", "Members agree on purpose, contribution amount, leadership and rules.", []],
      ["Save regularly", "Members contribute through Collect into the host-country partner bank.", []],
      ["Build the group pool", "Contributions accumulate while Collect maintains the group ledger.", []],
      ["Agree the collateral rules", "An approved share of the pool may be pledged or ring-fenced for loan.", []],
      ["Apply for credit", "A member submits an individual loan application to the host-country partner bank.", []],
      ["Invest at home", "Use the loan to invest in property or a business in Rwanda.", []]
    ]
  },
  {
    path: "/insurance/",
    aliases: ["/protection/"],
    title: "Insurance | Collect by IKANISA",
    description: "Collect can help organize insurance-related records where approved providers are involved.",
    h1: "Protection that fits how people earn.",
    intro: "Collect works with licensed insurers to design simple protection products, flexible premium micro-payments and transparent claims journeys for informal and variable-income communities.",
    asset: MOMO_ASSET,
    nav_label: "Insurance",
    summary_label: "Insurance support records",
    metrics: [
      ["Records", "Customer support"],
      ["Providers", "Final decisions"]
    ],
    infographic: {
      title: "Why current insurance misses informal earners",
      body: "Annual risks cannot always be funded with one large annual payment. Informal earners may understand the need for insurance but struggle with premiums and processes designed around regular monthly salaries. Insurers also face high costs when collecting many small payments and servicing customers outside traditional channels.",
      steps: [
        ["Premiums do not match daily cash flow", ""],
        ["Policies are difficult to understand", ""],
        ["Insurance access is concentrated in formal channels", ""],
        ["Small payments are costly to collect", ""],
        ["Claims processes can weaken trust", ""],
        ["Credit is exposed when income stops", ""]
      ]
    },
    sections_heading: "Protection products",
    sections: [
      ["Income Protection", "Pays a short-term benefit when a covered member's income is verifiably interrupted.", []],
      ["Credit Life Protection", "Settles an eligible loan balance if the covered borrower dies or becomes permanently disabled.", []],
      ["Credit Repayment Protection", "Covers scheduled repayments for a defined period after a verified, temporary loss of income.", []],
      ["Group Savings Protection", "Covers a scheduled contribution for a defined period after a verified, temporary loss of income.", []]
    ]
  },
  {
    path: "/craas/",
    aliases: ["/credit-readiness/"],
    title: "CRaaS | Collect by IKANISA",
    description: "CRaaS helps a business understand what a lender needs, close the gaps, and submit one complete, bank-ready application file.",
    h1: "From loan inquiry to bank-ready file.",
    intro: "CRaaS helps a business understand what a lender needs, close the gaps, and submit one complete, bank-ready application file.",
    asset: MOMO_ASSET,
    nav_label: "CRaaS",
    summary_label: "Credit-readiness service",
    metrics: [
      ["Readiness", "File support"],
      ["Provider", "Final decision"]
    ],
    infographic: {
      title: "Payment access is widespread. Loan preparation support is not.",
      body: "Small businesses often need finance but do not know exactly what a bank requires. Many lack structured records, cash-flow forecasts, collateral evidence or the corporate documentation needed to complete a strong loan file. Preparation services are fragmented.",
      steps: [
        ["What businesses face", [
          "Unclear lender and product requirements",
          "Missing or expired documents",
          "Weak business and cash-flow records",
          "Expensive professional preparation services",
          "Rejection before full credit analysis begins"
        ]],
        ["What banks face", [
          "Incomplete files",
          "Inconsistent applicant quality",
          "Manual document checking",
          "Delayed analyst review",
          "High cost of small-business origination"
        ]]
      ]
    },
    sections_heading: "How CRaaS works",
    sections: [
      ["Loan inquiry", "The business states the financing need, amount, purpose and repayment.", []],
      ["Collect intake", "Captures the business profile and explains the preparation process.", []],
      ["Requirement mapping", "The request is matched to relevant bank and product requirements.", []],
      ["Document preparation", "Collect guides and supports on preparation of required documents.", []],
      ["Service coordination", "Collect coordinates corporate and admin processes and specialist services.", []],
      ["Bank-ready packaging", "The completed application is indexed and prepared for final bank review.", []]
    ]
  },
  {
    path: "/community-groups/",
    title: "Community Groups | Collect by IKANISA",
    description: "Collect equips trusted groups with digital tools while preserving the relationships, leadership and governance that already make them work.",
    h1: "Finance works better when communities lead.",
    intro: "Collect adds digital tools without changing how your group already leads itself - same relationships, same governance, same rules.",
    asset: BRAND_ASSET,
    nav_label: "Community Groups",
    summary_label: "Mobile group operations",
    metrics: [
      ["Group", "Member records"],
      ["Mobile app", "Group operations"]
    ],
    infographic: {
      title: "What the app enables for a group",
      body: "",
      steps: [
        ["For group leaders", [
          "Create and manage groups",
          "Define contribution rules",
          "Assign leadership roles",
          "Track missed contributions",
          "Produce transparent statements"
        ]],
        ["For members", [
          "Contribute through app or USSD",
          "Receive proof of each contribution",
          "View personal and group progress",
          "Understand group rules",
          "Build a verified contribution history",
          "Access to bank credit and insurance"
        ]]
      ]
    },
    sections_heading: "Community use cases",
    sections: [
      ["Moto-taxi groups", "Save toward insurance, taxes, licensing and green-mobility assets.", []],
      ["Agricultural cooperatives", "Accumulate capital for inputs, equipment, storage and working capital.", []],
      ["Women and youth groups", "Build verified savings histories and access structured business-readiness support.", []],
      ["MSME associations", "Prepare members for business loans and coordinate professional services.", []],
      ["Diaspora associations", "Create partner-bank-linked group savings and eligible collateral arrangements.", []]
    ],
    supported_groups_heading: "Collect supports community groups",
    supported_groups: [
      "Community & faith: Ibimina, religious and neighbourhood associations, family savings groups",
      "Economic: Cooperatives, trade and business associations, agricultural groups, employer and professional groups",
      "Demographic: Women-led groups, youth savings groups, diaspora associations"
    ]
  },
  {
    path: "/our-partners/",
    aliases: ["/partners/"],
    title: "Our Partners | Collect by IKANISA",
    description: "Collect helps banks convert existing informal savings discipline into formal deposits, reliable data and bankable credit relationships.",
    h1: "The banking opportunity in Rwanda's informal economy.",
    intro: "These customers already earn, save, and borrow - just outside the formal system. Collect turns that existing discipline into deposits, data, and bankable credit relationships.",
    asset: MOMO_ASSET,
    nav_label: "Our Partners",
    summary_label: "Banking opportunity",
    metrics: [
      ["RWF 288B+", "Annual ibimina savings flow"],
      ["4.8M", "Informal and group savers"]
    ],
    infographic: {
      title: "Bank growth workflow",
      body: "Convert existing savings discipline into formal deposits, reliable data and bankable credit relationships.",
      steps: [
        ["Mobilise deposits", "Bring daily and group savings into clearer bank-linked records."],
        ["Build data", "Turn contribution history into repayment and credit-readiness signals."],
        ["Prepare credit", "Package MSME and group-backed files for formal bank review."],
        ["Grow relationships", "Support deposits, lending and diaspora banking under bank approval."]
      ]
    },
    sections: [
      ["Low-cost deposit mobilisation", "Reach millions of informal savers through existing ibimina, cooperatives and community networks.", ["Mobile app and USSD access", "Member and group accounts", "Purpose-based savings", "Automated ledger reconciliation"]],
      ["Daily-income lending and repayment", "Collect helps banks design loans around how customers actually earn rather than forcing daily earners into a monthly salary model.", ["Daily or periodic micro-repayments", "Up to 365 repayment data points per borrower annually", "Earlier visibility of repayment stress", "More accurate portfolio monitoring"]],
      ["Group-backed and diaspora lending", "Verified group savings can provide an additional risk-control layer for eligible lending, including diaspora savings-to-credit models subject to bank policy and approval.", ["Bank-held savings collateral", "Group accountability", "Contribution history", "Purpose-controlled disbursement"]],
      ["Stronger MSME credit origination", "Collect Credit Readiness-as-a-Service prepares applicants before formal bank review so credit teams receive more complete, structured and decision-ready MSME files.", ["Requirement mapping", "Business-document checklist", "Gap closure before bank review", "Cleaner applicant summary"]]
    ]
  },
  {
    path: "/trust/",
    aliases: ["/security/"],
    title: "Trust and Security | Collect by IKANISA",
    description: "How Collect protects personal data, supports privacy rights, and explains data, AI, partner and deletion boundaries.",
    h1: "Security and trust",
    intro: "Collect uses safeguards designed to protect personal data and gives customers clear routes to access, correct and delete eligible data.",
    asset: QR_ASSET,
    legal_key: :trust,
    sections: []
  },
  {
    path: "/privacy/",
    title: LEGAL_PRIVACY.dig("seo", "title"),
    description: LEGAL_PRIVACY.dig("seo", "description"),
    eyebrow: LEGAL_PRIVACY.dig("hero", "eyebrow"),
    h1: LEGAL_PRIVACY.dig("hero", "headline"),
    intro: LEGAL_PRIVACY.dig("hero", "supporting_copy"),
    asset: QR_ASSET,
    nav_label: LEGAL_PRIVACY.fetch("title"),
    summary_label: "Customer information",
    metrics: [
      ["Choice", "Customer control"],
      ["Delete", "Request path"]
    ],
    legal_key: :privacy,
    sections: []
  },
  {
    path: "/terms/",
    title: LEGAL_TERMS.dig("seo", "title"),
    description: LEGAL_TERMS.dig("seo", "description"),
    eyebrow: LEGAL_TERMS.dig("hero", "eyebrow"),
    h1: LEGAL_TERMS.dig("hero", "headline"),
    intro: LEGAL_TERMS.dig("hero", "supporting_copy"),
    asset: BRAND_ASSET,
    nav_label: LEGAL_TERMS.fetch("title"),
    summary_label: "Service terms",
    metrics: [
      ["Customer", "Service terms"],
      ["Clear", "Group rules"]
    ],
    legal_key: :terms,
    sections: []
  },
  {
    path: "/account-deletion/",
    title: LEGAL_DELETE_ACCOUNT.dig("seo", "title"),
    description: LEGAL_DELETE_ACCOUNT.dig("seo", "description"),
    eyebrow: LEGAL_DELETE_ACCOUNT.dig("hero", "eyebrow"),
    h1: LEGAL_DELETE_ACCOUNT.dig("hero", "headline"),
    intro: LEGAL_DELETE_ACCOUNT.dig("hero", "supporting_copy"),
    asset: QR_ASSET,
    nav_label: "Account deletion",
    summary_label: "Account deletion",
    metrics: [
      ["Request", "Customer control"],
      ["Review", "Required records"]
    ],
    legal_key: :account_deletion,
    sections: []
  },
  {
    path: "/data-deletion/",
    title: "Data Deletion | Collect by IKANISA",
    description: "Request deletion or anonymisation of eligible Collect personal data and understand what records may be retained.",
    eyebrow: "ACCOUNT AND DATA DELETION",
    h1: "Data deletion and retention",
    intro: "You may request deletion of eligible personal data. Some records may be retained where required by law or necessary for security, fraud prevention, disputes, regulatory compliance, or ledger integrity.",
    asset: BRAND_ASSET,
    nav_label: "Data Deletion",
    summary_label: "Data deletion",
    metrics: [
      ["Data", "Deletion request"],
      ["Support", "Customer review"]
    ],
    legal_key: :data_deletion,
    sections: []
  }
].freeze

def esc(value)
  CGI.escapeHTML(value.to_s)
end

def whatsapp_url(message)
  "https://wa.me/#{WHATSAPP_NUMBER}?text=#{CGI.escape(message)}"
end

def mailto_url(subject)
  "mailto:#{SUPPORT_EMAIL}?subject=#{CGI.escape(subject)}"
end

def page_url(path)
  normalized_path = path == "/" ? "/" : "#{path.delete_suffix("/")}/"
  "#{PUBLIC_URL}#{normalized_path}"
end

def write_file(path, body)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, body)
end

def route_file(path)
  return File.join(BUILD_DIR, "index.html") if path == "/"
  File.join(BUILD_DIR, path.delete_prefix("/").delete_suffix("/"), "index.html")
end

def nav_html(current_path)
  PRIMARY_NAV.map do |label, href|
    active = current_path == href ||
      (href == "/craas/" && current_path == "/credit-readiness/") ||
      (href == "/insurance/" && current_path == "/protection/") ||
      (href == "/our-partners/" && current_path == "/partners/")
    %(<a class="nav-link#{active ? " active" : ""}" href="#{href}">#{esc(label)}</a>)
  end.join
end

def institutional_path?(path)
  ["/craas/", "/credit-readiness/", "/our-partners/", "/partners/"].include?(path)
end

def policy_path?(page)
  page[:legal_key]
end

def primary_cta_label(current_path, page)
  return "Talk to our team" if institutional_path?(current_path)
  return "Get Support" if policy_path?(page)

  "Get the App"
end

def primary_cta_href(current_path, page)
  if institutional_path?(current_path)
    return whatsapp_url("Hello IKANISA, I want to talk to your team about Collect.")
  end

  if policy_path?(page)
    return whatsapp_url("Hello IKANISA, I need support with Collect.")
  end

  APP_DOWNLOAD_URL
end

def primary_cta_class(current_path, page, surface:)
  classes = ["button"]
  classes << (surface == :header ? "secondary" : "primary")
  classes << (institutional_path?(current_path) ? "cta-touch" : "cta-app")
  classes.join(" ")
end

def cta_links_html(current_path, page, surface:)
  group_message = "Hello IKANISA, I want to talk about starting a Collect group."
  touch_message = "Hello IKANISA, I have a question about Collect."
  secondary_class = surface == :start ? "button ghost on-light" : "button ghost"
  items = [
    %(<a class="#{primary_cta_class(current_path, page, surface: surface)}" href="#{primary_cta_href(current_path, page)}">#{primary_cta_label(current_path, page)}</a>)
  ]

  unless policy_path?(page) || institutional_path?(current_path)
    items << %(<a class="#{secondary_class} cta-group" href="#{whatsapp_url(group_message)}">Talk to us about starting a group</a>)
  end

  unless institutional_path?(current_path)
    items << %(<a class="#{secondary_class} cta-touch" href="#{whatsapp_url(touch_message)}">Get in Touch</a>)
  end

  if institutional_path?(current_path)
    items << %(<a class="#{secondary_class} cta-app" href="#{APP_DOWNLOAD_URL}">Get the App</a>)
  end

  items.join("\n")
end

def app_availability_note_html(current_path, page)
  return "" if institutional_path?(current_path) || policy_path?(page)

  %(<p class="app-availability">Available on Android now. iOS roadmap is being scoped.</p>)
end

def language_switcher_html(current_path)
  links = [
    ["EN", "/"],
    ["RW", current_path.start_with?("/group-savings") ? "/rw/group-savings/" : "/rw/"],
    ["FR", current_path.start_with?("/our-partners") || current_path.start_with?("/partners") ? "/fr/our-partners/" : "/fr/diaspora/"]
  ]
  %(<nav class="language-switcher" aria-label="Language selector">#{links.map { |label, href| %(<a href="#{href}">#{label}</a>) }.join}</nav>)
end

def content_grid_html(page, current_path)
  return "" if current_path == "/" || current_path == "/group-savings/" || page[:legal_key]

  <<~HTML
    <section class="content-grid" aria-label="#{esc(page[:sections_heading] || "Page sections")}">
      #{page[:sections_heading] ? %(<h2 class="content-grid-heading">#{esc(page[:sections_heading])}</h2>) : ""}
      #{sections_html(page[:sections])}
    </section>
  HTML
end

def proof_section_html(current_path)
  return "" unless ["/", "/our-partners/", "/partners/", "/trust/", "/security/"].include?(current_path)

  cards = GOOGLE_PLAY_PROOF.map do |title, body|
    %(<article><strong>#{esc(title)}</strong><span>#{esc(body)}</span></article>)
  end.join
  <<~HTML
    <section class="proof-section" aria-labelledby="proof-heading">
      <div class="story-copy">
        <p class="section-kicker">Verified public proof</p>
        <h2 id="proof-heading">What Collect can prove publicly today.</h2>
        <p>These are current public signals, not inflated traction claims. Market-size figures elsewhere describe the opportunity, while this section describes Collect-specific proof points available for a reviewer to verify.</p>
      </div>
      <div class="proof-grid">
        #{cards}
      </div>
    </section>
  HTML
end

def faq_section_html(current_path)
  faqs = PUBLIC_FAQS.fetch(current_path, nil)
  faqs ||= PUBLIC_FAQS.fetch("/craas/") if current_path == "/credit-readiness/"
  faqs ||= PUBLIC_FAQS.fetch("/insurance/") if current_path == "/protection/"
  faqs ||= PUBLIC_FAQS.fetch("/our-partners/") if current_path == "/partners/"
  faqs ||= PUBLIC_FAQS.fetch("/trust/") if current_path == "/security/"
  return "" unless faqs

  items = faqs.map do |question, answer|
    <<~HTML
      <details>
        <summary>#{esc(question)}</summary>
        <p>#{esc(answer)}</p>
      </details>
    HTML
  end.join

  <<~HTML
    <section class="faq-section" aria-labelledby="faq-heading">
      <div class="story-copy">
        <p class="section-kicker">FAQ</p>
        <h2 id="faq-heading">Questions visitors ask before taking the next step.</h2>
      </div>
      <div class="faq-list">
        #{items}
      </div>
    </section>
  HTML
end

def localized_route_file(path)
  File.join(BUILD_DIR, path.delete_prefix("/").delete_suffix("/"), "index.html")
end

def localized_page_url(path)
  "#{PUBLIC_URL}#{path}"
end

def localized_nav_html(lang)
  if lang == "rw"
    [
      ["Ahabanza", "/rw/"],
      ["Ibimina", "/rw/group-savings/"],
      ["Amatsinda", "/rw/community-groups/"],
      ["English", "/"]
    ]
  else
    [
      ["Diaspora", "/fr/diaspora/"],
      ["Partenaires", "/fr/our-partners/"],
      ["English", "/"]
    ]
  end.map { |label, href| %(<a class="nav-link" href="#{href}">#{esc(label)}</a>) }.join
end

def localized_page_html(page)
  sections = Array(page[:sections]).map do |title, body|
    %(<article class="section-card"><h2>#{esc(title)}</h2><p>#{esc(body)}</p></article>)
  end.join
  faqs = Array(page[:faqs]).map do |question, answer|
    %(<details><summary>#{esc(question)}</summary><p>#{esc(answer)}</p></details>)
  end.join
  alternate_en = page[:path].include?("group-savings") ? "/group-savings/" : (page[:path].include?("our-partners") ? "/our-partners/" : "/")
  <<~HTML
    <!doctype html>
    <html lang="#{esc(page[:lang])}">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{esc(page[:title])}</title>
      <meta name="description" content="#{esc(page[:description])}">
      <meta name="theme-color" content="#8885F0">
      <link rel="canonical" href="#{localized_page_url(page[:path])}">
      <link rel="alternate" hreflang="en" href="#{page_url(alternate_en)}">
      <link rel="alternate" hreflang="#{esc(page[:lang])}" href="#{localized_page_url(page[:path])}">
      <meta property="og:title" content="#{esc(page[:title])}">
      <meta property="og:description" content="#{esc(page[:description])}">
      <meta property="og:type" content="website">
      <meta property="og:url" content="#{localized_page_url(page[:path])}">
      <meta property="og:image" content="#{PUBLIC_URL}/icons/collect.png">
      <meta property="og:locale" content="#{page[:lang] == "rw" ? "rw_RW" : "fr_FR"}">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="#{esc(page[:title])}">
      <meta name="twitter:description" content="#{esc(page[:description])}">
      <link rel="icon" href="/icons/collect.png" type="image/png">
      <link rel="stylesheet" href="/styles.css?v=#{ASSET_VERSION}">
      <link rel="stylesheet" href="/sections.css?v=#{ASSET_VERSION}">
      <script type="application/ld+json">#{json_ld({ title: page[:title], description: page[:description], path: page[:path] })}</script>
    </head>
    <body>
      <a class="skip-link" href="#content">Skip to content</a>
      <header class="site-header">
        <a class="brand" href="/">
          <img src="/icons/collect.png" alt="" width="42" height="42">
          <span><strong>Collect</strong><small>by IKANISA</small></span>
        </a>
        <nav class="site-nav localized-nav" aria-label="Localized navigation">
          #{localized_nav_html(page[:lang])}
        </nav>
      </header>
      <main id="content">
        <section class="hero localized-hero">
          <div class="hero-copy">
            <h1>#{esc(page[:h1])}</h1>
            <p class="hero-intro">#{esc(page[:intro])}</p>
            <div class="hero-actions">
              <a class="button primary" href="#{page[:lang] == "fr" ? whatsapp_url("Hello IKANISA, I want to talk to your team about Collect.") : APP_DOWNLOAD_URL}">#{esc(page[:cta])}</a>
              <a class="button ghost" href="#{page[:lang] == "fr" ? APP_DOWNLOAD_URL : whatsapp_url("Hello IKANISA, I want to talk about starting a Collect group.")}">#{esc(page[:secondary_cta])}</a>
            </div>
          </div>
          <div class="hero-device">
            #{hero_visual_html(path: page[:path])}
          </div>
        </section>
        <section class="content-grid localized-content" aria-label="Localized sections">
          #{sections}
        </section>
        <section class="faq-section localized-faq" aria-labelledby="localized-faq-heading">
          <div class="story-copy">
            <p class="section-kicker">FAQ</p>
            <h2 id="localized-faq-heading">#{page[:lang] == "rw" ? "Ibibazo bikunze kubazwa" : "Questions frequentes"}</h2>
          </div>
          <div class="faq-list">
            #{faqs}
          </div>
        </section>
      </main>
      #{site_footer_html}
      <script src="/site.js?v=#{ASSET_VERSION}" defer></script>
    </body>
    </html>
  HTML
end

def site_footer_html
  <<~HTML
    <footer class="site-footer">
      <div class="footer-identity">
        <strong>Collect by IKANISA</strong>
        <p>#{esc(REGISTERED_ENTITY)}</p>
        <p>#{esc(REGULATORY_FOOTER_NOTE)}</p>
        <p>Support: <a href="#{mailto_url("Collect support")}">#{esc(SUPPORT_EMAIL)}</a> · WhatsApp #{esc(DISPLAY_PHONE)}</p>
        <p>© #{Time.now.utc.year} #{esc(REGISTERED_ENTITY)}. All rights reserved.</p>
      </div>
      <nav aria-label="Footer navigation">
        <a href="/privacy/">Privacy</a>
        <a href="/terms/">Terms</a>
        <a href="/account-deletion/">Account deletion</a>
        <a href="/data-deletion/">Data deletion</a>
        <a href="/trust/">Trust</a>
        <a href="/rw/">Kinyarwanda</a>
        <a href="/fr/diaspora/">Francais</a>
      </nav>
    </footer>
  HTML
end

def alternate_links(current_path)
  links = [%(<link rel="alternate" hreflang="x-default" href="#{page_url("/")}">)]
  if current_path == "/"
    links << %(<link rel="alternate" hreflang="rw" href="#{localized_page_url("/rw/")}">)
    links << %(<link rel="alternate" hreflang="fr" href="#{localized_page_url("/fr/diaspora/")}">)
  elsif current_path == "/group-savings/"
    links << %(<link rel="alternate" hreflang="rw" href="#{localized_page_url("/rw/group-savings/")}">)
  elsif current_path == "/diaspora/"
    links << %(<link rel="alternate" hreflang="fr" href="#{localized_page_url("/fr/diaspora/")}">)
  elsif current_path == "/our-partners/"
    links << %(<link rel="alternate" hreflang="fr" href="#{localized_page_url("/fr/our-partners/")}">)
  end
  links.join("\n")
end

def json_ld(page)
  JSON.generate({
    "@context" => "https://schema.org",
    "@graph" => [
      {
        "@type" => "Organization",
        "name" => "IKANISA Ltd.",
        "url" => PUBLIC_URL,
        "contactPoint" => {
          "@type" => "ContactPoint",
          "contactType" => "customer support",
          "telephone" => DISPLAY_PHONE,
          "areaServed" => "RW"
        }
      },
      {
        "@type" => "SoftwareApplication",
        "name" => "Collect by IKANISA",
        "applicationCategory" => "FinanceApplication",
        "operatingSystem" => "Android, Web",
        "url" => page_url(page[:path]),
        "description" => page[:description]
      }
    ]
  })
end

def sections_html(sections)
  sections.each_with_index.map do |section, index|
    title, body, bullets = section
    bullet_html = Array(bullets).empty? ? "" : %(
        <ul class="bullet-list">
          #{Array(bullets).map { |item| %(<li>#{esc(item)}</li>) }.join}
        </ul>
    )
    %(
      <article class="section-card">
        <span class="section-number">#{format("%02d", index + 1)}</span>
        <h2>#{esc(title)}</h2>
        <p>#{esc(body)}</p>
        #{bullet_html}
      </article>
    )
  end.join
end

def legal_content_for(page)
  case page[:legal_key]
  when :privacy
    LEGAL_PRIVACY
  when :terms
    LEGAL_TERMS
  when :account_deletion
    LEGAL_DELETE_ACCOUNT
  when :data_deletion
    {
      "title" => "Data Deletion",
      "important_notice" => LEGAL_DELETE_ACCOUNT["important_notice"],
      "sections" => [
        privacy_section("account-and-data-deletion"),
        keyed_section("What happens next", LEGAL_DELETE_ACCOUNT["what_happens_next"]),
        keyed_section("Data we may retain", LEGAL_DELETE_ACCOUNT["data_we_may_retain"]),
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
  Array(LEGAL_PRIVACY["sections"]).find { |section| section["id"] == id }
end

def keyed_section(heading, content)
  return nil unless content.is_a?(Hash)

  content.merge("heading" => heading)
end

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
  details = hash.select { |_key, value| value.is_a?(String) || value.is_a?(Numeric) }
  nested = hash.reject { |key, value| details.key?(key) || %w[id].include?(key.to_s) || legal_internal_key?(key) || value.nil? || value.respond_to?(:empty?) && value.empty? }
  <<~HTML
    #{legal_details_html(details)}
    #{nested.map { |key, value| legal_named_value_html(key, value) }.join}
  HTML
end

def legal_details_html(details)
  seen = {}
  rows = details.reject { |key, value| legal_internal_key?(key) || value.to_s.strip.empty? }.map do |key, value|
    label = legal_contact_key?(key) ? "Email" : legal_label(key)
    dedupe_key = [label, value.to_s.strip]
    next if seen[dedupe_key]

    seen[dedupe_key] = true
    %(<dt>#{esc(label)}</dt><dd>#{esc(value)}</dd>)
  end.compact
  return "" if rows.empty?

  %(<dl class="legal-details">#{rows.join}</dl>)
end

def legal_contact_key?(key)
  %w[email privacy_email support_email general_support privacy complaints partnerships].include?(key.to_s)
end

def legal_named_value_html(key, value)
  return "" if legal_internal_key?(key) || value.nil? || value.respond_to?(:empty?) && value.empty?
  return %(<p><strong>Email:</strong> #{esc(value)}</p>) if legal_contact_key?(key) && !value.is_a?(Hash) && !value.is_a?(Array)

  case key.to_s
  when "heading"
    ""
  when "body"
    Array(value).map { |item| %(<p>#{esc(item)}</p>) }.join
  when "intro", "closing", "risk_statement", "trust_statement", "important_notice",
       "service_target", "copy", "clarification", "zero_fee_clarification",
       "non_exclusion", "priority_rule"
    %(<p>#{esc(value)}</p>)
  when "details", "contact"
    legal_details_html(value)
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
  when "path"
    %(<p><span class="legal-path">#{esc(value)}</span></p>)
  when "fields"
    legal_form_fields_html(value)
  else
    if value.is_a?(Array)
      %(<h3>#{esc(legal_label(key))}</h3>#{legal_array_html(value)})
    elsif value.is_a?(Hash)
      %(<h3>#{esc(legal_label(key))}</h3>#{legal_hash_html(value)})
    else
      %(<p><strong>#{esc(legal_label(key))}:</strong> #{esc(value)}</p>)
    end
  end
end

def legal_internal_key?(key)
  %w[id slug seo hero legal_review_note must_be_finalised_for].include?(key.to_s)
end

def legal_links_html(links)
  items = links.map do |label, href|
    normalized = href.to_s == "/delete-account" ? "/account-deletion/" : href.to_s
    linkable = ["/privacy", "/privacy/", "/terms", "/terms/", "/account-deletion", "/account-deletion/", "/data-deletion", "/data-deletion/", "/trust", "/trust/"].include?(normalized)
    href_display = normalized.end_with?("/") ? normalized : "#{normalized}/"
    content = linkable ? %(<a href="#{href_display}">#{esc(legal_label(label))}</a>) : esc(legal_label(label))
    %(<li>#{content}</li>)
  end
  %(<ul class="bullet-list">#{items.join}</ul>)
end

def legal_form_fields_html(fields)
  cards = Array(fields).map do |field|
    label = field["label"] || legal_label(field["name"])
    required = field["required"] ? "Required" : "Optional"
    options = Array(field["options"])
    <<~HTML
      <article class="legal-card">
        <h3>#{esc(label)}</h3>
        <p>#{esc(required)} field.</p>
        #{options.empty? ? "" : legal_array_html(options)}
      </article>
    HTML
  end.join
  %(<div class="legal-card-grid">#{cards}</div>)
end

def legal_section_html(section)
  return "" unless section.is_a?(Hash)

  heading = section["heading"] || section["title"] || legal_label(section["id"])
  body = section.reject { |key, _| %w[id heading title].include?(key.to_s) }
  seen_contact_values = {}
  body = body.reject do |key, value|
    next false unless legal_contact_key?(key)

    contact_value = value.to_s.strip
    duplicate = seen_contact_values[contact_value]
    seen_contact_values[contact_value] = true
    duplicate
  end
  <<~HTML
    <article class="legal-section">
      <h2>#{esc(heading)}</h2>
      #{body.map { |key, value| legal_named_value_html(key, value) }.join}
    </article>
  HTML
end

def legal_page_html(page)
  content = legal_content_for(page)
  return "" unless content

  meta = []
  meta << "Effective date: #{content["effective_date"]}" if content["effective_date"]
  meta << "Last updated: #{content["last_updated"]}" if content["last_updated"]
  top_keys = content.reject { |key, _| %w[id slug seo hero title sections].include?(key.to_s) || legal_internal_key?(key) }
  <<~HTML
    <section class="legal-content" aria-label="#{esc(content["title"] || page[:h1])}">
      #{meta.empty? ? "" : %(<p class="legal-meta">#{esc(meta.join(" · "))}</p>)}
      #{top_keys.map { |key, value| legal_named_value_html(key, value) }.join}
      #{Array(content["sections"]).map { |section| legal_section_html(section) }.join}
    </section>
  HTML
end

def supported_groups_html(page)
  groups = Array(page[:supported_groups]).map { |group| group.to_s.strip }.reject(&:empty?)
  return "" if groups.empty?

  cards = groups.each_with_index.map do |group, index|
    tone = (index % 4) + 1
    %(<article class="supported-group-card supported-group-card-#{tone}"><strong>#{esc(group)}</strong></article>)
  end.join

  <<~HTML
    <section class="supported-groups-section" aria-labelledby="supported-groups-heading">
      <h2 id="supported-groups-heading">#{esc(page[:supported_groups_heading] || "Collect supports community groups")}</h2>
      <div class="supported-groups-grid">
        #{cards}
      </div>
    </section>
  HTML
end

def infographic_html(page)
  infographic = page[:infographic]
  return "" unless infographic

  steps = Array(infographic[:steps])
  body = infographic[:body].to_s.strip
  body_html = body.empty? ? "" : %(<p>#{esc(body)}</p>)
  step_cards = steps.each_with_index.map do |(title, body), index|
    step_body_html = if body.is_a?(Array)
      items = body.map { |item| item.to_s.strip }.reject(&:empty?)
      items.empty? ? "" : %(<ul>#{items.map { |item| %(<li>#{esc(item)}</li>) }.join}</ul>)
    else
      step_body = body.to_s.strip
      step_body.empty? ? "" : %(<p>#{esc(step_body)}</p>)
    end
    %(
      <article class="infographic-step">
        <span class="section-number">#{format("%02d", index + 1)}</span>
        <h3>#{esc(title)}</h3>
        #{step_body_html}
      </article>
    )
  end.join

  <<~HTML
    <section class="infographic-band" aria-labelledby="infographic-heading">
      <div class="infographic-copy">
        <h2 id="infographic-heading">#{esc(infographic[:title])}</h2>
        #{body_html}
      </div>
      #{steps.empty? ? "" : %(<div class="infographic-grid">#{step_cards}</div>)}
    </section>
  HTML
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
        <h2 id="daily-rhythm-heading">From zero fee microsavings to capital accumulation and credit access</h2>
      </div>
      <div class="journey-rail" aria-label="Collect contribution journey">
        <article><span>01</span><strong>Save</strong><p>Group Savings via the app or USSD.</p></article>
        <article><span>02</span><strong>Build a record</strong><p>Build savings history and capital accumulations.</p></article>
        <article><span>03</span><strong>Prepare</strong><p>Get guidance on loan requirements and support to credit readiness.</p></article>
        <article><span>04</span><strong>Access credit</strong><p>Use group savings as collateral for loan application.</p></article>
        <article><span>05</span><strong>Protect</strong><p>Access suitable insurance for income, savings protection.</p></article>
        <article><span>06</span><strong>Grow</strong><p>Use capital for business, productive assets or community goals.</p></article>
      </div>
    </section>

    <section class="original-story light" aria-labelledby="ibimina-heading">
      <div class="story-copy">
        <h2 id="ibimina-heading">Everything Collect brings together</h2>
      </div>
      <div class="story-grid four home-product-grid">
        <article><strong>Group Savings</strong><span>Digitise group savings via zero-fee microsavings and grow accumulated group capital.</span><a href="/group-savings/">Explore Group Savings</a></article>
        <article><strong>Diaspora Group Savings</strong><span>Save together through a host-country partner bank and build collateral, access credit and capital to invest home.</span><a href="/diaspora/">Explore Diaspora</a></article>
        <article><strong>Credit Readiness</strong><span>Move from a loan inquiry to a complete, structured, bank-review-ready loan application file.</span><a href="/craas/">Explore CRaaS</a></article>
        <article><strong>Insurance</strong><span>Access insurance designed around daily and irregular income patterns to protect income and savings.</span><a href="/insurance/">Explore Insurance</a></article>
      </div>
    </section>

    <section class="original-story mint" aria-labelledby="diaspora-heading">
      <div class="story-copy">
        <h2 id="diaspora-heading">Built for people who earn, save, and borrow differently</h2>
      </div>
      <div class="story-grid four">
        <article><strong>Ibimina</strong><span>Rotating and accumulating groups that need readable activity records.</span></article>
        <article><strong>Daily earners</strong><span>People saving in small amounts around daily or irregular income.</span></article>
        <article><strong>MSMEs</strong><span>Helps businesses understand requirements, coordinate specialist services and prepare bank review-ready loan file.</span></article>
        <article><strong>Diaspora</strong><span>Diaspora group savings at host-country partner banks. Collateral pledged and Credit access.</span></article>
      </div>
    </section>

    <section class="original-story info" aria-labelledby="credit-boundary-heading">
      <div class="story-copy">
        <h2 id="credit-boundary-heading">Payments work. Financial progress still does not.</h2>
      </div>
      <div class="story-grid problem-grid">
        <article><strong>Daily-income mismatch</strong><span>90% of employment is informal, yet finance is designed around monthly salaries and lump-sum payments.</span></article>
        <article><strong>Invisible group savings</strong><span>52% of adults save through ibimina, but many records remain manual and cannot support formal credit.</span></article>
        <article><strong>Credit-readiness gap</strong><span>Rwanda has extensive payment agents, but no scalable last-mile service helping MSMEs prepare complete, bank-ready loan files.</span></article>
        <article><strong>Microinsurance gap</strong><span>Premiums and claims processes rarely match small, irregular daily incomes.</span></article>
        <article><strong>Diaspora credit barriers</strong><span>Mobility risk, thin credit histories, unstable employment and insufficient acceptable collateral restrict access to affordable host-country loans.</span></article>
      </div>
    </section>
  HTML
end

def group_savings_page_html
  how_steps = [
    ["Create the group", "Define its purpose, leadership, rules and contribution schedule."],
    ["Invite members", "Onboard members individually through the app or supported assisted channels."],
    ["Contribute and get proof", "Members save through the app, mobile money or USSD, and receive confirmation instantly."],
    ["Build financial history", "Contribution consistency becomes a verified record."],
    ["Connect to partners", "Eligible groups may access partner-led credit, insurance or purpose-based finance."]
  ]
  features = [
    ["Transparent group ledger", "Every recognised contribution is allocated to the correct member and group."],
    ["Member statements", "Members can view their balances and contribution history without depending solely on the group treasurer."],
    ["Flexible contribution schedules", "Save daily, weekly, monthly or according to the group's own rules."],
    ["Group roles and approvals", "Set leaders, signatories, reviewers and maker-checker controls."],
    ["Purpose-based goals", "Save toward insurance, school fees, business assets, property, agriculture, taxes or green mobility."],
    ["Basic-phone access", "Supported USSD and SMS journeys make participation possible beyond smartphone users."],
    ["Regulated fund handling", "Funds are held by regulated financial-service partners, not on Collect's own balance sheet."],
    ["Credit-readiness record", "Contribution discipline can become part of a stronger partner-lender application."]
  ]
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
        #{how_steps.each_with_index.map { |(title, body), index| %(<article><span>#{format("%02d", index + 1)}</span><strong>#{esc(title)}</strong><p>#{esc(body)}</p></article>) }.join}
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
        <p>Traditional rotational groups help members access a periodic lump sum, but the group capital is repeatedly distributed and depleted. Collect allows groups to add an accumulating model in which savings remain visible and can support shared goals, collateral arrangements and longer-term investment.</p>
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

def diaspora_collect_changes_html
  without_collect = [
    "Individual borrower assessed without group support",
    "Informal savings circle",
    "Limited transaction evidence",
    "Savings held outside the lending bank",
    "No controlled collateral arrangement"
  ]
  with_collect = [
    "Verified contribution history",
    "Savings held by the potential lender",
    "Agreed collateral structure",
    "Group rules and accountability",
    "Structured Rwanda investment support"
  ]

  <<~HTML
    <section class="diaspora-change-section" aria-labelledby="diaspora-change-heading">
      <div class="story-copy">
        <h2 id="diaspora-change-heading">What Collect changes</h2>
      </div>
      <div class="change-compare-grid" aria-label="What Collect changes for diaspora groups">
        <article>
          <h3>Without Collect</h3>
          <ul>
            #{without_collect.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
        <article>
          <h3>With Collect and the partner bank</h3>
          <ul>
            #{with_collect.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
      </div>
    </section>
  HTML
end

def insurance_page_html
  how_steps = [
    "Members see an eligible product in Collect.",
    "Product terms, exclusions, price and insurer are displayed.",
    "Premium is collected daily, or through a flexible schedule.",
    "The member receives digital proof of cover.",
    "Collect supports claim notification and evidence collection.",
    "The insurer makes the claims decision and pays the valid claim."
  ]

  <<~HTML
    <section class="insurance-work-section" aria-labelledby="insurance-work-heading">
      <div class="story-copy">
        <h2 id="insurance-work-heading">How it works</h2>
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
        <p>A partner bank may provide purpose-locked premium financing. Repayment can then be aligned with the member's normal micro-contribution pattern.</p>
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
    "Cleaner application pipeline",
    "Less administrative rework",
    "More consistent files",
    "Faster pre-credit preparation",
    "Better productivity",
    "Improved applicant experience"
  ]

  <<~HTML
    <section class="craas-specialist-section" aria-labelledby="craas-specialist-heading">
      <div class="story-copy">
        <h2 id="craas-specialist-heading">Specialist support services</h2>
      </div>
      <div class="craas-service-grid" aria-label="Specialist support services">
        #{specialist_services.map { |item| %(<article><strong>#{esc(item)}</strong></article>) }.join}
      </div>
    </section>

    <section class="craas-bank-section" aria-labelledby="craas-bank-heading">
      <div class="story-copy">
        <h2 id="craas-bank-heading">What the bank receives</h2>
      </div>
      <div class="craas-list-panel">
        <ul>
          #{bank_receives.map { |item| %(<li>#{esc(item)}</li>) }.join}
        </ul>
      </div>
    </section>

    <section class="craas-benefits-section" aria-labelledby="craas-benefits-heading">
      <div class="story-copy">
        <h2 id="craas-benefits-heading">Benefits</h2>
      </div>
      <div class="craas-benefit-grid">
        <article>
          <h3>For businesses</h3>
          <ul>
            #{business_benefits.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
        <article>
          <h3>For banks</h3>
          <ul>
            #{bank_benefits.map { |item| %(<li>#{esc(item)}</li>) }.join}
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
    "Daily and periodic microsavings",
    "Mobile app and USSD access",
    "Member and group accounts",
    "Purpose-based savings",
    "Automated ledger reconciliation",
    "National community mobilisation"
  ]

  daily_income_lending = [
    "Daily or periodic micro-repayments",
    "Up to 365 repayment data points per borrower annually",
    "Automated split between repayment and savings",
    "Reduced branch and collection-agent dependence",
    "Earlier visibility of repayment stress",
    "More accurate portfolio monitoring"
  ]

  group_diaspora_lending = [
    "Bank-held savings collateral",
    "Group accountability",
    "Contribution history",
    "Purpose-controlled disbursement",
    "Daily repayment visibility",
    "Credit-life or income-protection cover"
  ]

  msme_origination = [
    "Initial eligibility and requirement mapping",
    "Business-document and financial-record checklist",
    "Contribution, savings and repayment-history packaging",
    "Gap closure before formal bank review",
    "Cleaner applicant summary for credit teams",
    "Less rework between customer, adviser and bank"
  ]

  collect_provides = [
    "USSD-enabled microsavings",
    "Group creation and administration",
    "Member and group ledgers",
    "Transaction reconciliation",
    "Statements and contribution records",
    "Savings mobilisation support",
    "Loan application preparation",
    "Credit Readiness guide and support",
    "Daily loan micro-repayment",
    "Group savings collateral workflow",
    "Diaspora group-savings infrastructure"
  ]

  bank_provides = [
    "Regulated savings accounts and account operations",
    "KYC, KYB and AML/CFT controls",
    "Account and product approval",
    "Collateral documentation",
    "Credit assessment and pricing",
    "Final loan approval",
    "Loan disbursement",
    "Collections and recovery",
    "Regulatory reporting"
  ]

  bank_value = [
    "Growth in low-cost deposits",
    "New retail and MSME customers",
    "Increased loan origination",
    "Net interest income",
    "Reduced pre-credit administration",
    "Lower application rework",
    "Daily repayment visibility",
    "Insurance-premium financing",
    "Green and productive-asset finance",
    "Purpose-controlled loan disbursement",
    "Stronger customer retention",
    "New diaspora banking relationships"
  ]

  <<~HTML
    <section class="partner-opportunity-section" aria-labelledby="partner-opportunity-heading">
      <div class="story-copy">
        <h2 id="partner-opportunity-heading">A large savings and credit market already exists, mostly outside formal banking.</h2>
      </div>
      <div class="partner-metric-grid" aria-label="Banking opportunity metrics">
        #{opportunity_metrics.map { |value, label| %(<article><strong>#{esc(value)}</strong><span>#{esc(label)}</span></article>) }.join}
      </div>
    </section>

    <section class="partner-market-section" aria-labelledby="partner-growth-heading">
      <div class="story-copy">
        <h2 id="partner-growth-heading">Growth Engines for Banks</h2>
      </div>
      <div class="partner-engine-grid" aria-label="Growth engines for partner banks">
        <article>
          <strong>Low-cost deposit mobilisation</strong>
          <p>Reach millions of informal savers through existing ibimina, cooperatives and community networks.</p>
          <ul>
            #{deposit_mobilisation.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
        <article>
          <strong>Daily-income lending and repayment</strong>
          <p>Monthly repayment structures often do not match informal-sector cash flow. Collect helps banks design loans around how customers actually earn rather than forcing daily earners into a monthly salary model.</p>
          <ul>
            #{daily_income_lending.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
        <article>
          <strong>Group-backed and diaspora lending</strong>
          <p>Verified group savings can provide an additional risk-control layer for eligible lending. For diaspora banking, group savings can remain with the regulated country partner bank, with an agreed portion pledged for loans to eligible members subject to the bank's credit policy and approval.</p>
          <ul>
            #{group_diaspora_lending.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
          <p>The addressable Rwandan diaspora market is 300,000+ people across Europe, the United Kingdom, North America and other corridors. Collect's diaspora proposition is a regulated-country-bank savings and secured-credit model.</p>
        </article>
        <article>
          <strong>Stronger MSME credit origination</strong>
          <p>Collect's Credit Readiness-as-a-Service prepares applicants before formal bank review, helping credit teams receive more complete, structured and decision-ready MSME files.</p>
          <ul>
            #{msme_origination.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
      </div>
    </section>

    <section class="partner-operating-section" aria-labelledby="partner-operating-heading">
      <div class="story-copy">
        <h2 id="partner-operating-heading">What each side brings</h2>
      </div>
      <div class="partner-operating-grid">
        <article>
          <h3>What Collect Provides</h3>
          <ul>
            #{collect_provides.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
        <article>
          <h3>What the Partner Bank Provides</h3>
          <ul>
            #{bank_provides.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
        <article>
          <h3>The Commercial Value to Banks</h3>
          <p>Partner banks can generate value through:</p>
          <ul>
            #{bank_value.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
      </div>
    </section>
  HTML
end

def hero_visual_html(page)
  case page[:path]
  when "/group-savings/"
    <<~HTML
      <div class="hero-widget ledger-widget phone-widget" aria-label="Group savings ledger preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Statement</strong>
              <button class="download-button" aria-label="Export ledger statement"><i aria-hidden="true"></i></button>
            </div>
            <section class="statement-card">
              <strong>RayonSport Fan Club</strong>
              <small>June 2026 contribution ledger</small>
            </section>
            <div class="ledger-summary">
              <div><span>Collected</span><strong>RWF 18,000</strong></div>
              <div><span>Pending</span><strong>1 member</strong></div>
            </div>
            <div class="statement-table" role="table" aria-label="RayonSport Fan Club contribution statement">
              <div class="statement-head" role="row"><span>Member</span><span>Amount</span><span>Status</span></div>
              <div class="ledger-row" role="row"><span class="ledger-member" role="cell"><i class="profile-icon" aria-hidden="true"></i>482917</span><strong role="cell">RWF 6,000</strong><em role="cell">Paid</em></div>
              <div class="ledger-row" role="row"><span class="ledger-member" role="cell"><i class="profile-icon" aria-hidden="true"></i>739204</span><strong role="cell">RWF 6,000</strong><em role="cell">Paid</em></div>
              <div class="ledger-row pending" role="row"><span class="ledger-member" role="cell"><i class="profile-icon" aria-hidden="true"></i>156883</span><strong role="cell">RWF 6,000</strong><em role="cell">Pending</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Ledger</span><span>Members</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/diaspora/"
    <<~HTML
      <div class="hero-widget diaspora-widget phone-widget" aria-label="Diaspora savings app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Diaspora</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="diaspora-card">
              <strong>Paris Saving Group</strong>
            </section>
            <div class="app-segments" aria-label="Diaspora workflow tabs">
              <span class="active">Records</span><span>Members</span><span>Support</span>
            </div>
            <div class="app-list" role="list" aria-label="Member contributions">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>482917</strong><small>Member contribution</small></span><em>Saved</em></div>
              <div role="listitem"><i class="app-dot ready"></i><span><strong>739204</strong><small>Member contribution</small></span><em>Saved</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>156883</strong><small>Member contribution</small></span><em>Pending</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Diaspora</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/insurance/", "/protection/"
    <<~HTML
      <div class="hero-widget protection-widget phone-widget" aria-label="Protection support app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Protection</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="protection-card">
              <strong>Insurance-related records</strong>
            </section>
            <div class="app-segments" aria-label="Protection workflow tabs">
              <span class="active">Request</span><span>Records</span><span>Provider</span>
            </div>
            <div class="app-list" role="list" aria-label="Insurance products">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Income Protection</strong><small>Short-term income interruption support</small></span><em>Eligible</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Credit Life Protection</strong><small>Partner-loan balance protection</small></span><em>Eligible</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Credit Repayment Protection</strong><small>Repayment support after income interruption</small></span><em>Eligible</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Protection</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/craas/", "/credit-readiness/"
    <<~HTML
      <div class="hero-widget file-widget phone-widget" aria-label="Credit-readiness app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Readiness</strong>
              <button class="download-button" aria-label="Export readiness file"><i aria-hidden="true"></i></button>
            </div>
            <section class="readiness-card">
              <strong>Customer support file</strong>
            </section>
            <div class="app-segments" aria-label="Readiness file tabs">
              <span class="active">File</span><span>History</span><span>Notes</span>
            </div>
            <div class="app-list" role="list" aria-label="MSME credit-readiness support services">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Accounting</strong><small>Financial records and statements</small></span><em>Support</em></div>
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Business-plan</strong><small>Loan purpose and repayment plan</small></span><em>Support</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Tax advisory</strong><small>Tax records and compliance guidance</small></span><em>Support</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Notaries</strong><small>Document certification support</small></span><em>Support</em></div>
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Legal services</strong><small>Contracts and legal documents</small></span><em>Support</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Insurers</strong><small>Protection and policy support</small></span><em>Support</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">File</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/community-groups/"
    <<~HTML
      <div class="hero-widget community-widget phone-widget" aria-label="Community group app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Community</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="community-card">
              <strong>Community savings group</strong>
            </section>
            <div class="app-segments" aria-label="Community group tabs">
              <span class="active">Activity</span><span>Members</span><span>Records</span>
            </div>
            <div class="member-strip" aria-label="Member preview">
              <i></i><i></i><i></i><i></i><span>Member records visible</span>
            </div>
            <div class="app-list" role="list" aria-label="Wedding group contributions">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>482917</strong><small>Wedding group contribution</small></span><em>RWF 10,000</em></div>
              <div role="listitem"><i class="app-dot ready"></i><span><strong>739204</strong><small>Wedding group contribution</small></span><em>RWF 10,000</em></div>
              <div role="listitem"><i class="app-dot ready"></i><span><strong>156883</strong><small>Wedding group contribution</small></span><em>RWF 5,000</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Groups</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/our-partners/", "/partners/"
    <<~HTML
      <div class="hero-widget partner-widget phone-widget" aria-label="Partner workflow app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Partners</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="partner-card">
              <strong>Records before review</strong>
              <small>Groups keep records. Providers review under their own rules.</small>
            </section>
            <div class="workflow-stack" aria-label="Partner workflow preview">
              <div><i class="app-dot ready"></i><span><strong>Groups</strong><small>Use Collect to organize records</small></span></div>
              <b></b>
              <div><i class="app-dot"></i><span><strong>Records</strong><small>Contribution history and request notes</small></span></div>
              <b></b>
              <div><i class="app-dot support"></i><span><strong>Providers</strong><small>Review and decide under their own rules</small></span></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Partners</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/trust/", "/security/"
    <<~HTML
      <div class="hero-widget trust-widget phone-widget" aria-label="Trust app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Trust</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="trust-card">
              <span>Trust center</span>
              <strong>Clear records and support paths</strong>
              <small>Deletion routes, careful public claims and WhatsApp support.</small>
            </section>
            <div class="app-list" role="list" aria-label="Trust checklist">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Clear records</strong><small>Readable contribution and request history</small></span><em>Active</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Deletion routes</strong><small>Account and data deletion support</small></span><em>Available</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Public claims</strong><small>Only approved wording goes public</small></span><em>Checked</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Trust</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/privacy/"
    <<~HTML
      <div class="hero-widget policy-widget phone-widget" aria-label="Privacy app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Privacy</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="policy-card"><span>Privacy controls</span><strong>Manage data requests</strong><small>Access, correction, account deletion and data deletion routes.</small></section>
            <div class="app-list" role="list" aria-label="Privacy controls">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Access</strong><small>Ask about profile and service data</small></span><em>Open</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Correction</strong><small>Request correction support</small></span><em>Support</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Deletion</strong><small>Account and data deletion routes</small></span><em>Available</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview"><span>Home</span><span class="active">Privacy</span><span>Support</span></nav>
          </div>
        </div>
      </div>
    HTML
  when "/terms/"
    <<~HTML
      <div class="hero-widget terms-widget phone-widget" aria-label="Terms app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Terms</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="terms-card"><span>Service terms</span><strong>Use Collect clearly</strong><small>Customer responsibilities, group rules and provider decision boundaries.</small></section>
            <div class="app-list" role="list" aria-label="Terms summary">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Customer responsibilities</strong><small>Use accurate information</small></span><em>Read</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Group rules</strong><small>Groups manage their own rules</small></span><em>Group</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Provider decisions</strong><small>Providers decide under their own rules</small></span><em>Provider</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview"><span>Home</span><span class="active">Terms</span><span>Support</span></nav>
          </div>
        </div>
      </div>
    HTML
  when "/account-deletion/"
    <<~HTML
      <div class="hero-widget deletion-widget phone-widget" aria-label="Account deletion app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Delete Account</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="deletion-card"><span>Account deletion</span><strong>Request support</strong><small>Use WhatsApp support to request account deletion and status updates.</small></section>
            <div class="app-list" role="list" aria-label="Account deletion steps">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Request</strong><small>Start deletion support</small></span><em>Step 1</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Verify account</strong><small>Confirm the account request</small></span><em>Step 2</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Confirm status</strong><small>Receive support follow-up</small></span><em>Step 3</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview"><span>Home</span><span class="active">Account</span><span>Support</span></nav>
          </div>
        </div>
      </div>
    HTML
  when "/data-deletion/"
    <<~HTML
      <div class="hero-widget data-widget phone-widget" aria-label="Data deletion app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Delete Data</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="data-card"><span>Data deletion</span><strong>Request data support</strong><small>Profile details, support messages and service data are handled through support.</small></section>
            <div class="app-list" role="list" aria-label="Data deletion scope">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Profile details</strong><small>Profile-related deletion request</small></span><em>Scope</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Support messages</strong><small>Support request history</small></span><em>Review</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Retention rules</strong><small>Limited retention may apply</small></span><em>Policy</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview"><span>Home</span><span class="active">Data</span><span>Support</span></nav>
          </div>
        </div>
      </div>
    HTML
  else
    <<~HTML
      <div class="hero-widget home-widget phone-widget" aria-label="Collect app home screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Open menu"><i aria-hidden="true"></i></button>
              <strong>Collect</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="home-dashboard-card">
              <strong>RayonSport Fan Club</strong>
              <div class="dashboard-progress" role="progressbar" aria-label="Group contribution progress" aria-valuemin="0" aria-valuemax="100" aria-valuenow="72"><i></i></div>
              <div class="dashboard-stats" aria-label="Group summary">
                <span><b>RWF 18,000</b><small>Collected</small></span>
                <span><b>3</b><small>Paid</small></span>
              </div>
            </section>
            <div class="quick-actions" aria-label="Collect app quick actions">
              <button type="button"><i class="quick-save" aria-hidden="true"></i><span>Save</span></button>
              <button type="button"><i class="quick-ledger" aria-hidden="true"></i><span>Ledger</span></button>
              <button type="button"><i class="quick-export" aria-hidden="true"></i><span>Readiness</span></button>
            </div>
            <div class="home-record-list" role="list" aria-label="Recent contribution records">
              <div role="listitem"><i class="profile-icon" aria-hidden="true"></i><span><strong>482917</strong><small>Daily saving received</small></span><em>Paid</em></div>
              <div role="listitem"><i class="profile-icon" aria-hidden="true"></i><span><strong>739204</strong><small>Readiness file updated</small></span><em>Paid</em></div>
              <div role="listitem"><i class="profile-icon" aria-hidden="true"></i><span><strong>156883</strong><small>Protection follow-up</small></span><em>Paid</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span class="active">Home</span><span>Groups</span><span>Records</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  end
end

def page_html(page, current_path: page[:path])
  <<~HTML
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{esc(page[:title])}</title>
      <meta name="description" content="#{esc(page[:description])}">
      <meta name="theme-color" content="#8885F0">
      <link rel="canonical" href="#{page_url(current_path)}">
      #{alternate_links(current_path)}
      <link rel="icon" href="/icons/collect.png" type="image/png">
      <link rel="manifest" href="/manifest.json">
      <meta property="og:type" content="website">
      <meta property="og:locale" content="en_US">
      <meta property="og:url" content="#{page_url(current_path)}">
      <meta property="og:title" content="#{esc(page[:title])}">
      <meta property="og:description" content="#{esc(page[:description])}">
      <meta property="og:image" content="#{PUBLIC_URL}/assets/brand/collect_runtime/media/group-momentum.png">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="#{esc(page[:title])}">
      <meta name="twitter:description" content="#{esc(page[:description])}">
      <link rel="stylesheet" href="/styles.css?v=#{ASSET_VERSION}">
      <link rel="stylesheet" href="/sections.css?v=#{ASSET_VERSION}">
      <script type="application/ld+json">#{json_ld(page)}</script>
    </head>
    <body>
      <a class="skip-link" href="#content">Skip to content</a>
      <header class="site-header">
        <a class="brand" href="/">
          <img src="/icons/collect.png" alt="" width="42" height="42">
          <span><strong>Collect</strong><small>by IKANISA</small></span>
        </a>
        <button class="menu-button" type="button" data-menu-button aria-expanded="false" aria-controls="site-nav">Menu</button>
        <nav id="site-nav" class="site-nav" data-site-nav aria-label="Main navigation">
          #{nav_html(current_path)}
        </nav>
        #{language_switcher_html(current_path)}
        <div class="header-actions">
          #{cta_links_html(current_path, page, surface: :header)}
        </div>
      </header>

      <main id="content">
        <section class="hero">
          <div class="hero-copy">
            #{page[:eyebrow] ? %(<p class="hero-eyebrow">#{esc(page[:eyebrow])}</p>) : ""}
            <h1>#{esc(page[:h1])}</h1>
            <p class="hero-intro">#{esc(page[:intro])}</p>
            <div class="hero-actions">
              #{cta_links_html(current_path, page, surface: :hero)}
            </div>
            #{app_availability_note_html(current_path, page)}
          </div>
          <div class="hero-device">
            #{hero_visual_html(page)}
          </div>
        </section>

        #{current_path == "/" ? "" : infographic_html(page)}

        #{current_path == "/" ? home_credit_readiness_html : ""}

        #{current_path == "/group-savings/" ? group_savings_page_html : ""}

        #{legal_page_html(page)}

        #{content_grid_html(page, current_path)}

        #{supported_groups_html(page)}

        #{current_path == "/our-partners/" || current_path == "/partners/" ? partner_page_html : ""}

        #{current_path == "/craas/" || current_path == "/credit-readiness/" ? craas_page_html : ""}

        #{current_path == "/diaspora/" ? diaspora_collect_changes_html : ""}

        #{current_path == "/insurance/" ? insurance_page_html : ""}

        #{current_path == "/" ? original_home_sections_html : ""}

        #{proof_section_html(current_path)}

        #{faq_section_html(current_path)}

        <section id="start" class="start-section" aria-labelledby="start-heading">
          <div>
            <h2 id="start-heading">#{page[:start_heading] ? esc(page[:start_heading]) : "Download <span class=\"brand-word\">Collect</span> or Get in Touch"}</h2>
            <div class="start-actions">
              #{cta_links_html(current_path, page, surface: :start)}
            </div>
            #{app_availability_note_html(current_path, page)}
          </div>
        </section>

      </main>

      #{site_footer_html}
      <script src="/site.js?v=#{ASSET_VERSION}" defer></script>
    </body>
    </html>
  HTML
end

def stylesheet
  <<~CSS
    :root {
      color-scheme: dark light;
      --paper: #faf8f5;
      --ink: #252044;
      --muted: #5f5a76;
      --night: #050510;
      --panel: #12111c;
      --line: rgba(250, 248, 245, .14);
      --periwinkle: #5f5ce6;
      --mint: #3cd070;
      --rose: #d38b96;
      --urgent: #ff5e43;
      --white: #fffdfb;
      --focus: #a7a2ff;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body { margin: 0; background: var(--night); color: var(--paper); letter-spacing: 0; }
    a { color: inherit; }
    a:focus-visible, button:focus-visible, input:focus-visible, select:focus-visible { outline: 3px solid var(--focus); outline-offset: 4px; }
    .skip-link { position: absolute; left: 16px; top: -80px; z-index: 10; background: var(--paper); color: var(--ink); padding: 10px 12px; border-radius: 8px; }
    .skip-link:focus { top: 16px; }
    .site-header { min-height: 72px; display: flex; align-items: center; gap: 16px; padding: 18px clamp(20px, 4vw, 48px); position: sticky; top: 0; z-index: 5; background: rgba(5, 5, 16, .86); backdrop-filter: blur(18px); border-bottom: 1px solid rgba(250,248,245,.08); }
    .brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; min-width: max-content; }
    .brand img { border-radius: 10px; }
    .brand strong, .brand small { display: block; line-height: 1; }
    .brand strong { font-size: 19px; font-weight: 900; }
    .brand small { color: rgba(250,248,245,.7); font-weight: 800; margin-top: 3px; }
    .site-nav { display: flex; gap: 2px; align-items: center; flex: 1; justify-content: center; min-width: 0; }
    .nav-link { text-decoration: none; font-size: 12px; font-weight: 850; color: rgba(250,248,245,.72); padding: 10px 8px; border-radius: 10px; white-space: nowrap; }
    .nav-link:hover, .nav-link.active { color: var(--paper); background: rgba(250,248,245,.09); }
    .language-switcher { display: inline-flex; align-items: center; gap: 4px; padding: 4px; border: 1px solid rgba(250,248,245,.14); border-radius: 12px; background: rgba(250,248,245,.06); }
    .language-switcher a { min-width: 34px; min-height: 34px; display: inline-grid; place-items: center; border-radius: 9px; text-decoration: none; color: rgba(250,248,245,.78); font-size: 12px; font-weight: 950; }
    .language-switcher a:hover { background: rgba(250,248,245,.12); color: var(--paper); }
    .header-actions, .hero-actions { display: flex; gap: 10px; flex-wrap: wrap; }
    .header-actions { flex: 0 0 auto; flex-wrap: nowrap; gap: 8px; }
    .button, button { min-height: 44px; border: 1px solid rgba(250,248,245,.18); border-radius: 12px; display: inline-flex; align-items: center; justify-content: center; padding: 12px 18px; text-decoration: none; font-size: 14px; font-weight: 900; cursor: pointer; }
    .button { white-space: nowrap; }
    .header-actions .button { padding: 11px 14px; font-size: 13px; }
    .button.primary, .button.secondary { background: var(--periwinkle); color: white; border-color: var(--periwinkle); box-shadow: 0 14px 34px rgba(136,133,240,.24); }
    .button.ghost { background: transparent; color: var(--paper); }
    .button.cta-app { background: var(--periwinkle); color: #fffdfb; border-color: var(--periwinkle); box-shadow: 0 14px 34px rgba(136,133,240,.28); }
    .button.cta-group { background: var(--mint); color: #050510; border-color: var(--mint); box-shadow: 0 14px 34px rgba(60,208,112,.22); }
    .button.cta-touch { background: var(--rose); color: var(--night); border-color: var(--rose); box-shadow: 0 14px 34px rgba(211,139,150,.22); }
    .menu-button { display: none; background: rgba(250,248,245,.08); color: var(--paper); }
    .hero { min-height: calc(100svh - 72px); display: grid; grid-template-columns: minmax(0, 1.02fr) minmax(320px, .78fr); gap: clamp(28px, 5vw, 72px); align-items: center; padding: clamp(48px, 8vw, 104px) clamp(20px, 5vw, 64px) 64px; background: radial-gradient(circle at 72% 18%, rgba(136,133,240,.28), transparent 32%), radial-gradient(circle at 18% 80%, rgba(60,208,112,.16), transparent 32%), #050510; }
    .section-kicker { color: var(--mint); font-size: 13px; font-weight: 900; text-transform: uppercase; letter-spacing: .08em; margin: 0 0 18px; }
    .hero-eyebrow { color: var(--mint); font-size: 13px; font-weight: 950; text-transform: uppercase; letter-spacing: .12em; margin: 0 0 18px; }
    section { scroll-margin-top: 96px; }
    h1 { font-size: clamp(44px, 8vw, 96px); line-height: .94; margin: 0; max-width: 920px; font-weight: 950; }
    .hero-intro { color: rgba(250,248,245,.74); font-size: clamp(19px, 2.1vw, 25px); line-height: 1.38; max-width: 760px; margin: 26px 0 30px; }
    .app-availability { margin: 14px 0 0; color: rgba(250,248,245,.68); font-size: .88rem; font-weight: 800; line-height: 1.35; }
    .hero-device { position: relative; min-height: 520px; display: grid; place-items: center; }
    .hero-widget { width: min(94%, 450px); min-height: 430px; border-radius: 34px; padding: 28px; color: var(--paper); border: 1px solid rgba(250,248,245,.18); background: linear-gradient(145deg, rgba(250,248,245,.11), rgba(136,133,240,.16)); box-shadow: 0 34px 90px rgba(0,0,0,.42); display: grid; gap: 16px; align-content: center; overflow: hidden; }
    .hero-widget strong, .hero-widget span, .hero-widget em, .hero-widget small { overflow-wrap: anywhere; }
    .widget-topline span, .widget-note, .hero-widget small, .hero-widget > span, .hero-widget li { color: rgba(250,248,245,.7); }
    .widget-topline strong { display: block; font-size: clamp(28px, 4vw, 42px); line-height: 1; margin-top: 8px; }
    .widget-note { font-weight: 850; line-height: 1.35; }
    .phone-widget { width: min(94%, 366px); min-height: 650px; border: 0; border-radius: 52px; padding: 0; background: transparent; box-shadow: none; display: block; overflow: visible; }
    .phone-shell { position: relative; width: 100%; height: 650px; min-height: 650px; border-radius: 52px; padding: 10px; background: linear-gradient(145deg, #060811, #171923); border: 1px solid rgba(250,248,245,.16); box-shadow: 0 38px 96px rgba(0,0,0,.55), inset 0 0 0 2px rgba(255,255,255,.05); }
    .phone-shell::before { content: ""; position: absolute; right: -4px; top: 124px; width: 4px; height: 66px; border-radius: 0 4px 4px 0; background: #272936; }
    .phone-notch { position: absolute; z-index: 2; top: 18px; left: 50%; width: 92px; height: 25px; transform: translateX(-50%); border-radius: 999px; background: #050510; box-shadow: inset 0 0 0 1px rgba(255,255,255,.06); }
    .phone-screen { height: 630px; min-height: 630px; border-radius: 42px; overflow: hidden; background: #f5f7fb; color: #17142c; display: flex; flex-direction: column; padding: 18px 16px 14px; border: 1px solid rgba(255,255,255,.08); }
    .phone-status { display: flex; align-items: center; justify-content: space-between; min-height: 24px; color: #18162c; font-size: 12px; font-weight: 950; padding: 0 4px; }
    .phone-status i { width: 52px; height: 5px; border-radius: 999px; background: transparent; }
    .phone-status b { width: 18px; height: 9px; border-radius: 3px; border: 1.5px solid #18162c; position: relative; }
    .phone-status b::after { content: ""; position: absolute; right: -4px; top: 2px; width: 2px; height: 3px; border-radius: 1px; background: #18162c; }
    .app-bar { display: grid; grid-template-columns: 38px minmax(0, 1fr) 38px; align-items: center; gap: 10px; min-height: 48px; margin-top: 8px; }
    .app-bar strong { text-align: center; font-size: 16px; line-height: 1; color: #17142c; }
    .back-button, .download-button, .chat-button { width: 38px; min-height: 38px; height: 38px; padding: 0; border-radius: 14px; background: white; border: 1px solid #e5e8f0; box-shadow: 0 8px 18px rgba(23,20,44,.08); }
    .back-button i, .download-button i, .chat-button i { display: block; width: 18px; height: 18px; margin: auto; position: relative; }
    .back-button i::before { content: ""; position: absolute; left: 5px; top: 3px; width: 10px; height: 10px; border-left: 3px solid #17142c; border-bottom: 3px solid #17142c; transform: rotate(45deg); border-radius: 1px; }
    .download-button i::before { content: ""; position: absolute; left: 7px; top: 1px; width: 4px; height: 10px; border-radius: 999px; background: #17142c; box-shadow: 0 7px 0 -2px #17142c; }
    .download-button i::after { content: ""; position: absolute; left: 3px; bottom: 1px; width: 12px; height: 7px; border-left: 3px solid #17142c; border-bottom: 3px solid #17142c; transform: rotate(-45deg); border-radius: 1px; }
    .chat-button i::before { content: ""; position: absolute; inset: 2px 1px 5px; border: 3px solid #17142c; border-radius: 999px; }
    .chat-button i::after { content: ""; position: absolute; left: 3px; bottom: 2px; width: 8px; height: 8px; border-left: 3px solid #17142c; border-bottom: 3px solid #17142c; transform: rotate(-18deg); border-radius: 1px; background: white; }
    .statement-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #231f58, #5865e8 68%, #28b86b); box-shadow: 0 18px 36px rgba(88,101,232,.25); }
    .statement-card span, .statement-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .statement-card strong { display: block; margin-top: 8px; font-size: 26px; line-height: 1.05; }
    .statement-card small { margin-top: 18px; font-size: 12px; }
    .diaspora-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #15352d, #23895b 58%, #6976f0); box-shadow: 0 18px 36px rgba(35,137,91,.22); }
    .diaspora-card span, .diaspora-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .diaspora-card strong { display: block; margin-top: 8px; font-size: 25px; line-height: 1.05; }
    .diaspora-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .protection-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #251d52, #6d63dc 58%, #f2b84b); box-shadow: 0 18px 36px rgba(109,99,220,.22); }
    .protection-card span, .protection-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .protection-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .protection-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .readiness-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #151833, #3846b8 58%, #2f9ec8); box-shadow: 0 18px 36px rgba(56,70,184,.22); }
    .readiness-card span, .readiness-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .readiness-card strong { display: block; margin-top: 8px; font-size: 25px; line-height: 1.05; }
    .readiness-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .community-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #102f45, #257ea4 58%, #28b86b); box-shadow: 0 18px 36px rgba(37,126,164,.22); }
    .community-card span, .community-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .community-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .community-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .partner-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #142f3a, #2f9ec8 58%, #6976f0); box-shadow: 0 18px 36px rgba(47,158,200,.22); }
    .partner-card span, .partner-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .partner-card strong { display: block; margin-top: 8px; font-size: 25px; line-height: 1.05; }
    .partner-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .trust-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #17142c, #23415f 58%, #28b86b); box-shadow: 0 18px 36px rgba(35,65,95,.22); }
    .trust-card span, .trust-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .trust-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .trust-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .policy-card, .terms-card, .deletion-card, .data-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; box-shadow: 0 18px 36px rgba(23,20,44,.18); }
    .policy-card { background: linear-gradient(145deg, #17324b, #2f9ec8 58%, #6976f0); }
    .terms-card { background: linear-gradient(145deg, #211b43, #6976f0 58%, #28b86b); }
    .deletion-card { background: linear-gradient(145deg, #331a2d, #b04b7a 58%, #6976f0); }
    .data-card { background: linear-gradient(145deg, #172d35, #23895b 58%, #2f9ec8); }
    .policy-card span, .policy-card small, .terms-card span, .terms-card small, .deletion-card span, .deletion-card small, .data-card span, .data-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .policy-card strong, .terms-card strong, .deletion-card strong, .data-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .policy-card small, .terms-card small, .deletion-card small, .data-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .home-app-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #211b43, #6976f0 55%, #28b86b); box-shadow: 0 18px 36px rgba(105,118,240,.24); }
    .home-app-card span, .home-app-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .home-app-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .home-app-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .home-dashboard-card { margin-top: 10px; padding: 18px; border-radius: 26px; color: white; background: linear-gradient(145deg, #17142c, #5b63df 58%, #27af67); box-shadow: 0 18px 36px rgba(91,99,223,.24); }
    .home-dashboard-card > span, .home-dashboard-card > small { display: block; color: rgba(255,255,255,.76); font-weight: 850; }
    .home-dashboard-card > strong { display: block; margin-top: 8px; font-size: 27px; line-height: 1.02; color: white; }
    .home-dashboard-card > small { margin-top: 10px; font-size: 12px; line-height: 1.35; }
    .dashboard-progress { height: 9px; margin: 18px 0 14px; border-radius: 999px; background: rgba(255,255,255,.22); overflow: hidden; }
    .dashboard-progress i { display: block; width: 72%; height: 100%; border-radius: inherit; background: linear-gradient(90deg, #3cd070, #fffdfb); }
    .dashboard-stats { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .dashboard-stats span { display: block; min-height: 62px; padding: 11px; border-radius: 17px; background: rgba(5,5,16,.22); border: 1px solid rgba(255,255,255,.16); }
    .dashboard-stats b, .dashboard-stats small { display: block; }
    .dashboard-stats b { color: white; font-size: 18px; line-height: 1.05; }
    .dashboard-stats small { margin-top: 6px; color: rgba(255,255,255,.72); font-size: 11px; font-weight: 850; }
    .quick-actions { display: grid; grid-template-columns: repeat(3, 1fr); gap: 9px; margin-top: 12px; }
    .quick-actions button { min-height: 72px; padding: 10px 8px; border-radius: 19px; border: 1px solid #e5e8f0; background: #fff; color: #17142c; box-shadow: 0 10px 20px rgba(23,20,44,.05); display: grid; gap: 7px; justify-items: center; font-size: 11px; line-height: 1; }
    .quick-actions i { width: 28px; height: 28px; border-radius: 999px; position: relative; background: #edf2ff; color: #6976f0; }
    .quick-actions i::before, .quick-actions i::after { content: ""; position: absolute; }
    .quick-save::before { left: 8px; top: 6px; width: 12px; height: 16px; border-radius: 8px 8px 5px 5px; background: currentColor; }
    .quick-save::after { left: 12px; top: 3px; width: 4px; height: 8px; border-radius: 999px; background: #3cd070; }
    .quick-ledger::before { left: 7px; top: 7px; width: 14px; height: 14px; border: 2px solid currentColor; border-radius: 4px; }
    .quick-ledger::after { left: 10px; top: 12px; width: 8px; height: 2px; background: currentColor; box-shadow: 0 5px 0 currentColor; }
    .quick-export::before { left: 12px; top: 6px; width: 4px; height: 13px; border-radius: 999px; background: currentColor; }
    .quick-export::after { left: 8px; top: 13px; width: 12px; height: 8px; border-left: 3px solid currentColor; border-bottom: 3px solid currentColor; transform: rotate(-45deg); border-radius: 1px; }
    .home-record-list { display: grid; gap: 10px; margin-top: 12px; }
    .home-record-list > div { display: grid; grid-template-columns: 28px minmax(0, 1fr) auto; gap: 10px; align-items: center; min-height: 62px; padding: 10px 12px; border: 1px solid #e5e8f0; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .home-record-list strong, .home-record-list small { display: block; }
    .home-record-list strong { color: #17142c; font-size: 14px; line-height: 1.1; }
    .home-record-list small { margin-top: 4px; color: #72738a; font-size: 11px; line-height: 1.25; }
    .home-record-list em { font-style: normal; color: #28b86b; font-size: 11px; font-weight: 950; }
    .app-segments { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; margin-top: 12px; padding: 5px; border-radius: 17px; background: #e9edf5; }
    .app-segments span { min-height: 32px; display: grid; place-items: center; border-radius: 13px; color: #77788c; font-size: 11px; font-weight: 950; }
    .app-segments span.active { color: #17142c; background: #ffffff; box-shadow: 0 6px 14px rgba(23,20,44,.08); }
    .app-list { display: grid; gap: 10px; margin-top: 12px; }
    .app-list > div { display: grid; grid-template-columns: 28px minmax(0, 1fr) auto; gap: 10px; align-items: center; min-height: 66px; padding: 10px 12px; border: 1px solid #e5e8f0; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .app-list strong, .app-list small { display: block; }
    .app-list strong { color: #17142c; font-size: 14px; line-height: 1.1; }
    .app-list small { margin-top: 4px; color: #72738a; font-size: 11px; line-height: 1.25; }
    .app-list em { font-style: normal; color: #6976f0; font-size: 11px; font-weight: 950; }
    .app-dot { width: 28px; height: 28px; border-radius: 999px; background: #edf2ff; border: 1px solid #d7ddf0; position: relative; }
    .app-dot::after { content: ""; position: absolute; inset: 8px; border-radius: 999px; background: #6976f0; }
    .app-dot.ready { background: #e7f8ee; border-color: #cdeed9; }
    .app-dot.ready::after { background: #28b86b; }
    .app-dot.support { background: #fff7df; border-color: #f3e4ad; }
    .app-dot.support::after { background: #f2b84b; }
    .member-strip { display: flex; align-items: center; gap: 0; margin-top: 12px; padding: 12px; border: 1px solid #e5e8f0; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .member-strip i { width: 30px; height: 30px; border-radius: 999px; border: 2px solid #fff; background: linear-gradient(145deg, #edf2ff, #6976f0); margin-left: -8px; }
    .member-strip i:first-child { margin-left: 0; background: linear-gradient(145deg, #e7f8ee, #28b86b); }
    .member-strip i:nth-child(3) { background: linear-gradient(145deg, #fff7df, #f2b84b); }
    .member-strip span { margin-left: 10px; color: #17142c; font-size: 12px; font-weight: 950; }
    .workflow-stack { display: grid; gap: 8px; margin-top: 14px; }
    .workflow-stack > div { display: grid; grid-template-columns: 28px minmax(0, 1fr); gap: 10px; align-items: center; min-height: 66px; padding: 10px 12px; border: 1px solid #e5e8f0; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .workflow-stack > b { display: block; width: 2px; height: 18px; margin-left: 25px; background: #d9dee9; border-radius: 999px; }
    .workflow-stack strong, .workflow-stack small { display: block; }
    .workflow-stack strong { color: #17142c; font-size: 14px; line-height: 1.1; }
    .workflow-stack small { margin-top: 4px; color: #72738a; font-size: 11px; line-height: 1.25; }
    .ledger-summary { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 12px; }
    .ledger-summary div { border: 1px solid #e5e8f0; border-radius: 18px; padding: 13px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .ledger-summary span, .ledger-summary strong { display: block; }
    .ledger-summary span, .statement-head span { color: #72738a; }
    .ledger-summary strong { margin-top: 5px; font-size: 18px; line-height: 1.05; color: #17142c; }
    .statement-table { margin-top: 12px; border: 1px solid #e5e8f0; border-radius: 22px; overflow: hidden; background: #ffffff; box-shadow: 0 12px 24px rgba(23,20,44,.06); }
    .statement-head, .ledger-widget .ledger-row { display: grid; grid-template-columns: minmax(112px, 1fr) auto auto; gap: 10px; align-items: center; }
    .statement-head { padding: 12px 14px; background: #eef2f8; font-size: 10px; font-weight: 950; text-transform: uppercase; }
    .ledger-row, .record-card, .protection-item, .file-widget li, .activity-list, .policy-widget:not(.phone-widget) span, .terms-widget:not(.phone-widget) span, .deletion-widget:not(.phone-widget) span, .data-widget:not(.phone-widget) span { border: 1px solid rgba(250,248,245,.14); border-radius: 16px; padding: 14px; background: rgba(5,5,16,.38); }
    .ledger-row { display: grid; grid-template-columns: minmax(0, 1fr) auto auto; gap: 10px; align-items: center; }
    .ledger-widget .ledger-row { border: 0; border-radius: 0; border-top: 1px solid #edf0f5; padding: 13px 14px; background: transparent; color: #17142c; }
    .ledger-member { display: inline-flex; align-items: center; gap: 9px; min-width: 0; font-weight: 950; }
    .profile-icon { position: relative; width: 28px; height: 28px; border-radius: 999px; flex: 0 0 auto; background: #edf2ff; border: 1px solid #d7ddf0; }
    .profile-icon::before { content: ""; position: absolute; left: 9px; top: 6px; width: 8px; height: 8px; border-radius: 999px; background: #6976f0; }
    .profile-icon::after { content: ""; position: absolute; left: 6px; bottom: 5px; width: 14px; height: 9px; border-radius: 999px 999px 6px 6px; background: #6976f0; }
    .ledger-row strong { font-size: 15px; }
    .ledger-widget .ledger-row strong { font-size: 12px; white-space: nowrap; color: #17142c; }
    .ledger-row em { font-style: normal; color: var(--mint); font-weight: 950; }
    .ledger-row.pending em { color: #f5c65b; }
    .phone-tabs { margin-top: auto; display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; padding: 10px 6px 4px; border-top: 1px solid #e7ebf2; }
    .phone-tabs span { display: grid; place-items: center; min-height: 34px; border-radius: 13px; color: #5f6178; font-size: 11px; font-weight: 950; }
    .phone-tabs span.active { color: #17142c; background: #edf2ff; }
    .corridor-map { display: grid; grid-template-columns: auto minmax(68px, 1fr) auto; align-items: center; gap: 10px; font-weight: 900; }
    .corridor-map i, .home-flow i, .partner-line { display: block; height: 2px; background: linear-gradient(90deg, var(--mint), var(--periwinkle)); border-radius: 999px; }
    .record-card strong, .record-card span, .protection-item strong, .protection-item span, .activity-list strong, .activity-list span { display: block; }
    .record-card span, .protection-item span, .activity-list span { margin-top: 6px; color: rgba(250,248,245,.68); line-height: 1.35; }
    .record-card.accent, .protection-item:nth-child(2), .policy-widget:not(.phone-widget) span:nth-of-type(2), .data-widget:not(.phone-widget) span:nth-of-type(2) { border-color: rgba(60,208,112,.36); }
    .protection-widget { grid-template-columns: 1fr; }
    .protection-item strong { font-size: 34px; line-height: 1; }
    .file-header strong, .policy-widget:not(.phone-widget) strong, .terms-widget:not(.phone-widget) strong, .deletion-widget:not(.phone-widget) strong, .data-widget:not(.phone-widget) strong, .trust-widget:not(.phone-widget) > strong { display: block; font-size: clamp(27px, 3vw, 38px); line-height: 1; }
    .file-header span { color: rgba(250,248,245,.68); font-weight: 850; }
    .file-widget ul { margin: 4px 0 0; padding: 0; list-style: none; display: grid; gap: 10px; }
    .file-widget li { color: var(--paper); font-weight: 850; display: flex; align-items: center; gap: 10px; }
    .file-widget li span { width: 12px; height: 12px; border-radius: 999px; background: var(--mint); flex: 0 0 auto; }
    .community-widget:not(.phone-widget) { grid-template-columns: .8fr 1fr; align-items: center; }
    .member-ring { width: 150px; height: 150px; border-radius: 999px; display: grid; place-items: center; align-content: center; border: 16px solid rgba(60,208,112,.52); box-shadow: inset 0 0 0 1px rgba(250,248,245,.18); }
    .member-ring span { font-size: 50px; line-height: .9; font-weight: 950; }
    .member-ring small { font-weight: 900; }
    .activity-list { display: grid; gap: 8px; }
    .activity-list span { margin-top: 0; }
    .policy-widget:not(.phone-widget), .terms-widget:not(.phone-widget), .deletion-widget:not(.phone-widget), .data-widget:not(.phone-widget) { align-content: stretch; }
    .partner-widget { grid-template-columns: 1fr; align-content: center; }
    .partner-node { min-height: 78px; display: grid; place-items: center; border-radius: 18px; border: 1px solid rgba(250,248,245,.16); background: rgba(250,248,245,.1); font-weight: 950; }
    .partner-line { width: 70%; justify-self: center; }
    .shield-mark { width: 118px; height: 118px; border-radius: 32px; display: grid; place-items: center; background: linear-gradient(145deg, rgba(60,208,112,.9), rgba(136,133,240,.9)); color: #050510; font-weight: 950; font-size: 32px; }
    .trust-widget { justify-items: start; }
    .trust-widget span { line-height: 1.4; }
    .policy-widget:not(.phone-widget), .terms-widget:not(.phone-widget), .deletion-widget:not(.phone-widget), .data-widget:not(.phone-widget) { grid-template-columns: 1fr 1fr; }
    .policy-widget:not(.phone-widget) strong, .terms-widget:not(.phone-widget) strong, .deletion-widget:not(.phone-widget) strong, .data-widget:not(.phone-widget) strong { grid-column: 1 / -1; }
    .policy-widget:not(.phone-widget) span, .terms-widget:not(.phone-widget) span, .deletion-widget:not(.phone-widget) span, .data-widget:not(.phone-widget) span { font-weight: 850; display: grid; align-items: center; min-height: 58px; }
    .home-flow { display: grid; grid-template-columns: auto minmax(34px, 1fr) auto minmax(34px, 1fr) auto; align-items: center; gap: 10px; }
    .home-flow span { font-weight: 950; }
    .infographic-band h2 { font-size: clamp(34px, 5vw, 64px); line-height: 1; margin: 0; }
    .infographic-band p { color: var(--muted); line-height: 1.55; }
    .infographic-band { display: grid; gap: 28px; padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #f2f4ff; color: var(--ink); }
    .infographic-copy { max-width: 860px; }
    .infographic-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; }
    .infographic-step { min-height: 150px; border: 1px solid #e1d9f0; border-radius: 18px; padding: 18px; background: rgba(255,253,251,.86); box-shadow: 0 14px 34px rgba(37,32,68,.06); }
    .infographic-step h3 { margin: 16px 0 8px; font-size: 19px; line-height: 1.12; }
    .infographic-step p { margin: 0; font-size: 14px; }
    .infographic-step ul { margin: 10px 0 0; padding-left: 18px; color: var(--muted); line-height: 1.45; font-size: 14px; }
    .infographic-step li + li { margin-top: 6px; }
    .explain-band, .start-section, .market-context, .proof-section, .faq-section { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: var(--paper); color: var(--ink); }
    .proof-section { background: #11101a; color: var(--paper); }
    .faq-section { background: #fffdfb; color: var(--ink); }
    .explain-band h2, .start-section h2, .market-context h2, .proof-section h2, .faq-section h2 { font-size: clamp(34px, 5vw, 64px); line-height: 1; margin: 0; }
    .brand-word { color: var(--periwinkle); }
    .market-context p { color: var(--muted); line-height: 1.55; }
    .source-note { font-size: 13px; max-width: 680px; }
    .source-note a { color: #2f3db9; font-weight: 850; }
    .market-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); border: 1px solid #e5deef; border-radius: 20px; overflow: hidden; background: #fffdfb; }
    .market-grid article { min-height: 154px; padding: 24px; border-right: 1px solid #e5deef; border-bottom: 1px solid #e5deef; display: grid; align-content: end; }
    .market-grid article:nth-child(2n) { border-right: 0; }
    .market-grid article:nth-last-child(-n+2) { border-bottom: 0; }
    .market-grid strong { display: block; font-size: clamp(42px, 5vw, 62px); line-height: .9; color: #23306f; }
    .market-grid span { display: block; margin-top: 12px; color: var(--muted); font-weight: 850; line-height: 1.3; }
    .step-list { display: grid; gap: 12px; margin: 0; padding: 0; list-style: none; }
    .step-list li, .section-card { border: 1px solid #e5deef; border-radius: 16px; padding: 18px; background: #fffdfb; }
    .step-list strong, .step-list span { display: block; }
    .step-list span { color: var(--muted); margin-top: 4px; line-height: 1.45; }
    .content-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 18px; padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #fffdfb; color: var(--ink); }
    .content-grid-heading { grid-column: 1 / -1; margin: 0 0 10px; font-size: clamp(42px, 6vw, 72px); line-height: .95; letter-spacing: 0; max-width: 920px; }
    .legal-content { display: grid; gap: 18px; padding: clamp(48px, 7vw, 86px) clamp(20px, 5vw, 64px); background: #fffdfb; color: var(--ink); }
    .legal-meta { margin: 0; color: var(--muted); font-weight: 900; }
    .legal-section, .legal-card { border: 1px solid #e5deef; border-radius: 16px; padding: clamp(20px, 3vw, 30px); background: rgba(255,255,255,.82); box-shadow: 0 18px 48px rgba(37,32,68,.05); }
    .legal-section h2, .legal-card h3 { margin: 0 0 12px; line-height: 1.08; color: var(--ink); }
    .legal-section h2 { font-size: clamp(26px, 3vw, 40px); }
    .legal-card h3 { font-size: 20px; }
    .legal-section h3 { margin: 22px 0 10px; font-size: 19px; line-height: 1.15; }
    .legal-section p, .legal-card p, .legal-details dd { color: var(--muted); line-height: 1.55; }
    .legal-card-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
    .legal-details { display: grid; grid-template-columns: minmax(140px, .35fr) minmax(0, 1fr); gap: 10px 18px; margin: 16px 0; }
    .legal-details dt { color: var(--ink); font-weight: 950; }
    .legal-details dd { margin: 0; overflow-wrap: anywhere; }
    .legal-path { display: inline-flex; padding: 8px 10px; border-radius: 10px; background: #f2f4ff; color: var(--ink); font-weight: 900; }
    .supported-groups-section { display: grid; grid-template-columns: minmax(0, .82fr) minmax(0, 1.18fr); gap: clamp(24px, 5vw, 72px); align-items: start; padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #fffdfb; color: var(--ink); }
    .supported-groups-section h2 { margin: 0; max-width: 620px; font-size: clamp(42px, 6vw, 72px); line-height: .96; letter-spacing: 0; }
    .supported-groups-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
    .supported-group-card { min-height: 118px; border-radius: 18px; padding: 22px; display: flex; align-items: flex-start; color: #fff; box-shadow: 0 18px 40px rgba(20, 22, 45, .12); }
    .supported-group-card strong { color: #fff; font-size: clamp(18px, 2vw, 24px); line-height: 1.05; font-weight: 950; letter-spacing: 0; }
    .supported-group-card-1 { background: linear-gradient(135deg, #8885f0, #5f67e8); }
    .supported-group-card-2 { background: linear-gradient(135deg, #35d071, #0a8f5b); }
    .supported-group-card-3 { background: linear-gradient(135deg, #ff6148, #d63b2e); }
    .supported-group-card-4 { background: linear-gradient(135deg, #f59bb3, #b4576d); }
    .section-number { color: var(--periwinkle); font-weight: 950; }
    .section-card h2 { margin: 18px 0 10px; font-size: 24px; line-height: 1.12; }
    .section-card p, .start-section p { color: var(--muted); line-height: 1.55; }
    .start-section .app-availability { color: rgba(37,32,68,.68); }
    .proof-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
    .proof-grid article { min-height: 158px; padding: 20px; border-radius: 18px; border: 1px solid rgba(250,248,245,.14); background: rgba(250,248,245,.08); }
    .proof-grid strong, .proof-grid span { display: block; }
    .proof-grid strong { font-size: 18px; line-height: 1.05; font-weight: 950; }
    .proof-grid span { margin-top: 10px; color: rgba(250,248,245,.7); line-height: 1.45; }
    .faq-list { display: grid; gap: 12px; }
    .faq-list details { border: 1px solid rgba(136,133,240,.22); border-radius: 16px; background: #ffffff; padding: 0 18px; }
    .faq-list summary { min-height: 58px; display: flex; align-items: center; cursor: pointer; color: var(--ink); font-weight: 950; line-height: 1.2; }
    .faq-list details p { margin: 0 0 18px; color: var(--muted); line-height: 1.5; }
    .localized-hero { min-height: auto; }
    .localized-content { background: #f2f4ff; }
    .bullet-list { margin: 18px 0 0; padding: 0; list-style: none; display: grid; gap: 10px; }
    .bullet-list li { position: relative; padding-left: 22px; color: var(--muted); line-height: 1.4; font-weight: 700; }
    .bullet-list li::before { content: ""; position: absolute; left: 0; top: .62em; width: 8px; height: 8px; border-radius: 999px; background: var(--mint); }
    .original-story { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #11101a; color: var(--paper); }
    .original-story.light { background: #fffdfb; color: var(--ink); }
    .original-story.mint { background: #ecfbf1; color: var(--ink); }
    .original-story.danger { background: #fff3f3; color: var(--ink); }
    .original-story.info { background: #f2f4ff; color: var(--ink); }
    .original-story h2 { font-size: clamp(34px, 5vw, 62px); line-height: 1; margin: 0; }
    .original-story p { color: color-mix(in srgb, currentColor 72%, transparent); line-height: 1.55; }
    .story-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; }
    .story-grid.four { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    .story-grid.home-product-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .story-grid.problem-grid { grid-template-columns: 1fr; }
    .story-grid.five { grid-template-columns: repeat(5, minmax(0, 1fr)); }
    .story-grid.six { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    .story-grid article { min-height: 142px; border: 1px solid rgba(136,133,240,.2); border-radius: 16px; padding: 18px; background: rgba(255,255,255,.72); color: var(--ink); }
    .original-story:not(.light):not(.mint):not(.danger):not(.info) .story-grid article { background: rgba(250,248,245,.08); color: var(--paper); border-color: rgba(250,248,245,.14); }
    .story-grid strong, .story-grid span { display: block; }
    .story-grid strong { font-size: 18px; font-weight: 950; line-height: 1.05; }
    .story-grid span { margin-top: 10px; color: color-mix(in srgb, currentColor 68%, transparent); line-height: 1.35; }
    .story-grid a { display: inline-flex; margin-top: 18px; color: #4b55c9; font-weight: 950; text-decoration: none; }
    .group-problem-section, .group-workflow-section, .group-feature-section, .group-accumulation-section, .group-use-section { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); }
    .group-problem-section { background: #fffdfb; color: var(--ink); }
    .group-workflow-section { background: #11101a; color: var(--paper); }
    .group-feature-section { background: #f2f4ff; color: var(--ink); }
    .group-accumulation-section { background: #ecfbf1; color: var(--ink); }
    .group-use-section { background: #fffdfb; color: var(--ink); }
    .group-problem-section h2, .group-workflow-section h2, .group-feature-section h2, .group-accumulation-section h2, .group-use-section h2 { font-size: clamp(34px, 5vw, 62px); line-height: 1; margin: 0; }
    .group-problem-section p, .group-accumulation-section p { color: var(--muted); line-height: 1.55; font-size: 18px; }
    .problem-list { display: grid; gap: 12px; }
    .problem-list article, .use-case-grid article { border: 1px solid #e5deef; border-radius: 16px; padding: 18px; background: rgba(255,255,255,.78); color: var(--ink); font-weight: 900; line-height: 1.2; }
    .problem-list.compact { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .group-journey { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    .group-journey article { min-height: 210px; }
    .group-journey article:nth-child(3n) { border-right: 1px solid rgba(250,248,245,.14); }
    .group-journey article:nth-child(4n) { border-right: 0; }
    .group-journey article:nth-last-child(-n+4) { border-bottom: 0; }
    .group-feature-grid { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    .accumulation-panel { border: 1px solid rgba(37,32,68,.12); border-radius: 24px; padding: clamp(24px, 4vw, 42px); background: rgba(255,255,255,.78); box-shadow: 0 18px 48px rgba(37,32,68,.06); }
    .accumulation-panel p { margin-top: 0; }
    .accumulation-panel strong, .accumulation-panel span { display: block; }
    .accumulation-panel strong { color: #164a2b; font-size: 24px; line-height: 1.1; }
    .accumulation-panel span { margin-top: 8px; color: var(--muted); line-height: 1.45; }
    .use-case-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
    .journey-rail { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 0; border: 1px solid rgba(250,248,245,.16); border-radius: 22px; overflow: hidden; background: rgba(250,248,245,.06); }
    .journey-rail article { min-height: 190px; padding: 22px; border-right: 1px solid rgba(250,248,245,.14); border-bottom: 1px solid rgba(250,248,245,.14); display: grid; align-content: end; }
    .journey-rail article:nth-child(3n) { border-right: 0; }
    .journey-rail article:nth-last-child(-n+3) { border-bottom: 0; }
    .journey-rail span { color: var(--mint); font-size: 13px; font-weight: 950; }
    .journey-rail strong { display: block; margin-top: 42px; font-size: clamp(22px, 2.1vw, 30px); line-height: 1; }
    .journey-rail p { margin: 14px 0 0; color: rgba(250,248,245,.72); line-height: 1.38; }
    .journey-rail.group-journey { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    .journey-rail.group-journey article { min-height: 210px; }
    .journey-rail.group-journey article:nth-child(3n) { border-right: 1px solid rgba(250,248,245,.14); }
    .journey-rail.group-journey article:nth-child(4n) { border-right: 0; }
    .journey-rail.group-journey article:nth-last-child(-n+4) { border-bottom: 0; }
    .diaspora-change-section { display: grid; grid-template-columns: minmax(240px, .55fr) minmax(0, 1.45fr); gap: clamp(24px, 4vw, 56px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #11101a; color: var(--paper); }
    .diaspora-change-section h2 { font-size: clamp(34px, 5vw, 62px); line-height: 1; margin: 0; }
    .change-compare-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; }
    .change-compare-grid article { border: 1px solid rgba(250,248,245,.14); border-radius: 22px; padding: clamp(22px, 3vw, 34px); background: rgba(250,248,245,.07); min-height: 360px; }
    .change-compare-grid article:nth-child(2) { background: linear-gradient(135deg, rgba(57,205,116,.22), rgba(136,133,240,.16)); }
    .change-compare-grid h3 { margin: 0 0 18px; font-size: clamp(24px, 2.4vw, 34px); line-height: 1.04; }
    .change-compare-grid ul { display: grid; gap: 12px; margin: 0; padding: 0; list-style: none; }
    .change-compare-grid li { position: relative; padding-left: 22px; color: rgba(250,248,245,.78); line-height: 1.35; font-weight: 750; }
    .change-compare-grid li::before { content: ""; position: absolute; left: 0; top: .62em; width: 8px; height: 8px; border-radius: 999px; background: var(--mint); }
    .insurance-work-section, .insurance-finance-section { display: grid; grid-template-columns: minmax(240px, .55fr) minmax(0, 1.45fr); gap: clamp(24px, 4vw, 56px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); }
    .insurance-work-section { background: #11101a; color: var(--paper); }
    .insurance-finance-section { background: #ecfbf1; color: var(--ink); }
    .insurance-work-section h2, .insurance-finance-section h2 { font-size: clamp(34px, 5vw, 62px); line-height: 1; margin: 0; }
    .insurance-step-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; }
    .insurance-step-grid article { min-height: 190px; border: 1px solid rgba(250,248,245,.14); border-radius: 22px; padding: 24px; background: rgba(250,248,245,.07); display: grid; align-content: end; }
    .insurance-step-grid span { color: var(--mint); font-size: 13px; font-weight: 950; }
    .insurance-step-grid p { margin: 42px 0 0; color: rgba(250,248,245,.78); line-height: 1.38; font-size: clamp(18px, 1.6vw, 22px); font-weight: 750; }
    .premium-finance-panel { border: 1px solid rgba(37,32,68,.12); border-radius: 24px; padding: clamp(24px, 4vw, 42px); background: linear-gradient(135deg, rgba(57,205,116,.2), rgba(136,133,240,.14)); box-shadow: 0 18px 48px rgba(37,32,68,.06); }
    .premium-finance-panel p { margin: 0; color: var(--muted); line-height: 1.55; font-size: clamp(20px, 2vw, 28px); font-weight: 800; }
    .craas-specialist-section, .craas-bank-section, .craas-benefits-section { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); }
    .craas-specialist-section { background: #11101a; color: var(--paper); }
    .craas-bank-section { background: #fffdfb; color: var(--ink); }
    .craas-benefits-section { background: #ecfbf1; color: var(--ink); }
    .craas-specialist-section h2, .craas-bank-section h2, .craas-benefits-section h2 { font-size: clamp(34px, 5vw, 62px); line-height: 1; margin: 0; }
    .craas-service-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
    .craas-service-grid article { min-height: 132px; border-radius: 20px; padding: 22px; color: #fffdfb; box-shadow: 0 18px 42px rgba(0,0,0,.18); display: grid; align-content: end; }
    .craas-service-grid article:nth-child(4n+1) { background: linear-gradient(135deg, #8885f0, #5f6fe9); }
    .craas-service-grid article:nth-child(4n+2) { background: linear-gradient(135deg, #39cd74, #11875d); }
    .craas-service-grid article:nth-child(4n+3) { background: linear-gradient(135deg, #ff644a, #db2f25); }
    .craas-service-grid article:nth-child(4n+4) { background: linear-gradient(135deg, #ef8fa4, #8e5369); }
    .craas-service-grid strong { font-size: clamp(18px, 2vw, 28px); line-height: 1.05; font-weight: 950; }
    .craas-list-panel, .craas-benefit-grid article { border: 1px solid rgba(37,32,68,.12); border-radius: 24px; padding: clamp(22px, 3vw, 34px); background: rgba(255,255,255,.78); box-shadow: 0 18px 48px rgba(37,32,68,.06); }
    .craas-list-panel ul, .craas-benefit-grid ul { display: grid; gap: 12px; margin: 0; padding: 0; list-style: none; }
    .craas-list-panel ul { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .craas-list-panel li, .craas-benefit-grid li { position: relative; padding-left: 22px; color: var(--muted); line-height: 1.35; font-weight: 760; }
    .craas-list-panel li::before, .craas-benefit-grid li::before { content: ""; position: absolute; left: 0; top: .58em; width: 8px; height: 8px; border-radius: 999px; background: var(--mint); }
    .craas-benefit-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; }
    .craas-benefit-grid article:nth-child(2) { background: linear-gradient(135deg, rgba(57,205,116,.18), rgba(136,133,240,.12)); }
    .craas-benefit-grid h3 { margin: 0 0 18px; font-size: clamp(24px, 2.4vw, 34px); line-height: 1.04; }
    .partner-opportunity-section, .partner-market-section, .partner-operating-section { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); }
    .partner-opportunity-section { background: #fffdfb; color: var(--ink); }
    .partner-market-section { background: #f2f4ff; color: var(--ink); }
    .partner-operating-section { background: #11101a; color: var(--paper); }
    .partner-opportunity-section h2, .partner-market-section h2, .partner-operating-section h2 { font-size: clamp(34px, 5vw, 62px); line-height: 1; margin: 0; }
    .partner-metric-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
    .partner-metric-grid article { min-height: 150px; border-radius: 22px; padding: 24px; background: #11101a; color: var(--paper); display: grid; align-content: end; box-shadow: 0 18px 42px rgba(37,32,68,.12); }
    .partner-metric-grid article:nth-child(2) { background: linear-gradient(135deg, #39cd74, #11875d); }
    .partner-metric-grid article:nth-child(3) { background: linear-gradient(135deg, #8885f0, #5f6fe9); }
    .partner-metric-grid article:nth-child(4) { background: linear-gradient(135deg, #ff644a, #db2f25); }
    .partner-metric-grid strong, .partner-metric-grid span { display: block; }
    .partner-metric-grid strong { font-size: clamp(32px, 4vw, 54px); line-height: .95; font-weight: 950; }
    .partner-metric-grid span { margin-top: 12px; color: rgba(255,253,251,.82); line-height: 1.25; font-weight: 850; }
    .partner-engine-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
    .partner-engine-grid article { border: 1px solid rgba(37,32,68,.12); border-radius: 22px; padding: 24px; background: rgba(255,255,255,.78); box-shadow: 0 18px 48px rgba(37,32,68,.06); }
    .partner-engine-grid article:nth-child(2) { background: linear-gradient(135deg, rgba(57,205,116,.18), rgba(255,255,255,.82)); }
    .partner-engine-grid article:nth-child(3) { background: linear-gradient(135deg, rgba(136,133,240,.18), rgba(255,255,255,.82)); }
    .partner-engine-grid article:nth-child(4) { background: linear-gradient(135deg, rgba(255,100,74,.15), rgba(255,255,255,.82)); }
    .partner-engine-grid strong { display: block; font-size: clamp(22px, 2.2vw, 32px); line-height: 1.04; font-weight: 950; }
    .partner-engine-grid p { margin: 16px 0 0; color: var(--muted); line-height: 1.45; font-weight: 760; }
    .partner-engine-grid ul { display: grid; gap: 10px; margin: 18px 0 0; padding: 0; list-style: none; }
    .partner-engine-grid li { position: relative; padding-left: 22px; color: var(--muted); line-height: 1.32; font-weight: 760; }
    .partner-engine-grid li::before { content: ""; position: absolute; left: 0; top: .58em; width: 8px; height: 8px; border-radius: 999px; background: var(--mint); }
    .partner-market-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
    .partner-market-grid article { min-height: 226px; border-radius: 22px; padding: 24px; color: #fffdfb; box-shadow: 0 18px 42px rgba(37,32,68,.12); display: grid; align-content: start; }
    .partner-market-grid article:nth-child(1) { background: linear-gradient(135deg, #8885f0, #5f6fe9); }
    .partner-market-grid article:nth-child(2) { background: linear-gradient(135deg, #39cd74, #11875d); }
    .partner-market-grid article:nth-child(3) { background: linear-gradient(135deg, #ff644a, #db2f25); }
    .partner-market-grid article:nth-child(4) { background: linear-gradient(135deg, #ef8fa4, #8e5369); }
    .partner-market-grid article:nth-child(5) { grid-column: 1 / -1; background: linear-gradient(135deg, #39cd74, #8885f0 52%, #ff644a); }
    .partner-market-grid strong, .partner-market-grid span, .partner-market-grid p { display: block; }
    .partner-market-grid strong { font-size: clamp(22px, 2.4vw, 34px); line-height: 1.02; font-weight: 950; }
    .partner-market-grid span { margin-top: 14px; color: rgba(255,253,251,.82); font-size: 15px; line-height: 1.25; font-weight: 950; }
    .partner-market-grid p { margin: 20px 0 0; color: rgba(255,253,251,.82); line-height: 1.4; font-size: 16px; font-weight: 760; }
    .partner-operating-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; }
    .partner-operating-grid article { min-height: 520px; border: 1px solid rgba(250,248,245,.14); border-radius: 22px; padding: 24px; background: rgba(250,248,245,.07); }
    .partner-operating-grid article:nth-child(2) { background: linear-gradient(135deg, rgba(57,205,116,.2), rgba(250,248,245,.06)); }
    .partner-operating-grid article:nth-child(3) { background: linear-gradient(135deg, rgba(255,100,74,.18), rgba(136,133,240,.15)); }
    .partner-operating-grid h3 { margin: 0 0 18px; font-size: clamp(22px, 2vw, 30px); line-height: 1.05; }
    .partner-operating-grid p { margin: 0 0 16px; color: rgba(250,248,245,.72); line-height: 1.45; font-weight: 760; }
    .partner-operating-grid ul { display: grid; gap: 10px; margin: 0; padding: 0; list-style: none; }
    .partner-operating-grid li { position: relative; padding-left: 22px; color: rgba(250,248,245,.78); line-height: 1.3; font-weight: 760; }
    .partner-operating-grid li::before { content: ""; position: absolute; left: 0; top: .58em; width: 8px; height: 8px; border-radius: 999px; background: var(--mint); }
    .start-actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 22px; }
    .button.on-light:not(.cta-app):not(.cta-group):not(.cta-touch) { color: var(--ink); border-color: #ded8ea; }
    .site-footer { display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, .8fr); gap: 28px; padding: 36px clamp(20px, 5vw, 64px); border-top: 1px solid rgba(250,248,245,.12); background: #050510; }
    .footer-identity { max-width: 760px; }
    .footer-identity p { margin: 8px 0 0; color: rgba(250,248,245,.68); font-size: .88rem; line-height: 1.55; }
    .site-footer nav { display: flex; flex-wrap: wrap; justify-content: flex-end; align-content: start; gap: 12px 18px; }
    .site-footer a { color: rgba(250,248,245,.82); font-weight: 800; }
    @media (max-width: 1120px) and (min-width: 981px) {
      .site-header { flex-wrap: nowrap; }
      .menu-button { display: inline-flex; margin-left: auto; }
      .site-nav { display: none; position: absolute; top: 100%; left: 0; right: 0; padding: 12px clamp(20px, 5vw, 64px) 18px; justify-content: flex-start; overflow: visible; flex-wrap: wrap; background: #050510; border-bottom: 1px solid rgba(250,248,245,.1); box-shadow: 0 24px 60px rgba(0,0,0,.35); }
      .site-nav.open { display: flex; }
      .header-actions { display: none; }
    }
    @media (max-width: 980px) {
      .site-header { flex-wrap: nowrap; }
      .menu-button { display: inline-flex; margin-left: auto; }
      .site-nav { display: none; position: absolute; top: 100%; left: 0; right: 0; padding: 12px clamp(20px, 5vw, 64px) 18px; justify-content: flex-start; overflow: visible; flex-wrap: wrap; background: #050510; border-bottom: 1px solid rgba(250,248,245,.1); box-shadow: 0 24px 60px rgba(0,0,0,.35); }
      .site-nav.open { display: flex; }
      .header-actions { display: none; }
      .hero { min-height: auto; grid-template-columns: 1fr; padding-top: 40px; }
      .hero-device { min-height: 360px; }
      .hero-widget { width: min(100%, 390px); min-height: 350px; }
      .phone-widget { width: min(100%, 366px); min-height: 650px; }
      .content-grid, .infographic-grid { grid-template-columns: 1fr 1fr; }
      .explain-band, .start-section, .market-context, .proof-section, .faq-section, .original-story, .supported-groups-section { grid-template-columns: 1fr; }
      .group-problem-section, .group-workflow-section, .group-feature-section, .group-accumulation-section, .group-use-section, .diaspora-change-section, .insurance-work-section, .insurance-finance-section, .craas-specialist-section, .craas-bank-section, .craas-benefits-section, .partner-opportunity-section, .partner-market-section, .partner-operating-section { grid-template-columns: 1fr; }
      .problem-list.compact, .use-case-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .partner-engine-grid, .partner-operating-grid { grid-template-columns: 1fr; }
      .craas-service-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .story-grid, .story-grid.four, .story-grid.five, .story-grid.six { grid-template-columns: 1fr 1fr; }
      .journey-rail { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .journey-rail.group-journey { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .journey-rail article { border-right: 1px solid rgba(250,248,245,.14); border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-child(3n) { border-right: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-child(2n) { border-right: 0; }
      .journey-rail article:not(:nth-last-child(-n+2)) { border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-last-child(-n+2) { border-bottom: 0; }
    }
    @media (max-width: 560px) {
      .site-header { padding: 14px 20px; gap: 12px; }
      .brand strong { font-size: 18px; }
      .hero { padding: 20px 20px 24px; gap: 12px; }
      h1 { font-size: clamp(30px, 9vw, 38px); line-height: 1; }
      .hero-intro { font-size: 15px; line-height: 1.32; margin: 14px 0 16px; }
      .hero-actions { display: grid; grid-template-columns: 1fr; gap: 8px; }
      .button { width: 100%; }
      .hero-actions .button { min-height: 42px; padding: 10px 14px; }
      .hero-device { min-height: 160px; max-height: 160px; overflow: hidden; align-items: start; }
      .hero-widget { width: 100%; min-height: 300px; border-radius: 24px; padding: 20px; }
      .phone-widget { width: min(100%, 340px); height: 160px; min-height: 160px; padding: 0; border-radius: 38px; overflow: hidden; }
      .phone-shell { width: 340px; max-width: 100%; height: 620px; min-height: 620px; border-radius: 48px; transform: scale(.42); transform-origin: top center; margin: 0 auto; }
      .phone-screen { height: 600px; min-height: 600px; border-radius: 38px; padding: 16px 14px 12px; }
      .ledger-summary { grid-template-columns: 1fr; }
      .statement-head, .ledger-widget .ledger-row { grid-template-columns: minmax(92px, 1fr) auto; }
      .statement-head span:last-child, .ledger-widget .ledger-row em { grid-column: 1 / -1; }
      .ledger-row { grid-template-columns: 1fr auto; gap: 8px; }
      .ledger-row strong { grid-column: 1 / -1; }
      .ledger-widget .ledger-row strong { grid-column: auto; }
      .community-widget:not(.phone-widget), .policy-widget:not(.phone-widget), .terms-widget:not(.phone-widget), .deletion-widget:not(.phone-widget), .data-widget:not(.phone-widget) { grid-template-columns: 1fr; }
      .member-ring { width: 128px; height: 128px; justify-self: center; }
      .home-flow { grid-template-columns: 1fr; }
      .home-flow i { height: 18px; width: 2px; justify-self: center; }
      .content-grid, .infographic-grid, .supported-groups-grid { grid-template-columns: 1fr; }
      .legal-card-grid, .legal-details { grid-template-columns: 1fr; }
      .story-grid, .story-grid.four, .story-grid.five, .story-grid.six { grid-template-columns: 1fr; }
      .language-switcher { display: none; }
      .localized-nav { display: flex; position: static; padding: 0; background: transparent; border-bottom: 0; box-shadow: none; }
      .proof-grid { grid-template-columns: 1fr; }
      .explain-band, .start-section, .market-context, .proof-section, .faq-section, .content-grid, .supported-groups-section { padding: 48px 20px; }
      .legal-content { padding: 48px 20px; }
      .group-problem-section, .group-workflow-section, .group-feature-section, .group-accumulation-section, .group-use-section, .diaspora-change-section, .insurance-work-section, .insurance-finance-section, .craas-specialist-section, .craas-bank-section, .craas-benefits-section, .partner-opportunity-section, .partner-market-section, .partner-operating-section { grid-template-columns: 1fr; padding: 48px 20px; }
      .problem-list.compact, .use-case-grid, .journey-rail.group-journey, .change-compare-grid, .insurance-step-grid, .craas-service-grid, .craas-list-panel ul, .craas-benefit-grid, .partner-metric-grid, .partner-engine-grid, .partner-market-grid, .partner-operating-grid { grid-template-columns: 1fr; }
      .partner-market-grid article:nth-child(5) { grid-column: auto; }
      .market-grid { grid-template-columns: 1fr; }
      .market-grid article { min-height: 128px; border-right: 0; }
      .market-grid article:nth-last-child(2) { border-bottom: 1px solid #e5deef; }
      .original-story { padding: 48px 20px; }
      .journey-rail { grid-template-columns: 1fr; }
      .journey-rail article { min-height: 180px; border-right: 0; border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:last-child { border-bottom: 0; }
      .site-footer { grid-template-columns: 1fr; }
      .site-footer nav { justify-content: flex-start; }
    }
    @media (max-width: 1180px) and (min-width: 981px) {
      .journey-rail { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .journey-rail article { border-right: 1px solid rgba(250,248,245,.14); border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-child(3n) { border-right: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-child(2n) { border-right: 0; }
      .journey-rail article:nth-last-child(-n+3) { border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-last-child(-n+2) { border-bottom: 0; }
    }
  CSS
end

def minify_css(css)
  css
    .gsub(%r{/\*.*?\*/}m, "")
    .gsub(/\s+/, " ")
    .gsub(/\s*([{}:;,>+~])\s*/, "\\1")
    .gsub(/;}/, "}")
    .gsub(/\b0+\./, ".")
    .gsub(/(:|\s)0(px|rem|em|%)/, "\\10")
    .gsub("#ffffff", "#fff")
    .strip
end

def split_stylesheets(css)
  section_prefixes = %w[
    content-grid infographic supported-groups section-card bullet-list legal-
    group-problem group-workflow group-feature group-accumulation group-use
    problem-list use-case-grid group-journey accumulation-panel
    diaspora-change change-compare insurance-work insurance-finance
    insurance-step premium-finance craas- partner- story-grid.five story-grid.six
    diaspora-card protection-card readiness-card community-card partner-card
    trust-card policy-card terms-card deletion-card data-card
  ]
  sections_css = []
  core_css = css.gsub(/^\s*([^@{}][^{}]*)\{([^{}]*)\}\n?/m) do |rule|
    selector = Regexp.last_match(1)
    section_rule = section_prefixes.any? do |prefix|
      selector.include?(".#{prefix}") || selector.include?(prefix)
    end
    if section_rule
      sections_css << rule
      ""
    else
      rule
    end
  end
  [minify_css(core_css), minify_css(sections_css.join("\n"))]
end

def site_js
  <<~JS
    const nav = document.querySelector('[data-site-nav]');
    const button = document.querySelector('[data-menu-button]');
    if (button && nav) {
      button.addEventListener('click', () => {
        const open = nav.classList.toggle('open');
        button.setAttribute('aria-expanded', String(open));
      });
    }
    if (window.location.hash === '#/privacy') {
      window.location.replace('/privacy/');
    }
  JS
end

def headers
  <<~HEADERS
    /*
      X-Frame-Options: DENY
      X-Content-Type-Options: nosniff
      Referrer-Policy: strict-origin-when-cross-origin
      Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), fullscreen=(self)
      Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://static.cloudflareinsights.com; style-src 'self'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' https://cloudflareinsights.com https://*.cloudflareinsights.com; manifest-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; upgrade-insecure-requests

    /index.html
      Cache-Control: public, max-age=300, must-revalidate

    /
      Cache-Control: public, max-age=300, must-revalidate

    /*.html
      Cache-Control: public, max-age=300, must-revalidate

    /styles.css
      Cache-Control: public, max-age=31536000, immutable

    /site.js
      Cache-Control: public, max-age=31536000, immutable

    /sections.css
      Cache-Control: public, max-age=31536000, immutable

    /manifest.json
      Cache-Control: public, max-age=3600, must-revalidate

    /assets/*
      Cache-Control: public, max-age=31536000, immutable

    /icons/*
      Cache-Control: public, max-age=31536000, immutable
  HEADERS
end

FileUtils.rm_rf(BUILD_DIR)
FileUtils.mkdir_p(BUILD_DIR)
build_lastmod = Time.now.utc.strftime("%Y-%m-%d")

unless INDEXNOW_KEY.empty? || INDEXNOW_KEY.match?(INDEXNOW_KEY_PATTERN)
  abort("PUBLIC_INDEXNOW_KEY must be 8-128 characters using A-Z, a-z, 0-9, or dashes only")
end

core_stylesheet, section_stylesheet = split_stylesheets(stylesheet)
write_file(File.join(BUILD_DIR, "styles.css"), core_stylesheet)
write_file(File.join(BUILD_DIR, "sections.css"), section_stylesheet)
write_file(File.join(BUILD_DIR, "site.js"), site_js)
write_file(File.join(BUILD_DIR, "_headers"), headers)
write_file(File.join(BUILD_DIR, "robots.txt"), "User-agent: *\nAllow: /\nSitemap: #{PUBLIC_URL}/sitemap.xml\n")
write_file(File.join(BUILD_DIR, "#{INDEXNOW_KEY}.txt"), "#{INDEXNOW_KEY}\n") unless INDEXNOW_KEY.empty?

assets = [
  BRAND_ASSET,
  MOMO_ASSET,
  QR_ASSET,
  ICON_ASSET
]
assets.each do |asset|
  source = File.join(ROOT, asset)
  next unless File.file?(source)

  target = File.join(BUILD_DIR, asset)
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.cp(source, target)
end

FileUtils.mkdir_p(File.join(BUILD_DIR, "icons"))
FileUtils.cp(File.join(ROOT, ICON_ASSET), File.join(BUILD_DIR, "icons", "collect.png"))

well_known_source = File.join(ROOT, "web", ".well-known")
if Dir.exist?(well_known_source)
  well_known_target = File.join(BUILD_DIR, ".well-known")
  FileUtils.mkdir_p(well_known_target)
  Dir.children(well_known_source).each do |entry|
    source = File.join(well_known_source, entry)
    next unless File.file?(source)

    FileUtils.cp(source, File.join(well_known_target, entry))
  end
end

manifest = {
  "name" => "Collect by IKANISA",
  "short_name" => "Collect",
  "description" => "Microsavings and group savings for daily earners.",
  "start_url" => "/",
  "display" => "standalone",
  "background_color" => "#050510",
  "theme_color" => "#8885F0",
  "icons" => [
    {
      "src" => "/icons/collect.png",
      "sizes" => "512x512",
      "type" => "image/png",
      "purpose" => "any maskable"
    }
  ]
}
write_file(File.join(BUILD_DIR, "manifest.json"), JSON.pretty_generate(manifest) + "\n")

all_paths = []
PAGES.each do |page|
  html = page_html(page)
  write_file(route_file(page[:path]), html)
  all_paths << page[:path]
  Array(page[:aliases]).each do |alias_path|
    alias_page = page.merge(path: alias_path)
    write_file(route_file(alias_path), page_html(alias_page, current_path: alias_path))
    all_paths << alias_path
  end
end

LOCALIZED_PAGES.each do |page|
  write_file(localized_route_file(page[:path]), localized_page_html(page))
  all_paths << page[:path]
end

sitemap_urls = all_paths.uniq.sort.map do |path|
  "  <url><loc>#{page_url(path)}</loc><lastmod>#{build_lastmod}</lastmod></url>"
end.join("\n")
write_file(
  File.join(BUILD_DIR, "sitemap.xml"),
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n#{sitemap_urls}\n</urlset>\n"
)

write_file(
  File.join(BUILD_DIR, "version.json"),
  JSON.pretty_generate(
    "name" => "collect-public-static",
    "generated_at" => Time.now.utc.iso8601,
    "routes" => all_paths.uniq.sort,
    "indexnow_key_file" => INDEXNOW_KEY.empty? ? nil : "#{INDEXNOW_KEY}.txt"
  ) + "\n"
)

puts "Prepared static public website build: #{BUILD_DIR}"
