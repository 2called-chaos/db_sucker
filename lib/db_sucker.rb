

# require "pathname"
require "yaml"
require "ostruct"
require "optparse"
require "securerandom"
require "active_support"
require "active_support/core_ext"
require "net/http"
require "net/ssh"
require "net/sftp"
require "active_support"
begin ; require "pry" ; rescue LoadError ; end

require "banana/logger"
require "db_sucker/version"
require "db_sucker/helpers"
require "db_sucker/application/logger_client"
require "db_sucker/configuration/worker"
require "db_sucker/configuration/rpc"
require "db_sucker/configuration/container"
require "db_sucker/configuration/variation"
require "db_sucker/configuration"
require "db_sucker/sequel_importer"
require "db_sucker/application/dispatch"
require "db_sucker/application"

module DbSucker
  ROOT = Pathname.new(File.expand_path("../..", __FILE__))
  BASH_ENABLED = "#{ENV["SHELL"]}".downcase["bash"]
end
