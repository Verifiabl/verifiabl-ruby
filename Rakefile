# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"
require "standard/rake"

GEM_ROOTS = Dir["gems/*"].select { |path| File.directory?(path) }.sort.freeze

namespace :rbs do
  desc "Validate RBS signatures"
  task :validate do
    signature_paths = GEM_ROOTS.map { |root| "-I #{root}/sig" }.join(" ")
    sh "rbs #{signature_paths} validate"
  end
end

RuboCop::RakeTask.new(:metrics) do |task|
  task.options = ["--config", ".rubocop-metrics.yml"]
end

Rake::TestTask.new do |task|
  GEM_ROOTS.each do |root|
    task.libs << "#{root}/lib"
    task.libs << "#{root}/test"
  end
  task.pattern = "gems/*/test/**/*_test.rb"
end

task default: %i[standard metrics test rbs:validate]
