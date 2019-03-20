group node["tensorflow"]["group"] do
  action :create
  not_if "getent group #{node["tensorflow"]["group"]}"
end

user node["tensorflow"]["user"] do
  gid node["tensorflow"]["group"]
  manage_home true
  home "/home/#{node["tensorflow"]["user"]}"
  action :create
  shell "/bin/bash"
  not_if "getent passwd #{node["tensorflow"]["user"]}"
end

group node["tensorflow"]["group"] do
  action :modify
  members ["#{node["tensorflow"]["user"]}"]
  append true
end

directory node["tensorflow"]["dir"]  do
  owner node["tensorflow"]["user"]
  group node["tensorflow"]["group"]
  mode "755"
  action :create
  not_if { File.directory?("#{node["tensorflow"]["dir"]}") }
end

directory node["tensorflow"]["home"] do
  owner node["tensorflow"]["user"]
  group node["tensorflow"]["group"]
  mode "750"
  action :create
end

link node["tensorflow"]["base_dir"] do
  owner node["tensorflow"]["user"]
  group node["tensorflow"]["group"]
  to node["tensorflow"]["home"]
end

# First, find out the compute capability of your GPU here: https://developer.nvidia.com/cuda-gpus
# E.g.,
# NVIDIA TITAN X	6.1
# GeForce GTX 1080	6.1
# GeForce GTX 970	5.2
#

if node['cuda']['accept_nvidia_download_terms'].eql? "true"
  node.override['tensorflow']['need_cuda'] = 1
end
#
# If either 'infinband' or 'mpi' are selected, we have to build tensorflow from source.
#
if node['tensorflow']['mpi'].eql? "true"
  node.override['tensorflow']['need_mpi'] = 1

  case node['platform_family']
  when "debian"
    package "openmpi-bin"
    package "libopenmpi-dev"
    package "mpi-default-bin"

  when "rhel"
    # installs binaries to /usr/local/bin
    # horovod needs mpicxx in /usr/local/bin/mpicxx - add it to the PATH
    package "openmpi-devel"
    package "libtool"

    magic_shell_environment 'PATH' do
      value "$PATH:#{node['cuda']['base_dir']}/bin:/usr/local/bin"
    end
  end
end


if node['tensorflow']['mkl'].eql? "true"
  node.override['tensorflow']['need_mkl'] = 1

  case node['platform_family']
  when "debian"

  cached_file="l_mkl_2018.0.128.tgz"
  remote_file cached_file do
    source "#{node['download_url']}/l_mkl_2018.0.128.tgz"
    mode 0755
    action :create
    retries 1
    not_if { File.exist?(cached_file) }
  end

  bash "install-intel-mkl-ubuntu" do
      user "root"
      code <<-EOF
       set -e
       cd #{Chef::Config['file_cache_path']}
       tar zxf #{cached_file}
       cd #{cached_file}
#       echo "install -eula=accept installdir=#{node['tensorflow']['dir']}/intel_mkl" > commands.txt
#       ./install -s -eula=accept commands.txt
    EOF
      not_if "test -f #{Chef::Config['file_cache_path']}/#{cached_file}"
    end

  when "rhel"
    bash "install-intel-mkl-rhel" do
      user "root"
      code <<-EOF
       set -e
       yum install yum-utils -y
       yum-config-manager --add-repo https://yum.repos.intel.com/setup/intelproducts.repo
       rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB
       yum install intel-mkl-64bit-2017.3-056 -y
    EOF
    end
  end

end

