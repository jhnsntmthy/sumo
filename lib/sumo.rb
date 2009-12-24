module Sumo

  # Accomodate different load path managers and no load path manager
  def self.custom_require(gem)
    begin
      require gem
    rescue LoadError
      # TODO require 'vendor/rip' # fallback to Rip
      # TODO require 'vendor/gems/environment.rb' # fallback to Bundler
      # TODO Set Bundler's disable_system_gems 
      private_require(File.expand_path(File.dirname(__FILE__)), gem)
    end
  end

  module_function
  
  def private_require(dir, gem)
    check_load_path(dir, gem)
    final_require(gem)
  end

  def check_load_path(dir, gem)
    exit_msg = "Sumo requires the #{gem} gem be installed correctly."
    if $LOAD_PATH.include?(dir)
      raise SystemExit.new(exit_msg)
    else
      $LOAD_PATH.unshift(dir)
    end    
  end
  
  def final_require(gem)
    exit_msg  = "Sumo requires the #{gem} gem be installed correctly."
    begin
      require(gem)
    rescue LoadError
      raise SystemExit.new(exit_msg)
    end
  end

end

# Require third party gem files
%w[thor AWS yaml socket json logger net/ssh].each do |gemi|
  ::Sumo.custom_require gemi
end

# Require Sumo's library files
#%w[config instance].each do |gemi|
#  Sumo.tolerant_require("sumo/#{gemi}")
#end

# Require Sumo's test stack
if $SUMO_TEST_STACK
  %w[fileutils stringio spec rr diff/lcs].each do |gemi|
    Sumo.custom_require(gemi)
  end
end

#TODO Add spec_task, package_task, install_task
#
#spec_task(Dir["spec/**/*_spec.rb"])
#
#to any of your Thor classes. You can also customize it like so:spec_task(Dir["spec/**/*_spec.rb"], :name => “rcov”, :rcov => {:exclude => %w(spec /Library /Users task.thor lib/getopt.rb)})
#
#You can also add package/install tasks via: package_task / install_task (where install_task adds package_task by default).

