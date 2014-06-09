require 'open3'

module VagrantPlugins
  module ProviderKvm
    module Util
      module Commands
        def run_root_command(cmd)
          # FIXME detect whether 'sudo' or 'su -c'
          # for safety, we run cmd as single argument of sudo
          unless res = system('sudo ' + cmd)
            raise Errors::KvmFailedCommand, cmd: cmd, res: res
          end
        end

        def run_command(cmd)
          stdout, stderr, status = Open3.capture3(cmd)
          unless status.success?
            raise Errors::KvmFailedCommand, cmd: cmd, res: status.exitstatus, stdout: stdout, stderr: stderr
          end
          stdout
        end
      end
    end
  end
end

