source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in semtools.gemspec
gemspec

gem "rake", "~> 13.0"
gem "minitest", "~> 5.0"

expcalc_dev_path = File.expand_path('~/dev_gems/expcalc')
gem "expcalc", github: "seoanezonjic/expcalc", branch: "master" if Dir.exist?(expcalc_dev_path)