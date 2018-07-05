module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module IO
          class SftpNativeDownload < Base
            UnknownEventError = Class.new(::RuntimeError)
            attr_reader :downloader

            def init
              @label = "downloading"
              @entity = "download"
              @throughput.categories << :inet << :inet_down
            end

            def reset_state
              super
              @downloader = nil
            end

            def build_sftp_command src, dst
              [].tap{|cmd|
                cmd << %{sftp}
                cmd << %{-P #{@ctn.source["ssh"]["port"]}} if @ctn.source["ssh"]["port"]
                @ctn.ssh_key_files.each {|f| cmd << %{-i "#{f}"} }
                cmd << %{"#{@ctn.source["ssh"]["username"]}@#{@ctn.source["ssh"]["hostname"]}:#{src}"}
                cmd << %{"#{dst}"}
              }.join(" ").strip
            end

            def download! opts = {}
              opts = opts.reverse_merge(tries: 3, read_size: @read_size, force_new_connection: true)
              cmd = build_sftp_command(@remote, @local)
              prepare_local_destination

              execute(opts.slice(:tries).merge(sleep_error: 3)) do
                begin
                  @state = :init
                  @ctn.sftp_start(opts[:force_new_connection]) do |sftp|
                    @filesize = sftp.lstat!(@remote).size
                  end

                  # status thread
                  status_thread = @worker.app.spawn_thread(:sklaventreiber_worker_ctrl) do |thr|
                    loop do
                      @offset = File.size(@local) if File.exist?(@local)
                      break if thr[:stop]
                      thr.wait(0.25)
                    end
                  end

                  @state = :downloading
                  debug "Opening process `#{cmd}'"
                  Open3.popen2e(cmd, pgroup: true) do |_stdin, _stdouterr, _thread|
                    # close & exit status
                    _stdin.close_write
                    exit_status = _thread.value
                    if exit_status == 0
                      debug "Process exited (#{exit_status}) `#{cmd}'"
                    else
                      warning "Process exited (#{exit_status}) `#{cmd}'"
                    end
                  end

                  status_thread[:stop] = true
                  status_thread.signal
                  status_thread.join
                ensure
                  @state = :finishing
                end
              end
              @state = :done
            end
          end
        end
      end
    end
  end
end
