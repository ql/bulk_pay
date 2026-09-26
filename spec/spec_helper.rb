require 'rake'
ENV['APP_ENV'] = 'test'

rake = Rake::Application.new
Rake.application = rake
rake.load_rakefile
Rake::Task["db:reset"].invoke
Rake::Task["db:seed"].invoke

require './app/app.rb'