module Sumo
	def launch
		ami = config['ami']
		raise "No AMI selected" unless ami

		create_keypair unless File.exists? keypair_file

		create_security_group
		open_firewall(22)
		enable_ping

		result = ec2.run_instances(
			:image_id => ami,
			:instance_type => config['instance_size'] || 'm1.small',
			:key_name => keypair_name,
#			:group_id => [ 'sumo' ],
			:availability_zone => config['availability_zone']
		)
		result.instancesSet.item[0].instanceId
	end

	def list
		@list ||= fetch_list
	end

	def volumes
		result = ec2.describe_volumes
		return [] unless result.volumeSet

		result.volumeSet.item.map do |row|
			{
				:volume_id => row["volumeId"],
				:size => row["size"],
				:status => row["status"],
				:device => (row["attachmentSet"]["item"].first["device"] rescue ""),
				:instance_id => (row["attachmentSet"]["item"].first["instanceId"] rescue ""),
			}
		end
	end

	def available_volumes
		volumes.select { |vol| vol[:status] == 'available' }
	end

	def attached_volumes
		volumes.select { |vol| vol[:status] == 'in-use' }
	end

	def nondestroyed_volumes
		volumes.select { |vol| vol[:status] != 'deleting' }
	end

	def attach(volume, instance, device)
		result = ec2.attach_volume(
			:volume_id => volume,
			:instance_id => instance,
			:device => device
		)
		"done"
	end

	def detach(volume)
		result = ec2.detach_volume(:volume_id => volume, :force => "true")
		"done"
	end

	def create_volume(size)
		result = ec2.create_volume(
			:availability_zone => config['availability_zone'],
			:size => size.to_s
		)
		result["volumeId"]
	end

	def destroy_volume(volume)
		ec2.delete_volume(:volume_id => volume)
		"done"
	end

	def fetch_list
		result = ec2.describe_instances
		return [] unless result.reservationSet

		instances = []
		result.reservationSet.item.each do |r|
			r.instancesSet.item.each do |item|
				instances << {
					:instance_id => item.instanceId,
					:status => item.instanceState.name,
					:hostname => item.dnsName
				}
			end
		end
		instances
	end

	def find(id_or_hostname)
		return unless id_or_hostname
		id_or_hostname = id_or_hostname.strip.downcase
		list.detect do |inst|
			inst[:hostname] == id_or_hostname or
			inst[:instance_id] == id_or_hostname or
			inst[:instance_id].gsub(/^i-/, '') == id_or_hostname
		end
	end

	def find_volume(volume_id)
		return unless volume_id
		volume_id = volume_id.strip.downcase
		volumes.detect do |volume|
			volume[:volume_id] == volume_id or
			volume[:volume_id].gsub(/^vol-/, '') == volume_id
		end
	end

	def running
		list_by_status('running')
	end

	def pending
		list_by_status('pending')
	end

	def list_by_status(status)
		list.select { |i| i[:status] == status }
	end

	def instance_info(instance_id)
		fetch_list.detect do |inst|
			inst[:instance_id] == instance_id
		end
	end

	def wait_for_hostname(instance_id)
		raise ArgumentError unless instance_id and instance_id.match(/^i-/)
		loop do
			if inst = instance_info(instance_id)
				if hostname = inst[:hostname]
					return hostname
				end
			end
			sleep 1
		end
	end

	def wait_for_ssh(hostname)
		raise ArgumentError unless hostname
		loop do
			begin
				Timeout::timeout(4) do
					TCPSocket.new(hostname, 22)
					return
				end
			rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH
			end
		end
	end

	def sync_files(hostname)
		if config['tarball']
			# Safety check perms on /root or you'll be locked out
			`(cat #{config['tarball']} | #{ssh_command(hostname)} 'cd / && tar xz && chown -R root:root /root' )`
		end
	end

	def bootstrap_chef(hostname)
	  rubygems = "rubygems-1.3.5"
	  rubygems_url = "http://files.rubyforge.vm.bytemark.co.uk/rubygems/#{rubygems}.tgz"
		commands = [
			"apt-get update",
			"apt-get autoremove -y",
			"apt-get install -y ruby ruby1.8-dev libopenssl-ruby1.8 rdoc build-essential wget git-core",
			"wget -P/tmp #{rubygems_url}",
			"cd /tmp",
			"tar xzf #{rubygems}.tgz -v",
			"cd #{rubygems}",
			"/usr/bin/env ruby setup.rb",
			"ln -sfv /usr/bin/gem1.8 /usr/bin/gem",
			"gem sources -a http://gems.opscode.com",
			'gem install chef ohai rake --no-rdoc --no-ri',
      # Install thor, then execute:
			"cd ~",
      # thor install http://fqdn/sumo/bootstrap.thor
			"rm -rf #{cookbooks_path}",
			"cd ~",
			"git clone #{config['cookbooks_url']} #{cookbooks_path}",
		]
		if config['private_chef_repo']
		  commands.unshift("echo -e \"Host github.com\n\tStrictHostKeyChecking no\n\" >> ~/.ssh/config") 
		end

    if config['enable_submodules'] 
		  commands << [
		    "cd chef-cookbooks",
		    "git submodule init",
		    "git submodule update"		    
		  ]
		end
		
		ssh(hostname, commands)
	end

	def setup_role(hostname, role)
		commands = [
			"cd #{cookbooks_path}",
			"rake roles",
			"chef-solo -c config/solo.rb -j roles/#{role}.json"
		]
		ssh(hostname, commands)
	end
	
	def ssh(hostname, cmds)
		copy_key(hostname)
	        private_options = "-A" if config['private_chef_repo']
		IO.popen("ssh #{private_options} -i #{keypair_file} #{config['user']}@#{hostname} > ~/.sumo/ssh.log 2>&1", "w") do |pipe|
			pipe.puts prepare_commands(cmds)
		# TODO port private ssh options to ssh_command method then refactor.
		#IO.popen("#{ssh_command(hostname)} > ~/.sumo/ssh.log 2>&1", "w") do |pipe|
		end

		unless $?.success?
			abort "failed\nCheck ~/.sumo/ssh.log for the output"
		end
	end

	def prepare_commands(cmds)
	  joined_commands = cmds.join(' && ')
	  ssh_log.debug { "Executing ssh commands: "}
	  ssh_log.debug { joined_commands }
	  joined_commands
  end
  
  def ssh_log
    @ssh_log ||= Logger.new("#{sumo_dir}/ssh.log")
  end

	def copy_key(hostname)
		IO.popen("scp -i #{keypair_file} #{keypair_file} #{config['user']}@#{hostname}:~/.ssh")
	end

	def prepare_commands(cmds)
	  joined_commands = cmds.join(' && ')
	  ssh_log.debug { "Executing ssh commands: "}
	  ssh_log.debug { joined_commands }
	  joined_commands
  end
  
  def ssh_log
    @ssh_log ||= Logger.new("#{sumo_dir}/ssh.log")
  end

	def resources(hostname)
		@resources ||= {}
		@resources[hostname] ||= fetch_resources(hostname)
	end

	def fetch_resources(hostname)
		cmd = "#{ssh_command(hostname)} 'cat /root/resources' 2>&1"
		out = IO.popen(cmd, 'r') { |pipe| pipe.read }
		abort "failed to read resources, output:\n#{out}" unless $?.success?
		parse_resources(out, hostname)
	end

	def parse_resources(raw, hostname)
		raw.split("\n").map do |line|
			line.gsub(/localhost/, hostname)
		end
	end

	def terminate(instance_id)
		ec2.terminate_instances(:instance_id => [ instance_id ])
	end

	def console_output(instance_id)
		ec2.get_console_output(:instance_id => instance_id)["output"]
	end

	def config
		@config ||= default_config.merge read_config
	end

	def default_config
		{
			'user' => 'root',
			'ami' => 'ami-ed46a784',
			'availability_zone' => 'us-east-1b'
		}
	end

	def sumo_dir
		"#{ENV['HOME']}/.sumo"
	end

	def cookbooks_path
		config['cookbooks_path'] || 'chef-cookbooks'
	end

	def keypair_name
		config['keypair_name'] || 'sumo'
	end

	def ssh_command(hostname)
		"ssh -i #{keypair_file} #{config['user']}@#{hostname}"
	end

	def read_config
		YAML.load File.read("#{sumo_dir}/config.yml")
	rescue Errno::ENOENT
		raise "Sumo is not configured, please fill in ~/.sumo/config.yml"
	end
	
	def current_region
	  @current_region ||= begin
  	  zones = ec2.describe_availability_zones
  	  zones.availabilityZoneInfo.item[0].regionName
	  end
  end

	def keypair_file
	  "#{sumo_dir}/keypair-#{current_region}.pem"
	end

  def key_name
    "sumo-#{current_region}"
  end

	def create_keypair
		keypair = ec2.create_keypair(:key_name => keyname_name).keyMaterial
		File.open(keypair_file, 'w') { |f| f.write keypair }
		File.chmod 0600, keypair_file
	end

	def create_security_group
		ec2.create_security_group(:group_name => 'sumo', :group_description => 'Sumo')
	rescue AWS::EC2::InvalidGroupDuplicate
	end

	def open_firewall(port)
		ec2.authorize_security_group_ingress(
			:group_name => 'sumo',
			:ip_protocol => 'tcp',
			:from_port => port,
			:to_port => port,
			:cidr_ip => '0.0.0.0/0'
		)
	rescue AWS::EC2::InvalidPermissionDuplicate
	end
	
	def enable_ping
		ec2.authorize_security_group_ingress(
			:group_name => 'sumo',
			:ip_protocol => 'icmp',
			:from_port => -1,
			:to_port => -1,
			:cidr_ip => '0.0.0.0/0'	  
		)
	rescue AWS::InvalidPermissionDuplicate
	end
	
	def enable_ping
		ec2.authorize_security_group_ingress(
			:group_name => 'sumo',
			:ip_protocol => 'icmp',
			:from_port => -1,
			:to_port => -1,
			:cidr_ip => '0.0.0.0/0'	  
		)
	rescue AWS::InvalidPermissionDuplicate
	end

	def ec2
		@ec2 ||= AWS::EC2::Base.new(
			:access_key_id => config['access_key_id'],
			:secret_access_key => config['secret_access_key'],
			:server => server
		)
	end
	
	def server
		zone = config['availability_zone']
		host = zone.slice(0, zone.length - 1)
		"#{host}.ec2.amazonaws.com"
	end
end
