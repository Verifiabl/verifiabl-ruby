# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "tmpdir"

root = File.expand_path("..", __dir__)
issuer_root = File.join(root, "gems/verifiabl-issuer")
ruby = RbConfig.ruby
clean_env = {
  "BUNDLE_BIN_PATH" => nil,
  "BUNDLE_GEMFILE" => nil,
  "BUNDLER_VERSION" => nil,
  "RUBYLIB" => nil,
  "RUBYOPT" => nil
}

Dir.mktmpdir("verifiabl-packed-gem-") do |directory|
  package = File.join(directory, "verifiabl-issuer.gem")
  if ARGV.empty?
    system(clean_env, ruby, "-S", "gem", "build", "verifiabl-issuer.gemspec", "--output", package, chdir: issuer_root, exception: true)
  else
    source_package = File.expand_path(ARGV.fetch(0), Dir.pwd)
    abort "packed gem does not exist: #{source_package}" unless File.file?(source_package)
    FileUtils.cp(source_package, package)
  end

  gem_home = File.join(directory, "gems")
  system(clean_env, ruby, "-S", "gem", "install", package, "--install-dir", gem_home, "--no-document", exception: true)

  consumer_env = clean_env.merge("GEM_HOME" => gem_home, "GEM_PATH" => gem_home)
  checks = [
    <<~RUBY,
      require "verifiabl/issuer"
      abort "wrong namespace" unless defined?(Verifiabl::Issuer::Client)
      abort "missing QR dependency" unless defined?(RQRCodeCore::QRCode)
      reference = Verifiabl::Issuer.generate_verifiabl_reference
      valid_reference = reference.length == 22 && reference.chars.all? { |character| "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-".include?(character) }
      abort "invalid reference" unless valid_reference
      png = Verifiabl::Issuer.build_barcode_png(verifiabl_reference: reference, encrypted_pii: "foo".b, width: 480)
      abort "invalid PNG" unless png.png.start_with?([137, 80, 78, 71, 13, 10, 26, 10].pack("C*"))
    RUBY
    <<~RUBY
      require "verifiabl-issuer"
      spec = Gem.loaded_specs.fetch("verifiabl-issuer")
      abort "signatures were not packed" unless File.file?(File.join(spec.full_gem_path, "sig/verifiabl-issuer.rbs"))
      abort "frame assets were not packed" unless File.file?(File.join(spec.full_gem_path, "lib/verifiabl/issuer/assets/frame-720.vfr1"))
      abort "Rails loaded eagerly" if defined?(Rails)
    RUBY
  ]
  checks.each do |source|
    system(consumer_env, ruby, "-e", source, chdir: directory, exception: true)
  end
end

puts "Packed gem consumer checks passed"
