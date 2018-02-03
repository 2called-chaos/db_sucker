module DbSucker
  module Adapters
    module Mysql2
      module Api
        def self.require_dependencies
          begin; require "mysql2"; rescue LoadError; end
        end

        def client_binary
          source["client_binary"] || "mysql"
        end

        def local_client_binary
          data["client_binary"] || "mysql"
        end

        def dump_binary
          source["dump_binary"] || "mysqldump"
        end

        def client_call
          [].tap do |r|
            r << "#{client_binary}"
            r << "-u#{source["username"]}" if source["username"]
            r << "-p#{source["password"]}" if source["password"]
            r << "-h#{source["hostname"]}" if source["hostname"]
          end * " "
        end

        def local_client_call
          [].tap do |r|
            r << "#{local_client_binary}"
            r << "-u#{data["username"]}" if data["username"]
            r << "-p#{data["password"]}" if data["password"]
            r << "-h#{data["hostname"]}" if data["hostname"]
          end * " "
        end

        def dump_call
          [].tap do |r|
            r << "#{dump_binary}"
            r << "-u#{source["username"]}" if source["username"]
            r << "-p#{source["password"]}" if source["password"]
            r << "-h#{source["hostname"]}" if source["hostname"]
          end * " "
        end

        def dump_command_for table
          [].tap do |r|
            r << dump_call
            if c = constraint(table)
              r << "--compact --skip-extended-insert --no-create-info --complete-insert"
              r << Shellwords.escape("-w#{c}")
            end
            r << source["database"]
            r << table
            r << "#{source["args"]}"
          end * " "
        end

        def import_instruction_for file, flags = {}
          {}.tap do |instruction|
            instruction[:bin] = [local_client_call, data["database"], data["args"]].join(" ")
            instruction[:file] = file
            if flags[:dirty] && flags[:deferred]
              instruction[:file_prepend] = %{
                  echo "SET AUTOCOMMIT=0;"
                  echo "SET UNIQUE_CHECKS=0;"
                  echo "SET FOREIGN_KEY_CHECKS=0;"
              }
              instruction[:file_append] = %{
                  echo "SET FOREIGN_KEY_CHECKS=1;"
                  echo "SET UNIQUE_CHECKS=1;"
                  echo "SET AUTOCOMMIT=1;"
                  echo "COMMIT;"
              }
            end
          end
        end

        def database_list include_tables = false
          dbs = blocking_channel_result(%{#{client_call} -N -e 'SHOW DATABASES;'}).for_group(:stdout).join("").split("\n")

          if include_tables
            dbs.map do |db|
              [db, table_list(db)]
            end
          else
            dbs
          end
        end

        def table_list database
          blocking_channel_result(%{#{client_call} -N -e 'SHOW FULL TABLES IN #{database};'}).for_group(:stdout).join("").split("\n").map{|r| r.split("\t") }
        end

        def hostname
          blocking_channel_result(%{#{client_call} -N -e 'select @@hostname;'}).for_group(:stdout).join("").strip
        end
      end
    end
  end
end
