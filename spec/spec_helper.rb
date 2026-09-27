require 'rake'
ENV['APP_ENV'] = 'test'

# reset db with Rake
rake = Rake::Application.new
Rake.application = rake
rake.load_rakefile
Rake::Task["db:reset"].invoke

#ActiveRecord::Base.logger = Logger.new(STDOUT)

RSpec.configure do |config|
  config.around(:each) do |example|
    Payment.delete_all
    PaymentBatch.delete_all
    Firm.delete_all
    example.run
  end
end

def seed_data
  ActiveRecord::Base.connection.execute(File.read("./db/seeds/seed.sql"))
end

require './app.rb'

App.logger = Logger.new(File::NULL)
