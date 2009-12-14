require 'jeweler'

Jeweler::Tasks.new do |s|
	s.name = "sumo"
	s.description = "A no-hassle way to launch one-off EC2 instances from the command line"
	s.summary = s.description
	s.author = "Adam Wiggins"
	s.email = "adam@heroku.com"
	s.homepage = "http://github.com/adamwiggins/sumo"
	s.rubyforge_project = "sumo"
	s.files = FileList["[A-Z]*", "{bin,lib,spec}/**/*"]
	s.executables = %w(sumo)
	s.add_dependency "amazon-ec2"
	s.add_dependency "thor"
end

Jeweler::RubyforgeTasks.new

require 'micronaut/rake_task'
Micronaut::RakeTask.new(:spec) do |examples|
  examples.pattern = 'spec/**/*_spec.rb'
  examples.ruby_opts << '-Ilib -Ispec'
end

task :default => :spec

