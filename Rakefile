require 'erb'
require 'active_record'
require 'pg'

namespace :db do
  env = ENV.fetch('APP_ENV', 'development')
  content = File.read('config/database.yml')
  evaluated_yaml = ERB.new(content).result
  db_config       = YAML::load(evaluated_yaml, aliases: true)[env]
  db_config_admin = db_config.merge({'database' => 'postgres', 'schema_search_path' => 'public'})

  desc "Create the database"
  task :create do
    ActiveRecord::Base.establish_connection(db_config_admin)
    ActiveRecord::Base.connection.create_database(db_config["database"])
    puts "Database #{db_config["database"]} created."
  end

  desc "Migrate the database"
  task :migrate do
    ActiveRecord::Base.establish_connection(db_config)
    ActiveRecord::MigrationContext.new("db/migrate/").migrate
    Rake::Task["db:schema"].invoke
    puts "Database migrated."
  end

  desc "Drop the database"
  task :drop do
    ActiveRecord::Base.establish_connection(db_config_admin)
    ActiveRecord::Base.connection.drop_database(db_config["database"])
    puts "Database #{db_config["database"]} dropped."
  end

  desc "Seed the database"
  task :seed do
    ActiveRecord::Base.establish_connection(db_config)
    ActiveRecord::Base.connection.execute(File.read("./db/seeds/seed.sql"))
    puts "Database #{db_config["database"]} seeded."
  end

  desc "Create the database if missing and run pending migrations, safe to run from several instances at once"
  task :prepare do
    lock = PG.connect(host: db_config['host'], port: db_config['port'], user: db_config['username'],
                      password: db_config['password'], dbname: 'postgres')
    lock.exec_params('SELECT pg_advisory_lock(hashtext($1))', ["db:prepare #{db_config['database']}"])

    ActiveRecord::Base.establish_connection(db_config_admin)
    begin
      ActiveRecord::Base.connection.create_database(db_config["database"])
      puts "Database #{db_config["database"]} created."
    rescue ActiveRecord::DatabaseAlreadyExists
    end

    ActiveRecord::Base.establish_connection(db_config)
    ActiveRecord::MigrationContext.new("db/migrate/").migrate
    puts "Database #{db_config["database"]} migrated."
  ensure
    lock&.close
  end

  desc "Reset the database"
  task :reset => [:drop, :create, :migrate]

  desc 'Create a db/schema.rb file that is portable against any DB supported by AR'
  task :schema do
    ActiveRecord::Base.establish_connection(db_config)
    require 'active_record/schema_dumper'
    filename = "db/schema.rb"
    File.open(filename, "w:utf-8") do |file|
      pool = ActiveRecord::Base.connection_pool
      ActiveRecord::SchemaDumper.dump(pool, file)
    end
  end
end

namespace :g do
  desc "Generate migration"
  task :migration do
    name = ARGV[1] || raise("Specify name: rake g:migration your_migration")
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    path = File.expand_path("../db/migrate/#{timestamp}_#{name}.rb", __FILE__)
    migration_class = name.split("_").map(&:capitalize).join

    File.open(path, 'w') do |file|
      file.write <<-EOF
class #{migration_class} < ActiveRecord::Migration[8.1]
  def self.up
  end
  def self.down
  end
end
      EOF
    end

    puts "Migration #{path} created"
    abort # needed stop other tasks
  end
end
