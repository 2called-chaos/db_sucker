module DbSucker
  class Configuration
    module RPC
      def ssh_begin
        debug "Opening SSH connection for identifier `#{name}'"
        @ssh = ssh_start
      end

      def ssh_end
        debug "Closing SSH connection for identifier `#{name}'"
        @ssh.try(:close) rescue false
        debug "CLOSED SSH connection for identifier `#{name}'"
        @ssh = nil
      end

      def ssh_sync &block
        @ssh_mutex.synchronize(&block)
      end

      def sftp_begin
        debug "Opening SFTP connection for identifier `#{name}'"
        @sftp = sftp_start
      end

      def sftp_end
        debug "Closing SFTP connection for identifier `#{name}'"
        @sftp.try(:close) rescue false
        debug "CLOSED SFTP connection for identifier `#{name}'"
        @sftp = nil
      end

      def sftp_sync &block
        @sftp_mutex.synchronize(&block)
      end


      # -----------------------


      def ssh_start new_connection = false, &block
        if @ssh && !new_connection
          ssh_sync do
            return block ? block.call(@ssh) : @ssh
          end
        end

        opt = {}
        opt[:password] = data["source"]["ssh"]["password"] if data["source"]["ssh"]["password"].present?
        opt[:keys] = ssh_key_files if ssh_key_files.any?
        opt[:port] = data["source"]["ssh"]["port"] if data["source"]["ssh"]["port"].present?
        if block
          Net::SSH.start(data["source"]["ssh"]["hostname"], data["source"]["ssh"]["username"], opt) do |ssh|
            block.call(ssh)
          end
        else
          Net::SSH.start(data["source"]["ssh"]["hostname"], data["source"]["ssh"]["username"], opt)
        end
      end

      def sftp_start new_connection = false, &block
        if @sftp && !new_connection
          sftp_sync do
            return block ? block.call(@sftp) : @sftp
          end
        end

        opt = {}
        opt[:password] = data["source"]["ssh"]["password"] if data["source"]["ssh"]["password"].present?
        opt[:keys] = ssh_key_files if ssh_key_files.any?
        opt[:port] = data["source"]["ssh"]["port"] if data["source"]["ssh"]["port"].present?
        if block
          Net::SFTP.start(data["source"]["ssh"]["hostname"], data["source"]["ssh"]["username"], opt) do |sftp|
            block.call(sftp)
          end
        else
          Net::SFTP.start(data["source"]["ssh"]["hostname"], data["source"]["ssh"]["username"], opt)
        end
      end

      def loop_ssh *args, &block
        return false unless @ssh
        @ssh.loop(*args, &block)
      end

      def blocking_channel ssh = nil, &block
        channel = (ssh || ssh_start).open_channel do |ch|
          block.call(ch)
        end.tap(&:wait)
      end

      def nonblocking_channel ssh = nil, &block
        (ssh || ssh_start).open_channel do |ch|
          block.call(ch)
        end
      end

      def blocking_channel_result cmd, opts = {}
        opts = opts.reverse_merge(ssh: nil, blocking: true, channel: false)
        result = []
        chan = send(opts[:blocking] ? :blocking_channel : :nonblocking_channel, opts[:ssh]) do |ch|
          ch.exec(cmd) do |ch, success|
            raise "could not execute command" unless success

            # "on_data" is called when the process writes something to stdout
            ch.on_data do |c, data|
              result << data
            end

            # "on_extended_data" is called when the process writes something to stderr
            ch.on_extended_data do |c, type, data|
              result << data
            end

            ch.on_close { }
          end
        end
        opts[:channel] ? [chan, result] : result
      end

      def nonblocking_channel_result cmd, opts = {}
        blocking_channel_result(cmd, opts.merge(blocking: false))
      end

      # ============
      # = Commands =
      # ============
      def mysql_bin
        data["source"]["mysql_bin"] || "mysql"
      end

      def mysql_authed
        [].tap do |r|
          r << "#{mysql_bin}"
          r << "-u #{data["source"]["username"]}" if data["source"]["username"]
          r << "-p#{data["source"]["password"]}" if data["source"]["password"]
          r << "-h #{data["source"]["hostname"]}" if data["source"]["hostname"]
        end * " "
      end

      def mysql_database_list include_tables = false
        dbs = blocking_channel_result(%{#{mysql_authed} -N -e 'SHOW DATABASES;'}).join("").split("\n")

        if include_tables
          dbs.map do |db|
            [db, mysql_table_list(db)]
          end
        else
          dbs
        end
      end

      def mysql_table_list database
        blocking_channel_result(%{#{mysql_authed} -N -e 'SHOW FULL TABLES IN #{database};'}).join("").split("\n").map{|r| r.split("\t") }
      end

      def mysql_hostname
        blocking_channel_result(%{#{mysql_authed} -N -e 'select @@hostname;'}).join("").strip
      end
    end
  end
end
