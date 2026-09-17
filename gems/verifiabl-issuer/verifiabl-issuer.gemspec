# frozen_string_literal: true

require_relative "lib/verifiabl/issuer/version"

Gem::Specification.new do |spec|
  spec.name = "verifiabl-issuer"
  spec.version = Verifiabl::Issuer::VERSION
  spec.authors = ["Verifiabl"]
  spec.email = ["support@verifiabl.io"]

  spec.summary = "Official Verifiabl Ruby SDK for issuing payslip QR codes"
  spec.description = "Format and encrypt payslip PII, register non-PII data, and render Verifiabl QR codes."
  spec.homepage = "https://verifiabl.io"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/Verifiabl/verifiabl-ruby/issues",
    "changelog_uri" => "https://github.com/Verifiabl/verifiabl-ruby/blob/main/gems/verifiabl-issuer/CHANGELOG.md",
    "documentation_uri" => "https://docs.verifiabl.io/payroll-providers",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/Verifiabl/verifiabl-ruby"
  }

  spec.files = Dir.chdir(__dir__) do
    Dir["CHANGELOG.md", "LICENSE", "README.md", "lib/**/*", "sig/**/*"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "rqrcode_core", "~> 2.1"

  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rbs", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.88"
  spec.add_development_dependency "standard", "~> 1.0"
end
