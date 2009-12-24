require File.join(File.dirname(__FILE__), 'spec_helper')

describe Sumo do
  extend RR::Adapters::RRMethods
  class CheckPrivacy
    include ::Sumo
  end
  
	before do

	end

	after do
	end

  describe "inheriting classes" do
    [:custom_require, :private_require, :check_load_path, :final_require].each do |meth|
      it "must not respond to ##{meth} method" do
        CheckPrivacy.new.must_not respond_to(meth)
      end
      it "must respond to .#{meth} method" do
        CheckPrivacy.must_not respond_to(meth)
      end
    end
  end

  [:custom_require, :private_require, :check_load_path, :final_require].each do |meth|
    it "must respond to .#{meth} method" do
      Sumo.must respond_to(meth)
    end
  end

  describe ".custom_require" do

    it "must raise SystemError when given an uninstalled gem" do
      gem = "myjunkgem"
      msg = "Sumo requires the #{gem} gem be installed correctly."
      lambda { Sumo.custom_require(gem) }.must raise_error(::SystemExit, msg)
    end

  end


  it "defaults to user ubuntu if none is specified in the config" do
    pending
		sumo = Sumo::Instance.new :name => "test"
		sumo.user.should == 'ubuntu'
	end

	it "defaults to user can be overwritten on new" do
		pending
    sumo = Sumo::Instance.new :name => "test", :user => "root"
		sumo.user.should == 'root'
  end
	
	describe "prep_ssh_commands" do
	  it "joins them" do
      pending
	    @sumo.prepare_commands(["ls", "echo 'hi'"]).should == "ls && echo 'hi'"
    end
    
    it "logs them to ssh.log" do
      pending
      @sumo.prepare_commands(["cd foo", "ruby baz.rb"])
      File.read("#{@work_path}/ssh.log").should include("cd foo && ruby baz.rb")
    end
  end
end
