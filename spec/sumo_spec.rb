require File.dirname(__FILE__) + '/base'

require 'fileutils'

describe Sumo do
	before do
		@work_path = "/tmp/spec_#{Process.pid}/"
		FileUtils.mkdir_p(@work_path)
		File.open("#{@work_path}/config.yml", "w") do |f|
			f.write YAML.dump({})
		end

		@sumo = Sumo.new
		@sumo.stubs(:sumo_dir).returns(@work_path)
	end

	after do
		FileUtils.rm_rf(@work_path)
	end

	it "defaults to user root if none is specified in the config" do
		@sumo.config['user'].should == 'root'
	end

	it "uses specified user if one is in the config" do
		File.open("#{@work_path}/config.yml", "w") do |f|
			f.write YAML.dump('user' => 'joe')
		end
		@sumo.config['user'].should == 'joe'
	end
	
	describe "prep_ssh_commands" do
	  it "joins them" do
	    @sumo.prepare_commands(["ls", "echo 'hi'"]).should == "ls && echo 'hi'"
    end
    
    it "logs them to ssh.log" do
      @sumo.prepare_commands(["cd foo", "ruby baz.rb"])
      File.read("#{@work_path}/ssh.log").should include("cd foo && ruby baz.rb")
    end
  end
end
