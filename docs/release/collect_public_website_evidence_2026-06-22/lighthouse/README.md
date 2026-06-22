# Lighthouse And Core Web Vitals Evidence

Attach Lighthouse/PageSpeed evidence here.

Accepted completion artifacts:

- `mobile.json`, `mobile.html`, or `mobile.pdf`
- `desktop.json`, `desktop.html`, or `desktop.pdf`

Templates are provided with `.template.json` filenames. They do not satisfy the
completion gate until replaced by real Lighthouse/PageSpeed reports with the
accepted filename.

The completion gate validates JSON files by reading Lighthouse category scores.
For `mobile.json` and `desktop.json`, all of the following must be at least
`0.9`:

- `performance.score`
- `accessibility.score`
- `best-practices.score`
- `seo.score`

Target:

- Performance: green, preferably 90+
- Accessibility: green, preferably 90+
- Best Practices: green, preferably 90+
- SEO: green, preferably 90+
- Core Web Vitals evidence attached where available

The API attempts in `../pagespeed/` returned quota errors and do not close this
requirement.
