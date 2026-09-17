# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

root = File.expand_path("..", __dir__)
issuer_root = File.join(root, "gems/verifiabl-issuer")
example = File.join(root, "examples/issuer/basic")
ruby = RbConfig.ruby
clean_env = {
  "BUNDLE_BIN_PATH" => nil,
  "BUNDLE_GEMFILE" => nil,
  "BUNDLER_VERSION" => nil,
  "RUBYLIB" => nil,
  "RUBYOPT" => nil,
  "RUBYGEMS_GEMDEPS" => nil,
  "VERIFIABL_CLIENT_ID" => nil,
  "VERIFIABL_CLIENT_SECRET" => nil,
  "VERIFIABL_ENCRYPTION_KEY_BASE64" => nil
}

Dir.mktmpdir("verifiabl-basic-example-") do |directory|
  package = File.join(directory, "verifiabl-issuer.gem")
  system(clean_env, ruby, "-S", "gem", "build", "verifiabl-issuer.gemspec", "--output", package, chdir: issuer_root, exception: true)

  gem_home = File.join(directory, "gems")
  system(clean_env, ruby, "-S", "gem", "install", package, "--install-dir", gem_home, "--no-document", exception: true)
  consumer_env = clean_env.merge(
    "BUNDLE_IGNORE_CONFIG" => "1",
    "GEM_HOME" => gem_home,
    "GEM_PATH" => gem_home
  )
  system(
    consumer_env,
    ruby,
    "-e",
    'require "verifiabl/issuer"; abort "packed gem did not load" unless defined?(Verifiabl::Issuer::Client)',
    chdir: directory,
    exception: true
  )

  %w[issue_payslips_self_managed.rb issue_payslips_api_managed.rb].each do |source|
    FileUtils.cp(File.join(example, source), directory)
    system(consumer_env, ruby, "-c", source, chdir: directory, exception: true)
    _stdout, stderr, status = Open3.capture3(consumer_env, ruby, source, chdir: directory)
    unless !status.success? && stderr.include?('key not found: "VERIFIABL_CLIENT_ID"')
      abort "#{source} did not load the packed gem before reading credentials:\n#{stderr}"
    end
  end
end
