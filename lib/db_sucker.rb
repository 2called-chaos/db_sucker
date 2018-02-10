module DbSucker
  ROOT = File.expand_path("../..", __FILE__)
end

# stdlib
require "benchmark"
require "fileutils"
require "thread"
require "monitor"
require "pathname"
require "yaml"
require "ostruct"
require "optparse"
require "securerandom"
require "open3"
require "shellwords"
require "net/http"

# 3rd party
require "curses"
require "active_support"
require "active_support/core_ext"
require "active_support/time_with_zone"
require "net/ssh"
require "net/sftp"

# application
require "db_sucker/version"
require "db_sucker/application/tie"
require "db_sucker/application/output_helper"
require "db_sucker/application/sklaven_treiber/log_spool"
require "db_sucker/application/sklaven_treiber/worker/io/base"
require "db_sucker/application/sklaven_treiber/worker/io/throughput"
require "db_sucker/application/sklaven_treiber/worker/io/sftp_download"
require "db_sucker/application/sklaven_treiber/worker/io/file_copy"
require "db_sucker/application/sklaven_treiber/worker/io/file_gunzip"
require "db_sucker/application/sklaven_treiber/worker/io/file_shasum"
require "db_sucker/application/sklaven_treiber/worker/io/file_import_sql"
require "db_sucker/application/sklaven_treiber/worker/io/pv_wrapper"
require "db_sucker/application/sklaven_treiber/worker/core"
require "db_sucker/application/sklaven_treiber/worker/accessors"
require "db_sucker/application/sklaven_treiber/worker/helpers"
require "db_sucker/application/sklaven_treiber/worker/routines"
require "db_sucker/application/sklaven_treiber/worker"
require "db_sucker/application/sklaven_treiber"
require "db_sucker/application/window/core"
require "db_sucker/application/window/keypad/core"
require "db_sucker/application/window/keypad"
require "db_sucker/application/window/prompt"
require "db_sucker/application/window/dialog"
require "db_sucker/application/window"
require "db_sucker/application/container/accessors"
require "db_sucker/application/container/validations"
require "db_sucker/application/container/variation/accessors"
require "db_sucker/application/container/variation/helpers"
require "db_sucker/application/container/variation/worker_api"
require "db_sucker/application/container/variation"
require "db_sucker/application/container/ssh"
require "db_sucker/application/container"
require "db_sucker/application/container_collection"
require "db_sucker/application/dispatch"
require "db_sucker/application/colorize"
require "db_sucker/application/slot_pool"
require "db_sucker/application/evented_resultset"
require "db_sucker/application/fake_channel"
require "db_sucker/application/core"
require "db_sucker/application"

# adapters
require "db_sucker/adapters/mysql2"

# patches
require "db_sucker/patches/net-sftp"
require "db_sucker/patches/beta-warning"
if ENV["DBS_DEVELOPER"] && ENV["DBS_DEVELOPER"] != "false"
  require "pry"
  require "pry-remote"
  require "db_sucker/patches/developer"
  require "db_sucker/patches/thread-count"
end
