require "bundler/gem_tasks"
require "rake/testtask"
require 'rdoc/task'

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

RDoc::Task.new do |rdoc|
  rdoc.main = "README.doc"
  rdoc.rdoc_files.include("README.md", "lib/*.rb", "lib/semtools/*.rb")
  rdoc.options << "--all"
end

task :default => :test
