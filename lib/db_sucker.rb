STDIN.sync = true
STDOUT.sync = true

# stdlib
require "benchmark"
require "optparse"
require "fileutils"
require "curses"
require "thread"
require "monitor"
require "pathname"
require "yaml"
require "ostruct"
require "optparse"
require "securerandom"
require "open3"
require "net/http"

# 3rd party
require "active_support"
require "active_support/core_ext"
require "active_support/time_with_zone"
require "net/ssh"
require "net/sftp"
require "sequel"
# require "active_support"
begin ; require "pry" ; rescue LoadError ; end

# lib
require "db_sucker/version"
# require "banana/logger"
# require "db_sucker/helpers"
# require "db_sucker/application/logger_client"
# require "db_sucker/sequel_importer"
# require "db_sucker/configuration/worker"
# require "db_sucker/configuration/rpc"
# require "db_sucker/configuration/container"
# require "db_sucker/configuration/variation"
require "db_sucker/adapters/mysql2"
require "db_sucker/application/colorize"
require "db_sucker/application/output_helper"
require "db_sucker/application/core"
require "db_sucker/application/container_collection"
require "db_sucker/application/container/ssh"
require "db_sucker/application/container/variation"
require "db_sucker/application/container"
require "db_sucker/application/dispatch"
require "db_sucker/application/sklaven_treiber/log_spool"
require "db_sucker/application/sklaven_treiber/worker"
require "db_sucker/application/sklaven_treiber"
require "db_sucker/application/window"
require "db_sucker/application"

# module DbSucker
#   ROOT = Pathname.new(File.expand_path("../..", __FILE__))
#   BASH_ENABLED = "#{ENV["SHELL"]}".downcase["bash"]
# end
