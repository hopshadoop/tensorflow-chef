# First, find out the compute capability of your GPU here: https://developer.nvidia.com/cuda-gpus
# E.g.,
# NVIDIA TITAN X	6.1
# GeForce GTX 1080	6.1
# GeForce GTX 970	5.2
#

if node['cuda']['accept_nvidia_download_terms'].eql? "true"
  node.override['tensorflow']['need_cuda'] = 1
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

  package ["pkg-config", "zip", "g++", "zlib1g-dev", "unzip", "swig", "git", "build-essential", "cmake", "unzip", "libopenblas-dev", "liblapack-dev", "linux-image-#{node['kernel']['release']}", "linux-headers-#{node['kernel']['release']}", "python2.7", "python2.7-numpy", "python2.7-dev", "python-pip", "python2.7-lxml", "python-pillow", "libcupti-dev", "libcurl3-dev", "python-wheel", "python-six", "pciutils"]

when "rhel", "amazon"
  if node['rhel']['epel'].downcase == "true" && node['platform_family'].eql?("rhel")
    package 'epel-release'
  elsif node['rhel']['epel'].downcase == "true" && node['platform_family'].eql?("amazon")
    bash "install_epel_amazon" do 
      user "root"
      code <<-EOH
        amazon-linux-extras install epel
      EOH
    end
  end

  # With our current CentOS box "CentOS Linux release 7.5.1804 (Core)",
  # sudo yum install "kernel-devel-uname-r == $(uname -r)" doesn't work as it cannot find the kernel-devel version
  # returned by uname-r.
  # It works in AWS CentOS Linux release 7.6.1810 (Core) though.
  # We can install the specific version and if that fails, then install the kernel devel package without
  # specifying a version
  package 'kernel-devel' do
    version node['kernel']['release']
    action :install
    ignore_failure true
  end

  package 'kernel-devel' do
    action :install
    not_if  "ls -l /usr/src/kernels/$(uname -r)"
  end

  package ['pciutils', 'python-pip', 'mlocate', 'gcc', 'gcc-c++', 'openssl', 'openssl-devel', 'python', 'python-devel', 'python-lxml', 'python-pillow', 'libcurl-devel', 'python-wheel', 'python-six']
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

  tensorflow_install "cuda_install" do
    cuda_version node['cuda']['versions'].split(',').last
    action :cuda
  end

  tensorflow_install "cudnn_install" do
    cuda_version node['cudnn']['version_mapping'].split(',').last.split('+')[1]
    cudnn_version node['cudnn']['version_mapping'].split(',').last.split('+')[0]
    action :cudnn
  end

  tensorflow_install "nccl" do
    cuda_version node['nccl']['version_mapping'].split(',').last.split('+')[1]
    nccl_version node['nccl']['version_mapping'].split(',').last.split('+')[0]
    action :nccl
  end

  # Cleanup old cuda versions
  tensorflow_purge "remove_old_cuda" do
    cuda_versions node['cuda']['versions']
    action :cuda
  end

  # Cleanup old cudnn versions
  tensorflow_purge "remove_old_cudnn" do
    cudnn_versions node['cudnn']['version_mapping']
    :cudnn
  end

# Cleanup old nccl versions
  tensorflow_purge "remove_old_nccl" do
    nccl_versions node['nccl']['version_mapping']
    :nccl
  end

  # Test installation
  bash 'test_nvidia_installation' do
    user "root"
    code <<-EOH
      nvidia-smi -L
    EOH
  end
end

# Delete SparkMagic
file "#{Chef::Config['file_cache_path']}/sparkmagic-#{node['jupyter']['sparkmagic']['version']}.tar.gz" do
  action :delete
  only_if { File.exist? "#{Chef::Config['file_cache_path']}/sparkmagic-#{node['jupyter']['sparkmagic']['version']}.tar.gz" }
end

# Download SparkMagic
remote_file "#{Chef::Config['file_cache_path']}/sparkmagic-#{node['jupyter']['sparkmagic']['version']}.tar.gz" do
  user "root"
  group "root"
  source node['jupyter']['sparkmagic']['url']
  mode 0755
  action :create
end


#
# ROCm
#

if node['rocm']['install'].eql? "true"

  case node['platform_family']
  when "debian"
      install_dir = node['rocm']['dir'] + "/rocm-" + node['rocm']['debian']['version']
      directory node["rocm"]["dir"]  do
        owner "_apt"
        group "root"
        mode "755"
        action :create
        not_if { File.directory?("#{node["rocm"]["dir"]}") }
      end

      directory install_dir do
        owner "_apt"
        group "root"
        mode "750"
        action :create
      end

      link node["rocm"]["base_dir"] do
        owner "_apt"
        group "root"
        to install_dir
      end
  when "rhel"
      install_dir = node['rocm']['dir'] + "/rocm-" + node['rocm']['rhel']['version']
      directory node["rocm"]["dir"]  do
        owner "root"
        group "root"
        mode "755"
        action :create
        not_if { File.directory?("#{node["rocm"]["dir"]}") }
      end

      directory install_dir do
        owner "root"
        group "root"
        mode "750"
        action :create
      end

      link node["rocm"]["base_dir"] do
        owner "root"
        group "root"
        to install_dir
      end
  end

  tensorflow_purge "remove_old_rocm" do
    action :rocm
  end

  tensorflow_amd "install_rocm" do
    action :install_rocm
    rocm_home install_dir
  end
end
