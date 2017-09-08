# Monkeypatch™ Net::SFTP download to stop current file if requested to do so

module DbSucker
  module Patches
    module SftpStopDownload
      def on_read response
        if !active?
          response.instance_eval do
            def eof?
              true
            end
          end
        end
        super(response)
      end
    end
  end
end

Net::SFTP::Operations::Download.prepend(DbSucker::Patches::SftpStopDownload)