if node['tensorflow']['rdma'].eql? "true"
  node.override['tensorflow']['need_rdma'] = 1
  if node['platform_family'].eql? "debian"

    package "libipathverbs-dev"

    # Install inifiband
    # https://community.mellanox.com/docs/DOC-2683
    bash "install-infiniband-ubuntu" do
      user "root"
      code <<-EOF
    set -e
     apt-get install libmlx4-1 libmlx5-1 ibutils  rdmacm-utils libibverbs1 ibverbs-utils perftest infiniband-diags libibverbs-dev -y
     apt-get -y install libibcm1 libibverbs1 ibverbs-utils librdmacm1 rdmacm-utils libdapl2 ibsim-utils ibutils libcxgb3-1 libibmad5 libibumad3 libmlx4-1 libmthca1 libnes1 infiniband-diags mstflint opensm perftest srptools
     # RDMA stack modules
     sudo modprobe rdma_cm
     sudo modprobe ib_uverbs
     sudo modprobe rdma_ucm
     sudo modprobe ib_ucm
     sudo modprobe ib_umad
     sudo modprobe ib_ipoib
     # RDMA devices low-level drivers
     sudo modprobe mlx4_ib
     sudo modprobe mlx4_en
     sudo modprobe iw_cxgb3
     sudo modprobe iw_cxgb4
     sudo modprobe iw_nes
     sudo modprobe iw_c2
    EOF
    end
  else # "rhel"
    # http://www.rdmamojo.com/2014/10/11/working-rdma-redhatcentos-7/
    # https://community.mellanox.com/docs/DOC-2086


    # Get started - check hardware exists
    # [root@hadoop5 install]#  lspci |grep -i infin
    # 03:00.0 InfiniBand: QLogic Corp. IBA7322 QDR InfiniBand HCA (rev 02)
    # [root@hadoop5 install]# lspci -Qvvs 03:00.0
    # The last line will tell you what kernel module you need to load. In my case, it was:
    # 	Kernel modules: ib_qib

    # modprobe ib_qib
    # lsmod | grep ib_
    # Then check it is installed

    # [root@hadoop5 install]# ibstat
    # CA 'qib0'
    # 	CA type: InfiniPath_QLE7340
    # 	Number of ports: 1
    # 	Firmware version:
    # 	Hardware version: 2
    # 	Node GUID: 0x001175000076dcbe
    # 	System image GUID: 0x001175000076dcbe
    # 	Port 1:
    # 		State: Active
    # 		Physical state: LinkUp
    # 		Rate: 40
    # 		Base lid: 6
    # 		LMC: 0
    # 		SM lid: 3
    # 		Capability mask: 0x07610868
    # 		Port GUID: 0x001175000076dcbe
    # 		Link layer: InfiniBand

    # To measure bandwith, on the server run: 'ib_send_bw'
    # On the client, 'ib_send_bw hadoop5'
    #      ib_read_bw
    # ---------------------------------------------------------------------------------------
    # Device not recognized to implement inline feature. Disabling it

    # ************************************
    # * Waiting for client to connect... *
    # ************************************
    # ---------------------------------------------------------------------------------------
    #                     RDMA_Read BW Test
    #  Dual-port       : OFF		Device         : qib0
    #  Number of qps   : 1		Transport type : IB
    #  Connection type : RC		Using SRQ      : OFF
    #  CQ Moderation   : 100
    #  Mtu             : 2048[B]
    #  Link type       : IB
    #  Outstand reads  : 16
    #  rdma_cm QPs	 : OFF
    #  Data ex. method : Ethernet
    # ---------------------------------------------------------------------------------------
    #  local address: LID 0x06 QPN 0x000b PSN 0x2045ef OUT 0x10 RKey 0x030400 VAddr 0x007f9d36566000
    #  remote address: LID 0x03 QPN 0x0013 PSN 0x8c947f OUT 0x10 RKey 0x070800 VAddr 0x007ff8638c7000
    # ---------------------------------------------------------------------------------------
    #  #bytes     #iterations    BW peak[MB/sec]    BW average[MB/sec]   MsgRate[Mpps]
    #  65536      1000             2563.33            2563.29		   0.041013
    # ---------------------------------------------------------------------------------------


    bash "install-infiniband-rhel" do
      user "root"
      code <<-EOF
    #set -e
    yum -y groupinstall "Infiniband Support"
    yum --setopt=group_package_types=optional groupinstall "Infiniband Support" -y
    yum -y install perftest infiniband-diags
    systemctl start rdma.service

#    lsmod | grep mlx
#    modprobe mlx4_ib
#    modprobe mlx5_ib
   EOF
     not_if  "systemctl status rdma.service"
    end
  end
end


# http://www.pyimagesearch.com/2016/07/04/how-to-install-cuda-toolkit-and-cudnn-for-deep-learning/
case node['platform_family']
when "debian"

  package ["pkg-config", "zip", "g++", "zlib1g-dev", "unzip", "swig", "git", "build-essential", "cmake", "unzip", "libopenblas-dev", "liblapack-dev", "linux-image-#{node['kernel']['release']}", "linux-image-extra-#{node['kernel']['release']}", "linux-headers-#{node['kernel']['release']}", "python2.7", "python2.7-numpy", "python2.7-dev", "python-pip", "python2.7-lxml", "python-pillow", "libcupti-dev", "libcurl3-dev", "python-wheel", "python-six"]

when "rhel"
  if node['rhel']['epel']
    package 'epel-release'
  end

  package ['python-pip', 'mlocate', 'gcc', 'gcc-c++', 'kernel-devel', 'openssl', 'openssl-devel', 'python', 'python-devel', 'python-lxml', 'python-pillow', 'libcurl-devel', 'python-wheel', 'python-six']
