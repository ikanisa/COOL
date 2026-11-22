"""Validate Auth email contracts and optionally write synthetic HTML previews.

Validation uses an HTML parser and synthetic substitutions.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
PREVIEW_ORIGIN = "https://platform-admin.collect.ikanisa.com"
SUPPORT_EMAIL = "info@ikanisa.com"
SUBSTITUTIONS = {"SiteURL": PREVIEW_ORIGIN, "Token": "012345", "TokenHash": "a" * 64}
VARIABLE = re.compile(r"{{\s*\.([A-Za-z]+)\s*}}")
EXPECTED = {
    "invite": ("Your invitation to Collect", "Join Collect", {"SiteURL"}, "Open Collect"),
    "magic_link": ("Your Collect sign-in code", "Your sign-in code", {"Token"}, None),
    "confirmation": ("Your Collect sign-in code", "Your sign-in code", {"Token"}, None),
    "recovery": ("Reset your Collect password", "Reset your password", {"SiteURL", "TokenHash"}, "Reset password"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


class Email(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = set()
        self.text = []
        self.headings = []
        self.links = []
        self.current_link = None
        self.in_heading = False
        self.hidden_depth = 0
        self.language = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        require(len(attributes) == len(attrs), f"Duplicate HTML attribute on <{tag}>")
        require(not any(name.startswith("on") for name in attributes), "Executable event attribute")
        self.tags.add(tag)

        if tag == "html":
            self.language = attributes.get("lang")
        if tag in {"head", "style"}:
            self.hidden_depth += 1
        if tag == "h1":
            self.in_heading = True
        if tag == "a":
            href = attributes.get("href")
            require(href and self.current_link is None, "Expected a destination on an unnested email link")
            self.current_link = {"href": href, "label": ""}

    def handle_endtag(self, tag):
        if tag in {"head", "style"}:
            self.hidden_depth -= 1
        if tag == "h1":
            self.in_heading = False
        if tag == "a" and self.current_link is not None:
            self.links.append(self.current_link)
            self.current_link = None

    def handle_data(self, data):
        if not self.hidden_depth:
            self.text.append(data)
        if self.in_heading:
            self.headings.append(data)
        if self.current_link is not None:
            self.current_link["label"] += data


def sha_bytes(value):
    return hashlib.sha256(value).hexdigest()


def sha_file(path):
    return sha_bytes(path.read_bytes())


def validate_action(name, expected_label, source, visible, actions):
    if expected_label is None:
        require(not actions, "The OTP email must have no action links")
        require(visible.count(SUBSTITUTIONS["Token"]) == 1, "Expected one visible sign-in code")
        require("5 minutes" in visible and "Never share your code" in visible, "Missing OTP instructions")
        if name == "confirmation":
            require("confirm your email and continue" in visible, "Missing confirmation instructions")
        return None

    require(len(actions) == 1 and actions[0]["label"] == expected_label, "Incorrect primary action")
    action = actions[0]
    url = urlsplit(action["href"])
    origin = urlsplit(PREVIEW_ORIGIN)
    require(
        (url.scheme, url.netloc) == (origin.scheme, origin.netloc) and url.path == "/" and not url.query,
        "Incorrect action origin or path",
    )
    require(action["href"] not in visible, "Raw action URL is visibly printed")
    if name == "invite":
        require(url.fragment == "/admin/login", "Invitation action does not open Admin sign-in")
        require(
            "You have been invited to Collect." in visible and "does not sign you in" in visible,
            "Missing invitation instructions",
        )
        require("password" not in visible.lower() and "TokenHash" not in source, "Invitation includes password recovery")
    else:
        path, _, query = url.fragment.partition("?")
        require(
            path == "/admin/setup" and parse_qs(query) == {"token": [SUBSTITUTIONS["TokenHash"]], "invite": ["false"]},
            "Incorrect password reset destination",
        )
        require(SUBSTITUTIONS["TokenHash"] not in visible, "Reset token hash is visible")
    return action


def validate_email(name, payload):
    subject, heading, variables, label = EXPECTED[name]
    source_path = ROOT / f"{name}.html"
    source_bytes = source_path.read_bytes()
    source = source_bytes.decode("utf-8")
    require(payload[f"mailer_subjects_{name}"] == subject, "Incorrect subject")
    require(payload[f"mailer_templates_{name}_content"] == source, "Auth payload differs from the template")

    references = VARIABLE.findall(source)
    require(set(references) == variables, f"Incorrect template variables: {references}")
    if name == "confirmation":
        require(references == ["Token"], "Confirmation must contain only the managed OTP")
    require("{{" not in VARIABLE.sub("", source), "Unsupported Go template action")
    require(
        not any(term in source for term in (".ConfirmationURL", "access_token", "refresh_token")),
        "Unexpected session-token link",
    )
    require("Collect Admin" not in source and "Revolut" not in source, "Incorrect email branding")

    rendered = VARIABLE.sub(lambda match: html.escape(SUBSTITUTIONS[match[1]], quote=True), source)
    require("{{" not in rendered, "Unrendered template action")
    email = Email()
    email.feed(rendered)
    email.close()
    require(email.language == "en" and email.headings == [heading], "Incorrect language or heading")
    require(email.current_link is None and email.hidden_depth == 0, "Unclosed email link, head, or style")
    require(not email.tags & {"script", "iframe", "form", "input", "img", "link", "object"}, "Unsupported HTML element")

    visible = "".join(email.text)
    mailto = f"mailto:{SUPPORT_EMAIL}"
    support = [item for item in email.links if item["href"].startswith("mailto:")]
    require(SUPPORT_EMAIL in visible and support == [{"href": mailto, "label": SUPPORT_EMAIL}], "Incorrect support link")
    actions = [item for item in email.links if not item["href"].startswith("mailto:")]
    action = validate_action(name, label, source, visible, actions)
    return rendered.encode("utf-8"), {
        "template": name,
        "source_sha256": sha_bytes(source_bytes),
        "subject": subject,
        "allowed_variables": sorted(variables),
        "primary_action": action,
    }


def validate_templates():
    payload = json.loads((ROOT / "auth-template-config.json").read_text(encoding="utf-8"))
    expected_fields = {
        field for name in EXPECTED for field in (f"mailer_subjects_{name}", f"mailer_templates_{name}_content")
    }
    require(isinstance(payload, dict) and set(payload) == expected_fields, "Unexpected or missing Auth config fields")

    validated = []
    for name in EXPECTED:
        try:
            validated.append(validate_email(name, payload))
        except ValueError as error:
            raise ValueError(f"{name}.html: {error}") from error
    return validated


def write_previews(validated):
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    output = PROJECT / "docs/implementation/supabase-uat/previews" / stamp
    output.mkdir(parents=True)
    results = []
    for rendered, result in validated:
        target = output / f"{result['template']}.html"
        target.write_bytes(rendered)
        results.append({**result, "preview": str(target), "preview_sha256": sha_bytes(rendered), "contract": "pass"})

    receipt = {
        "format": "collect.supabase.auth-template-contract-validation.v1",
        "at": datetime.now(timezone.utc).isoformat(),
        "project_id": "rrlduytparvsjfmegalh",
        "templates": results,
        "source_inputs": {
            name: sha_file(ROOT / name)
            for name in ("build_templates.py", "validate_templates.py", "auth-template-config.json")
        },
        "method": "Strict variable/action allowlist, escaped synthetic substitution, parsed HTML and actual Auth/client URL contracts",
        "actual_Go_template_engine_executed": False,
        "browser_visual_review_completed": False,
        "email_client_render_verified": False,
        "remote_auth_configuration_applied": False,
        "provider_sends": 0,
        "real_token_or_account_values": False,
    }
    path = output / "validation.json"
    path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return {"receipt": str(path), "sha256": sha_file(path), "preview_directory": str(output)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate contracts without writing previews or a receipt")
    args = parser.parse_args()
    try:
        validated = validate_templates()
    except (OSError, ValueError) as error:
        raise SystemExit(f"Supabase Auth template validation failed: {error}") from error
    preview = {} if args.check else write_previews(validated)
    print(json.dumps({**preview, "template_contracts_passed": len(validated), "provider_sends": 0}))


if __name__ == "__main__":
    main()
