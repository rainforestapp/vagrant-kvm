require 'spec_helper'

module VagrantPlugins::ProviderKvm
  describe VagrantPlugins::ProviderKvm::Util::Commands do
    subject do
      Class.new do
        include Util::Commands
      end.new
    end

    describe "#run_command" do
      it "raises an error on wrong exit code" do
        expect do
          subject.run_command("exit 1")
        end.to raise_error(Errors::KvmFailedCommand)
      end

      it "returns the standard output" do
        subject.run_command("echo test").should == "test\n"
      end
    end
  end
end
