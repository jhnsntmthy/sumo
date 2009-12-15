#
# Cookbook Name:: hadoop
# Recipe:: default
#

bash "install_hadoop" do
  user "root"
  cwd "/tmp"
  code <<-EOBASH
    wget http://www.gtlib.gatech.edu/pub/apache/hadoop/core/hadoop-0.19.2/hadoop-0.19.2.tar.gz
    tar xzf hadoop-0.19.2.tar.gz
  EOBASH
end

bash "start_hadoop" do
  user "root"
  cwd "/tmp/hadoop-0.19.2"
  code <<-EOBASH
    ./bin/hadoop namenode -format
    ./bin/start-dfs.sh
    ./bin/start-mapred.sh
  EOBASH
end

