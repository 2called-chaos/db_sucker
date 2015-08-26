module DbSucker
  class Configuration
    class Variation
      attr_reader :cfg, :name, :data

      def initialize cfg, name, data
        @cfg, @name, @data = cfg, name, data

        if data["base"]
          bdata = cfg.variation(data["base"]) || raise("variation `#{name}' cannot base from `#{data["base"]}' since it doesn't exist in #{cfg.src}")
          @data = data.reverse_merge(bdata.data)
        end
      end

      def label
        data["label"]
      end

      def incrementals
        data["incremental"] || {}
      end

      def tables_to_transfer
        all = cfg.mysql_table_list(cfg.data["source"]["database"]).map(&:first)
        keep = []
        if data["only"]
          [*data["only"]].each do |t|
            raise "unknown table `#{t}' for variation `#{cfg.name}/#{name}' in #{cfg.src}" unless all.include?(t)
            keep << t
          end
        elsif data["except"]
          keep = all
          [*data["except"]].each do |t|
            raise "unknown table `#{t}' for variation `#{cfg.name}/#{name}' in #{cfg.src}" unless all.include?(t)
            keep.delete(t)
          end
        else
          keep = all
        end

        keep
      end

      def dump_command_for tables
        [].tap do |r|
          r << "mysqldump"
          r << "-h#{cfg.data["source"]["hostname"]}" unless cfg.data["source"]["hostname"].blank?
          r << "-u#{cfg.data["source"]["username"]}" unless cfg.data["source"]["username"].blank?
          r << "-p#{cfg.data["source"]["password"]}" unless cfg.data["source"]["password"].blank?
          r << cfg.data["source"]["database"]
          r << tables.join(" ")
          r << "#{cfg.data["source"]["args"]}"
        end.join(" ")
      end

      def load_command_for file
        [].tap do |r|
          r << "mysql"
          r << "-h#{data["hostname"]}" unless data["hostname"].blank?
          r << "-u#{data["username"]}" unless data["username"].blank?
          r << "-p#{data["password"]}" unless data["password"].blank?
          r << data["database"]
          r << "#{data["args"]}"
          r << " < #{file}"
        end.join(" ")
      end

      def dump_to_remote worker, blocking = true
        cmd = dump_command_for([worker.table])
        cmd << " > #{worker.tmp_filename(true)}"
        [worker.tmp_filename(true), cfg.blocking_channel_result(cmd, channel: true, blocking: blocking)]
      end

      def compress_file file, blocking = true
        cmd = %{gzip #{file}}
        ["#{file}.gz", cfg.blocking_channel_result(cmd, channel: true, blocking: blocking)]
      end

      def channelfy_thread t
        def t.active?
          alive?
        end

        def t.closed?
          alive?
        end

        def t.closing?
          !alive?
        end

        t
      end

      def decompress_file file
        cmd = %{gunzip #{file}}
        t = channelfy_thread(Thread.new{ system("#{cmd}") })
        [file[0..-4], t]
      end

      def wait_for_workers
        channelfy_thread Thread.new {
          loop do
            Thread.current[:workers] = $importing.synchronize { $importing.length }
            break if Thread.current[:workers] == 0
            sleep 1
          end
        }
      end

      def transfer_remote_to_local remote_file, local_file, blocking = true, &block
        FileUtils.mkdir_p(File.dirname(local_file))
        cfg.sftp_start(true) do |sftp|
          sftp.download!(remote_file, local_file, read_size: 5 * 1024 * 1024, &block)
        end
      end

      def load_local_file worker, file, &block
        if data["importer"] == "void10"
          t = channelfy_thread Thread.new{ sleep 10 }
        # elsif data["importer"] == "sequel"
        #   t = channelfy_thread Thread.new {
        #     Thread.current[:importer] = imp = SequelImporter.new(worker, file)
        #     imp.start
        #   }
        else
          t = channelfy_thread Thread.new{ system("#{load_command_for file}") }
        end

        block.call(data["importer"], t)
      end

      def copy_file worker, srcfile
        d, dt = Time.current.strftime("%Y-%m-%d"), Time.current.strftime("%H-%M-%S")
        bfile = data["file"]
        bfile = bfile.gsub(":date", d)
        bfile = bfile.gsub(":time", dt)
        bfile = bfile.gsub(":datetime", "#{d}_#{dt}")
        bfile = bfile.gsub(":table", worker.table)
        bfile = bfile.gsub(":id", worker.id)
        bfile = File.expand_path(bfile)
        bfile = "#{bfile}.gz" if data["gzip"] && !bfile.end_with?(".gz")
        bfile = bfile[0..-4] if !data["gzip"] && bfile.end_with?(".gz")
        t = Thread.new{
          FileUtils.mkdir_p(File.basename(bfile))
          FileUtils.copy_file(srcfile, bfile)
        }
        [bfile, channelfy_thread(t)]
      end

      def dump_to_local_stream
        raise NotImplemented
      end
    end
  end
end

__END__

# ==================
# = SOURCE OPTIONS =
# ==================
X> base: default
X> incremental:
     this_table: column_name # usually ID
X> only: [orders, order_items]
X> except: [orders, order_items]


# ======
# = DB =
# ======
X> database: DATABASE_NAME
X> hostname: localhost
X> username: root
X> password: SECRET
X> args:


# ========
# = FILE =
# ========
~> file: /home/backup/database-%Y-%m-%d.sql
~> gzip: yes
