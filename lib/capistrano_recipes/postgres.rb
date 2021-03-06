require 'capistrano_recipes/utils'
require 'securerandom'

Capistrano::Configuration.instance.load do
  # Postgres user name
  _cset(:database_user) { "#{fetch(:deploy_user, user)}" }
  # Postgres database name
  _cset(:database_name) { "#{application}" }
  # Path to the rails database erb template to be parsed before uploading to remote server
  _cset(:database_config_template) { "database.yml.erb" }
  # Path to where your remote rails database config will reside
  # (it will be symlinked to +#{current_release}/config/database.yml+ on each deploy)
  _cset(:database_config_path) { "#{shared_path}/config/database.yml" }

  namespace :db do
    def upload_config
      run "#{sudo} -u #{deploy_user} mkdir -p #{File.dirname(database_config_path)} && " \
          "#{sudo} touch #{database_config_path} && " \
          "#{sudo} chown #{user} #{database_config_path} && " \
          "#{sudo} chmod 770 #{database_config_path}"

      generate_config(database_config_template, database_config_path)

      run "#{sudo} chown #{deploy_user}:#{group} #{database_config_path} && " \
          "#{sudo} chmod 440 #{database_config_path}"
    end

    def create_db_user
      run "echo \"" \
          "CREATE USER #{database_user} WITH PASSWORD '#{database_password}';" \
          "CREATE DATABASE #{database_name};" \
          "GRANT ALL PRIVILEGES ON DATABASE #{database_name} TO #{database_user};" \
          "\" | #{sudo} -u postgres psql"
    end

    desc "Parses config file and outputs it to STDOUT (internal task)"
    task :parse_config, :roles => :app , :except => { :no_release => true } do
      puts parse_template(database_config_template)
    end

    desc <<-EOF
    Creates database user, database, grants user administrative privileges on this database, creates
    database config.
    EOF
    host_task :setup_host do
      if remote_file_exists?(database_config_path)
        logger.important "Skipping creating DB config, file already exists: #{database_config_path}"
      else
        password_prompt_with_default :database_password, SecureRandom.urlsafe_base64
        create_db_user
        upload_config
      end
    end
  end

  after 'host:setup' do
    db.setup_host #if Capistrano::CLI.ui.agree("Create database config? [y/n]")
  end
end

