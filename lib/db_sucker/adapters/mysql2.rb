module DbSucker
  module Adapters
    module Mysql2
      begin; require "mysql2"; rescue LoadError; end

      module RPC
        def binary
          data["source"]["binary"] || "mysql"
        end

        def client_call
          [].tap do |r|
            r << "#{binary}"
            r << "-u #{data["source"]["username"]}" if data["source"]["username"]
            r << "-p#{data["source"]["password"]}" if data["source"]["password"]
            r << "-h #{data["source"]["hostname"]}" if data["source"]["hostname"]
          end * " "
        end

        def database_list include_tables = false
          dbs = blocking_channel_result(%{#{client_call} -N -e 'SHOW DATABASES;'}).join("").split("\n")

          if include_tables
            dbs.map do |db|
              [db, table_list(db)]
            end
          else
            dbs
          end
        end

        def table_list database
          blocking_channel_result(%{#{client_call} -N -e 'SHOW FULL TABLES IN #{database};'}).join("").split("\n").map{|r| r.split("\t") }
        end

        def hostname
          blocking_channel_result(%{#{client_call} -N -e 'select @@hostname;'}).join("").strip
        end
      end
    end
  end
end
