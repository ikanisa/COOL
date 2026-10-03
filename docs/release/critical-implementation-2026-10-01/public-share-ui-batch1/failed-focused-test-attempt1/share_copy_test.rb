# frozen_string_literal: true

require 'minitest/autorun'

class ShareCopyTest < Minitest::Test
  ROOT = File.expand_path('../../../..', __dir__)
  BUILDER = File.join(ROOT, 'scripts/public_static_site_build.rb')
  SOURCE = File.read(BUILDER)
  STOP = SOURCE.index("\nallowed_build_roots = [") or raise 'Maintained execution boundary missing'
  RENDERER = Module.new
  RENDERER.module_eval(SOURCE[0...STOP], BUILDER, 1)

  def setup
    @renderer = Object.new.extend(RENDERER)
  end

  def test_generic_app_card_and_help_are_truthful_app_copy
    html = @renderer.share_landing_page_html(kind: :app)
    assert_includes html, '<h1 data-share-heading>Open Collect</h1>'
    assert_includes html, 'COLLECT APP LINK'
    assert_includes html, 'Continue in the Collect app'
    assert_includes html, 'Group invitations are confirmed separately after sign-in.'
    refute_includes html, 'COLLECT GROUP LINK'
    refute_includes html, 'A link that survives onboarding'
    refute_includes html, 'then joins only after the member signs in'
    assert_includes html, 'href="collect://app"'
  end

  def test_group_card_invitation_semantics_and_recovery_are_retained
    html = @renderer.share_landing_page_html(kind: :group)
    assert_includes html, 'COLLECT GROUP LINK'
    refute_includes html, 'COLLECT APP LINK'
    assert_includes html, 'A link that survives onboarding'
    assert_includes html, 'then joins only after the member signs in'
    assert_includes html, 'Expired, revoked or invalid links cannot join a group.'
    assert_includes html, 'Receiver numbers, raw payment messages and member phone numbers are never placed in this public link.'
    assert_includes html, 'href="collect://group/shared-group"'
  end

  def test_generic_app_branch_does_not_add_an_active_product_or_provider
    html = @renderer.share_landing_page_html(kind: :app)
    assert_includes html, 'app-id=6783960331'
    assert_includes html, 'https://play.google.com/store/apps/details?id=app.cool.mobile'
    assert_includes html, 'https://apps.apple.com/app/id6783960331'
    refute_match(/bank account|insurance enrollment|premium collection|SEPA|wallet balance|MoMo PIN/i, html)
  end
end
