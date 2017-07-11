private_ip = my_private_ip()


directory node.tensorflow.home do
  owner node.tensorflow.user
  group node.tensorflow.group
  mode "750"
  action :create
end

link node.tensorflow.base_dir do
  action :delete
  only_if "test -L #{node.tensorflow.base_dir}"
end

link node.tensorflow.base_dir do
  owner node.tensorflow.user
  group node.tensorflow.group
  to node.tensorflow.home
end

directory "#{node.tensorflow.home}/bin" do
  owner node.tensorflow.user
  group node.tensorflow.group
  mode "750"
  action :create
end

template "#{node.tensorflow.base_dir}/bin/launcher" do 
  source "launcher.sh.erb"
  owner node.tensorflow.user
  group node.tensorflow.group
  mode "750"
  # variables({
  #             :myNN => "hdfs://" + firstNN
  #           })
  action :create_if_missing
end

template "#{node.tensorflow.base_dir}/bin/kill-process.sh" do 
  source "kill-process.sh.erb"
  owner node.tensorflow.user
  group node.tensorflow.group
  mode "750"
  action :create_if_missing
end


url=node.tensorflow.python_url
base_filename =  File.basename(url)
cached_filename = "#{Chef::Config[:file_cache_path]}/#{base_filename}"

remote_file cached_filename do
  source url
  mode 0755
  action :create
end

hops_hdfs_directory cached_filename do
  action :put_as_superuser
  owner node.hops.hdfs.user
  group node.hops.group
  mode "1755"
  dest "/user/#{node.hops.hdfs.user}/#{base_filename}"
end


url=node.tensorflow.tfspark_url

base_filename =  File.basename(url)
cached_filename = "#{Chef::Config[:file_cache_path]}/#{base_filename}"

remote_file cached_filename do
  source url
  mode 0755
  action :create
end

hops_hdfs_directory cached_filename do
  action :put_as_superuser
  owner node.hops.hdfs.user
  group node.hops.group
  mode "1755"
  dest "/user/#{node.hops.hdfs.user}/#{base_filename}"
end

url=node.tensorflow.hopstf_url

base_filename =  File.basename(url)
cached_filename = "#{Chef::Config[:file_cache_path]}/#{base_filename}"

remote_file cached_filename do
  source url
  mode 0755
  action :create
end

hops_hdfs_directory cached_filename do
  action :put_as_superuser
  owner node.hops.hdfs.user
  group node.hops.group
  mode "1755"
  dest "/user/#{node.hops.hdfs.user}/#{base_filename}"
end



package "zip" do
  action :install
end

url=node.tensorflow.hopstfdemo_url

base_filename =  File.basename(url)
cached_filename = "#{Chef::Config[:file_cache_path]}/#{base_filename}"

remote_file cached_filename do
  source url
  mode 0755
  action :create
end

# Extract mnist
bash 'extract_mnist' do
        user node.tensorflow.user
        code <<-EOH
                set -e
                unzip cached_filename
        EOH
     not_if { ::File.exists?( cached_filename ) }
end

hops_hdfs_directory "#{Chef::Config[:file_cache_path]}/mnist.zip" do
  action :put_as_superuser
  owner node.hops.hdfs.user
  group node.hops.group
  mode "1755"
  dest "/user/#{node.hops.hdfs.user}/tensorflow_demo"
end

# libibverbs-devel
