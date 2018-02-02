module DbSucker
  class Application
    class SklavenTreiber
      class Worker
        module Helpers
          def runtime
            if @started
              human_seconds ((@ended || Time.current) - @started).to_i
            end
          end

          def sftp_download *args, &block
            IO::SftpDownload.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def file_copy *args, &block
            IO::FileCopy.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def file_gunzip *args, &block
            IO::FileGunzip.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def file_shasum *args, &block
            IO::Shasum.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def pv_wrap *args, &block
            IO::PvWrapper.new(self, *args).tap do |op|
              block.try(:call, op)
            end
          end

          def aquire_slots *which, &block
            target_thread = Thread.current
            aquired = []
            which.each_with_index do |wh, i|
              if pool = sklaventreiber.slot_pools[wh]
                waitlock = Queue.new
                channel = app.channelfy_thread app.spawn_thread(:sklaventreiber_worker_slot_progress) {|thr|
                  thr[:current_task] = target_thread[:current_task] if target_thread[:current_task]
                  thr[:slot_pool_qindex] = Proc.new { pool.qindex(target_thread) }
                  waitlock.pop
                  pool.aquire(target_thread)
                }
                waitlock << true
                target_thread.wait

                label = "aquiring slot #{i+1}/#{which.length} `#{pool.name}' :slot_pool_qindex(– #%s in queue )(:seconds)..."
                second_progress(channel, label, :blue).tap{ pool.wait_aquired(target_thread) }.join
                if pool.aquired?(target_thread)
                  aquired << wh
                else
                  break
                end
              else
                raise SlotPoolNotInitializedError, "slot pool `#{wh}' was never initialized, can't aquire slot"
              end
            end
            block.call if block && (which - aquired).empty?
          ensure
            release_slots(*which)
          end

          def release_slots *which
            which.each_with_index do |wh, i|
              if pool = sklaventreiber.slot_pools[wh]
                pool.release(Thread.current)
              else
                raise SlotPoolNotInitializedError, "slot pool `#{wh}' was never initialized, can't release slot (was most likely never aquired)"
              end
            end
          end

          def wait_defer_ready label = nil
            channel = app.fake_channel {|c| c[:slot_pool_qindex].call.zero? || @should_cancel }
            channel[:slot_pool_qindex] = Proc.new { sklaventreiber.sync { sklaventreiber.workers.count{|w| !w.done? && !w.deferred? } } }

            label = "deferred import: #{human_bytes(File.size(@local_file_raw))} raw SQL :slot_pool_qindex(– waiting for %s workers )(:seconds)"
            second_progress(channel, label, :blue).join
          end

          def second_progress channel, status, color = :yellow
            target_thread = Thread.current
            app.spawn_thread(:sklaventreiber_worker_second_progress) do |thr|
              thr[:iteration] = 0
              thr[:started_at] = Time.current
              thr[:current_task] = target_thread[:current_task] if target_thread[:current_task]
              channel[:handler] = thr if channel.respond_to?(:[]=)
              loop do
                if @should_cancel && !thr[:canceled]
                  if channel.is_a?(Net::SSH::Connection::Channel)
                    if channel[:pty]
                      channel.send_data("\C-c") rescue false
                    elsif channel[:pid]
                      @ctn.kill_remote_process(channel[:pid])
                    end
                  end
                  channel.try(:close) rescue false
                  Process.kill(:SIGINT, channel[:ipc_thread].pid) if channel[:ipc_thread]
                  thr[:canceled] = true
                end
                stat = status.gsub(":seconds", human_seconds(Time.current - thr[:started_at]))
                if channel[:slot_pool_qindex].respond_to?(:call)
                  qi = channel[:slot_pool_qindex].call
                  re = /:slot_pool_qindex\(([^\)]+)\)/
                  if stat[re]
                    stat[re] = qi ? stat[re].match(/\(([^\)]+)\)/)[1].gsub("%s", qi.to_s) : ""
                  end
                end
                if channel[:error_message]
                  @status = ["[ERROR] #{channel[:error_message]}", :red]
                elsif !channel.active?
                  @status = ["[CLOSED] #{stat}", :red]
                elsif channel.closing?
                  @status = ["[CLOSING] #{stat}", :red]
                else
                  @status = [stat, color]
                end
                break unless channel.active?
                thr.wait(0.1)
                thr[:iteration] += 1
              end
            end
          end
        end
      end
    end
  end
end
