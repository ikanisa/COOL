# Visual QA Screenshots

Attach final visual QA screenshots here.

Required screenshot files:

- `mobile_390x844.png`
- `mobile_430x932.png`
- `tablet_768x1024.png`
- `desktop_1440x1000.png`

The completion gate validates PNG signatures, exact dimensions matching the
file names above, and a passing `../browser_visual_qa.json` report.
Alternatively, attach `../owner-approvals/visual-approval.md` with explicit
owner approval.

The screenshots must show the live production site or a byte-equivalent local
build. They should prove:

- no clipped mobile navigation;
- primary CTA visible in the first viewport;
- product visual visible in the first viewport;
- text does not overlap or overflow;
- visual system is Collect-owned and not a copy of benchmark references.
