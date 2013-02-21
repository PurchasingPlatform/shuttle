module Shuttle
  class Rails < Shuttle::Deploy
    include Shuttle::Support::Bundler
    include Shuttle::Support::RVM
    include Shuttle::Support::Thin

    def rails_env
      environment
    end

    def setup_bundler
      if !bundler_installed?
        info "Bundler is missing. Installing"
        rer = ssh.run("gem install bundler")
        if res.success?
          info "Bundler v#{bundler_version} installed"
        else
          error "Unable to install bundler: #{res.output}"
        end
      end
    end

    def rake(command)
      res = ssh.run("cd #{release_path} && rake #{command}")
      if res.failure?
        error "Unable to run rake command: #{command}. Reason: #{res.output}"
      end
    end

    def deploy
      ssh.export('RACK_ENV', environment)
      ssh.export('RAILS_ENV', environment)

      setup
      setup_bundler
      update_code
      checkout_code
      bundle_install
      migrate_database

      log "Precompiling assets"
      rake 'assets:precompile'
      
      thin_restart

      link_shared_paths
      link_release
      cleanup_releases
    end

    def migrate_database
      return if !ssh.file_exists?(release_path('db/schema.rb'))

      migrate     = true # Will migrate by default
      schema      = ssh.read_file(release_path('db/schema.rb'))
      schema_file = shared_path('schema')
      checksum    = Digest::SHA1.hexdigest(schema)

      if ssh.file_exists?(schema_file)
        old_checksum = ssh.read_file(schema_file).strip
        if old_checksum == checksum
          migrate = false
        end
      end

      if migrate == true
        log "Migrating database"
        rake 'db:migrate'
        ssh.run("echo #{checksum} > #{schema_file}")
      else
        log "Database migration skipped"
      end
    end

    def link_shared_paths
      ssh.run("mkdir -p #{release_path('tmp')}")
      ssh.run("rm -rf #{release_path}/log")
      ssh.run("ln -s #{shared_path('pids')} #{release_path('tmp/pids')}")
      ssh.run("ln -s #{shared_path('log')} #{release_path('log')}")

      if config.rails
        if config.rails.shared_paths
          config.rails.shared_paths.each_pair do |name, path|
            log "Linking shared path: #{name}"
            ssh.run("ln -s #{shared_path}/#{name} #{release_path}/#{path}")
          end
        end
      end
    end
  end
end