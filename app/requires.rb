require 'active_record'
require 'erb'
require 'yaml'
require 'json'
require 'rack'
require 'digest'

env = ENV.fetch('APP_ENV', 'development')
content = File.read('config/database.yml')
evaluated_yaml = ERB.new(content).result
db_config       = YAML::load(evaluated_yaml, aliases: true)[env]
ActiveRecord::Base.establish_connection(db_config)
#ActiveRecord::Base.logger = Logger.new(STDOUT)

require './app/models/firm.rb'
require './app/models/payment_batch.rb'
require './app/models/payment.rb'
require './app/services/process_payments.rb'
require './app/exceptions.rb'
require 'pry' if env == 'development'
