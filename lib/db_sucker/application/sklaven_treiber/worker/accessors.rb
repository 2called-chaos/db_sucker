module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module Accessors
          def pending?
            @state == :pending
          end

          def done?
            succeeded? || failed? || canceled?
          end

          def sshing?
            @sshing
          end

          def failed?
            @state == :failed
          end

          def succeeded?
            @state == :done
          end

          def canceled?
            @state == :canceled
          end

          def running?
            @state == :running
          end

          def paused?
            @state == :paused
          end

          def pausing?
            @state == :pausing
          end

          def deferred?
            @deferred
          end

          def status
            @status
          end

          def state
            @state
          end

          def trxid
            sklaventreiber.trxid
          end

          def app
            sklaventreiber.app
          end

          def descriptive
            "#{ctn.source["database"]}-#{table}"
          end

          def identifier
            "#{trxid}_table"
          end

          def to_s
            "#<#{self.class}:#{self.object_id}-#{descriptive}(#{@state})>"
          end

          def tmp_filename tmp_suffix = false
            "#{ctn.tmp_path}/#{trxid}_#{ctn.source["database"]}_#{table}.dbsc#{".tmp" if tmp_suffix}"
          end

          def local_tmp_path
            sklaventreiber.app.core_tmp_path
          end

          def local_tmp_file file
            "#{local_tmp_path}/#{file}"
          end

          def spinner_frame
            @spinner_frames.unshift(@spinner_frames.pop)[0]
          end

          def copy_file_destination dstfile
            d, dt = Time.current.strftime("%Y-%m-%d"), Time.current.strftime("%H-%M-%S")

            File.expand_path dstfile.dup
              .gsub(":combined", ":datetime_-_:table")
              .gsub(":datetime", "#{d}_#{dt}")
              .gsub(":date", d)
              .gsub(":time", dt)
              .gsub(":table", table)
              .gsub(":id", sklaventreiber.trxid)
          end
        end
      end
    end
  end
end
