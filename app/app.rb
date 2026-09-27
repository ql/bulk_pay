require 'active_record'

env = ENV.fetch('APP_ENV', 'development')
content = File.read('config/database.yml')
evaluated_yaml = ERB.new(content).result
db_config       = YAML::load(evaluated_yaml, aliases: true)[env]
ActiveRecord::Base.establish_connection(db_config)

require './app/models/firm.rb'
require './app/models/payment.rb'
require './app/services/process_payments.rb'
require './app/exceptions.rb'
require 'pry' if env == 'development'
