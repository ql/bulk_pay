require 'rake'
ENV['APP_ENV'] = 'test'

rake = Rake::Application.new
Rake.application = rake
rake.load_rakefile
Rake::Task["db:reset"].invoke

#ActiveRecord::Base.logger = Logger.new(STDOUT)
RSpec.configure do |config|
  config.around(:each) do |example|
    Payment.delete_all
    Firm.delete_all
    ActiveRecord::Base.connection.execute(File.read("./db/seeds/seed.sql"))
    example.run
  end
end

require './app/app.rb'