end

bash "pip-upgrade" do
  user "root"
  umask "022"
  code <<-EOF
    set -e
    pip install --upgrade pip
  EOF
end

include_recipe "java"

#
# HDFS support in tensorflow
# https://github.com/tensorflow/tensorflow/issues/2218
#
magic_shell_environment 'HADOOP_HDFS_HOME' do
  value "#{node['hops']['base_dir']}"
end


if node['cuda']['accept_nvidia_download_terms'].eql?("true")

  package "clang"

  # Check to see if i can find a cuda card. If not, fail with an error
  bash "test_nvidia" do
    user "root"
    code <<-EOF
      set -e
      lspci | grep -i nvidia
    EOF
    not_if { node['cuda']['skip_test'] == "true" }
  end

    bash "stop_xserver" do
    user "root"
    ignore_failure true
    code <<-EOF
      service lightdm stop
    EOF
  end

  tensorflow_install "driver_install" do
    driver_version node['nvidia']['driver_version']
    action :driver
  end

  node['cuda']['versions'].split(',').each do |version|
    tensorflow_install "cuda_install" do
      cuda_version version
      action :cuda
    end
  end

  node['cudnn']['version_mapping'].split(',').each do |versionmap|
    tensorflow_install "cudnn_install" do
      cuda_version versionmap.split('+')[1]
      cudnn_version versionmap.split('+')[0]
      action :cudnn
    end
  end

  node['nccl']['version_mapping'].split(',').each do |versionmap|
    tensorflow_install "nccl" do
      cuda_version versionmap.split('+')[1]
      nccl_version versionmap.split('+')[0]
      action :nccl
    end
  end

  if node['tensorflow']['mpi'].eql? "true"
    case node['platform_family']
    when "rhel"
      tensorflow_compile "mpi-compile" do
        action :openmpi
      end
    end
  end

  # Cleanup old cuda/nccl installations which are no longer required
  tensorflow_purge "remove_old_cuda" do
    cuda_versions node['cuda']['versions']
    action :cuda
  end

  tensorflow_purge "remove_old_nccl" do
    nccl_versions node['nccl']['version_mapping']
    :nccl
  end

  tensorflow_purge "remove_old_cudnn" do
    cudnn_versions node['cudnn']['version_mapping']
    :cudnn
  end

  # Test installation
  bash 'test_nvidia_installation' do
    user "root"
    code <<-EOH
      nvidia-smi -L
    EOH
  end
end


if node['tensorflow']['install'].eql?("src")

  # https://wiki.fysik.dtu.dk/niflheim/OmniPath#openmpi-configuration
  # compile openmpi on centos 7
  # https://bitsanddragons.wordpress.com/2017/05/08/install-openmpi-2-1-0-on-centos-7/
  bzl =  File.basename(node['bazel']['url'])
  case node['platform_family']
  when "debian"

    bash "bazel-install-ubuntu" do
      user "root"
      code <<-EOF
      set -e
       apt-get install pkg-config zip g++ zlib1g-dev unzip -y
    EOF
    end

  when "rhel"

    # https://gist.github.com/jarutis/6c2934705298720ff92a1c10f6a009d4
    bash "bazel-install-centos" do
      user "root"
      umask "022"
      code <<-EOF
      set -e
      yum install patch -y
      yum -y install gcc gcc-c++ kernel-devel make automake autoconf swig git unzip libtool binutils
      yum -y install python-devel python-pip
      yum -y install freetype-devel libpng12-devel zip zlib-devel giflib-devel zeromq3-devel
      pip install --target /usr/lib/python2.7/site-packages numpy
      pip install grpcio_tools mock
    EOF
    end
  end

  bash "bazel-install" do
    user "root"
    code <<-EOF
      set -e
       cd #{Chef::Config['file_cache_path']}
       rm -f #{bzl}
       wget #{node['bazel']['url']}
       chmod +x bazel-*
#       ./#{bzl} --user
       ./#{bzl}
       /usr/local/bin/bazel
    EOF
    not_if { File::exists?("/usr/local/bin/bazel") }
  end

  tensorflow_compile "mpi-compile" do
    action :openmpi
  end

  tensorflow_compile "tensorflow" do
    action :tf
  end
end

# Download SparkMagic
remote_file "#{Chef::Config['file_cache_path']}/sparkmagic-#{node['jupyter']['sparkmagic']['version']}.tar.gz" do
  user "root"
  group "root"
  source node['jupyter']['sparkmagic']['url']
  mode 0755
  action :create_if_missing
end
