require File.join(File.dirname(__FILE__), 'spec_helper')

describe Sumo do
	before do
	end

	after do
	end

	it "defaults to user ubuntu if none is specified in the config" do
		sumo = Sumo::Instance.new :name => "test"
		sumo.user.should == 'ubuntu'
	end

	it "defaults to user can be overwritten on new" do
		sumo = Sumo::Instance.new :name => "test", :user => "root"
		sumo.user.should == 'root'
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
