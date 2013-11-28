module VagrantPlugins
  module ProviderKvm
    module Action
      class PrepareGui
        def initialize(app, env)
          @app = app
        end

        def call(env)
          config = env[:machine].provider_config
          if config.gui
            driver = env[:machine].provider.driver
            driver.set_gui(config.vnc_port, config.vnc_autoport, config.vnc_password)
          end
          @app.call(env)
        end
      end
    end
  end
end
