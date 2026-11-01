# Current frozen Ruby delivery gate

The fresh attempt is **blocked by the local toolchain/dependency environment**. It is not a product-test pass and does not reuse an older PR's successful receipt.

The maintained `ruby-delivery-tools` job in `.github/workflows/ci.yml` selects Ruby 3.3 and runs:

```sh
bundle check
bundle exec ruby scripts/tests/ruby_dependency_security_test.rb
bundle exec fastlane lanes
```

`Gemfile.lock` records Bundler 2.7.2, Fastlane 2.240.1 and Rubyzip 3.4.0. The current machine has Ruby 3.2.3 and Bundler 2.4.19 through `/usr/bin/bundle3.2`; the ordinary `bundle` executable is absent. Neither Fastlane nor Rubyzip is installed, and the frozen check lists the missing locked dependency graph.

The available Bundler alias was invoked with `BUNDLE_FROZEN=true`, `BUNDLE_DEPLOYMENT=true` and Fastlane update/usage checks disabled. Its results were:

| Command | Result |
| --- | --- |
| `bundle3.2 check` | Exit 1; required locked gems missing. |
| `bundle3.2 exec ruby scripts/tests/ruby_dependency_security_test.rb` | Exit 1 before the ZIP cases, because the bundle cannot materialize. |
| `bundle3.2 exec fastlane lanes` | Exit 127; Fastlane executable unavailable. |

`ruby-frozen-current-result.json` contains the actual stdout/stderr, command arguments, observed runtime versions and exact current hashes of the Gemfiles, Fastlane source, ZIP test and CI workflow. Static inspection found eight lane declarations (two Android and six historical iOS lanes); that is not successful runtime lane discovery. No lane was executed, no signing or store operation ran, no provider was contacted and no dependency installation or source edit was attempted.

To close this gate, provision the canonical isolated Ruby/Bundler environment, install the exact unchanged locked dependency graph under frozen settings, then rerun all three maintained commands and preserve their actual results. The three tiny ZIP boundary cases and eight-lane listing must execute successfully; they do not authorize any lane or store effect. Final artifact, rights, signing, Play and independent CI gates remain separate.
