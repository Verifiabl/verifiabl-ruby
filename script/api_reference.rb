# frozen_string_literal: true

require "fileutils"
require "json"
require "rbs"
require "yard"

ROOT = File.expand_path("..", __dir__)
SIGNATURE = File.join(ROOT, "gems/verifiabl-issuer/sig/verifiabl-issuer.rbs")
OUTPUT = File.join(ROOT, "generated/api/ruby.json")
SOURCE_FILES = Dir[File.join(ROOT, "gems/verifiabl-issuer/lib/**/*.rb")].sort.freeze

module ApiReference
  module_function

  def empty_documentation
    {"summary" => "", "tags" => []}
  end

  def documentation(path)
    object = YARD::Registry.at(path)
    return empty_documentation unless object
    return empty_documentation if object.file&.include?("/generated/")

    tags = object.tags
    unless object.docstring.line_range
      # YARD synthesizes incorrect `Object` return types for Data members. RBS is
      # authoritative for types, so retain inferred documentation but not inferred returns.
      tags = tags.reject { |tag| tag.tag_name.to_s == "return" }
    end
    {
      "summary" => object.docstring.to_s,
      "tags" => tags.map { |tag| tag_value(tag) }.sort_by { |tag| tag_sort_key(tag) }
    }
  end

  def tag_value(tag)
    value = {"name" => tag.tag_name.to_s, "text" => tag.text.to_s}
    value["subject"] = tag.name.to_s if tag.name
    value["types"] = tag.types.map(&:to_s) if tag.respond_to?(:types) && tag.types
    value
  end

  def tag_sort_key(tag)
    [tag.fetch("name"), tag.fetch("subject", ""), tag.fetch("text")]
  end

  def qualified_name(parent, name)
    value = name.to_s.delete_prefix("::")
    return value if parent.empty? || value.include?("::")

    "#{parent}::#{value}"
  end

  def member_path(parent, name, scope)
    separator = (scope == :singleton) ? "." : "#"
    "#{parent}#{separator}#{name}"
  end

  def method_member(parent, member)
    scope = member.kind
    path = member_path(parent, member.name, scope)
    {
      "path" => path,
      "name" => member.name.to_s,
      "kind" => "method",
      "scope" => scope.to_s,
      "signature" => member.location.source.strip,
      "documentation" => documentation(path)
    }
  end

  def attribute_member(parent, member)
    scope = member.kind
    path = member_path(parent, member.name, scope)
    {
      "path" => path,
      "name" => member.name.to_s,
      "kind" => "attribute",
      "scope" => scope.to_s,
      "access" => attribute_access(member),
      "signature" => member.location.source.strip,
      "documentation" => documentation(path)
    }
  end

  def attribute_access(member)
    return "read" if member.is_a?(RBS::AST::Members::AttrReader)
    return "write" if member.is_a?(RBS::AST::Members::AttrWriter)

    "read-write"
  end

  def constant_member(parent, declaration)
    path = qualified_name(parent, declaration.name)
    {
      "path" => path,
      "name" => declaration.name.name.to_s,
      "kind" => "constant",
      "signature" => declaration.location.source.strip,
      "documentation" => documentation(path)
    }
  end

  def api_member(parent, member)
    case member
    when RBS::AST::Members::MethodDefinition
      method_member(parent, member)
    when RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter, RBS::AST::Members::AttrAccessor
      attribute_member(parent, member)
    when RBS::AST::Declarations::Constant
      constant_member(parent, member)
    end
  end

  def namespace_declaration?(declaration)
    declaration.is_a?(RBS::AST::Declarations::Class) || declaration.is_a?(RBS::AST::Declarations::Module)
  end

  def namespace_value(declaration, parent, path)
    value = {
      "path" => path,
      "name" => declaration.name.name.to_s,
      "kind" => declaration.is_a?(RBS::AST::Declarations::Class) ? "class" : "module",
      "parent" => parent.empty? ? nil : parent,
      "documentation" => documentation(path),
      "members" => declaration.members.filter_map { |member| api_member(path, member) }.sort_by { |member| member.fetch("path") }
    }
    value["superclass"] = declaration.super_class.name.to_s if declaration.is_a?(RBS::AST::Declarations::Class) && declaration.super_class
    value
  end

  def add_namespace(declaration, parent, namespaces, constants)
    path = qualified_name(parent, declaration.name)
    namespaces << namespace_value(declaration, parent, path)
    nested = declaration.members.select { |member| namespace_declaration?(member) }
    walk(nested, path, namespaces, constants)
  end

  def walk(declarations, parent, namespaces, constants)
    declarations.each do |declaration|
      if namespace_declaration?(declaration)
        add_namespace(declaration, parent, namespaces, constants)
      elsif declaration.is_a?(RBS::AST::Declarations::Constant)
        constants << constant_member(parent, declaration)
      end
    end
  end

  def signature_declarations
    _, _, declarations = RBS::Parser.parse_signature(
      RBS::Buffer.new(name: SIGNATURE, content: File.read(SIGNATURE))
    )
    declarations
  end

  def catalogue_entries
    namespaces = []
    constants = []
    walk(signature_declarations, "", namespaces, constants)
    [namespaces, constants]
  end

  def paths_for(namespaces, constants)
    paths = namespaces.flat_map do |namespace|
      [namespace.fetch("path"), *namespace.fetch("members").map { |member| member.fetch("path") }]
    end
    paths.concat(constants.map { |constant| constant.fetch("path") })
  end

  def validate_paths(paths)
    duplicates = paths.tally.select { |_, count| count > 1 }.keys
    raise "Duplicate public API paths: #{duplicates.join(", ")}" unless duplicates.empty?

    required = [
      "Verifiabl::Issuer.format_pii",
      "Verifiabl::Issuer::Client#register_non_pii",
      "Verifiabl::Issuer::Rendering::SvgResult#svg"
    ]
    missing = required - paths
    raise "Generated API reference is missing: #{missing.join(", ")}" unless missing.empty?

    validate_non_public_paths(paths)
  end

  def validate_non_public_paths(paths)
    forbidden_prefixes = %w[
      Verifiabl::Issuer::Base32
      Verifiabl::Issuer::FrameAssets
      Verifiabl::Issuer::Instrumentation
      Verifiabl::Issuer::Pii
      Verifiabl::Issuer::PiiTextProfile
      Verifiabl::Issuer::Payload::ScanUrlParts
      Verifiabl::Issuer::PngEncoder
      Verifiabl::Issuer::Qr::CanonicalCode
      Verifiabl::Issuer::Qr::Result
      Verifiabl::Issuer::RenderingAssets
      Verifiabl::Issuer::Serialization
      Verifiabl::Issuer::Validation
    ]
    non_public = paths.select do |path|
      forbidden_prefixes.any? { |prefix| path == prefix || path.start_with?("#{prefix}::", "#{prefix}#", "#{prefix}.") }
    end
    raise "Generated API reference exposes non-public APIs: #{non_public.join(", ")}" unless non_public.empty?
  end

  def generate
    YARD::Registry.clear
    YARD::Parser::SourceParser.parse(SOURCE_FILES)
    namespaces, constants = catalogue_entries
    validate_paths(paths_for(namespaces, constants))

    JSON.pretty_generate(
      "schemaVersion" => 1,
      "generator" => {"name" => "YARD", "version" => YARD::VERSION},
      "package" => "verifiabl-issuer",
      "namespaces" => namespaces.sort_by { |namespace| namespace.fetch("path") },
      "constants" => constants.sort_by { |constant| constant.fetch("path") }
    ) << "\n"
  end
end

check = ARGV == ["--check"]
abort "Usage: #{File.basename($PROGRAM_NAME)} [--check]" unless ARGV.empty? || check

reference = ApiReference.generate
if check
  abort "Generated Ruby API reference is stale. Run: bundle exec ruby script/api_reference.rb" unless File.exist?(OUTPUT) && File.read(OUTPUT) == reference

  puts "Generated Ruby API reference is current."
else
  FileUtils.mkdir_p(File.dirname(OUTPUT))
  File.write(OUTPUT, reference)
  puts "Generated Ruby API reference with #{JSON.parse(reference).fetch("namespaces").length} namespaces."
end
