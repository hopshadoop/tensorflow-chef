# coding: utf-8


action :openmpi do

  basename = ::File.basename(node['openmpi']['version'], ".tar.gz")

  case node['platform_family']
  when "debian"
    package 'libibverbs-dev'
  when "rhel"
    package 'libsysfs-devel'
    package 'libibverbs'
    package 'rdma-core-devel'
    package 'gcc-c++'
  end
  cuda=""
  if node['cuda']['accept_nvidia_download_terms'].eql?("true")
    cuda=" --with-cuda=#{node['cuda']['version_dir']}"
  end
  rdma=""
  if node['tensorflow']['rdma'].eql? "true"
    rdma=" --with-verbs"
  end

  bash "compile_openmpi" do
    user "root"
    code <<-EOF
        set -e
        cd #{Chef::Config['file_cache_path']}
        if [ ! -f #{node['openmpi']['version']} ] ; then
          wget #{node['download_url']}/openmpi/#{node['openmpi']['version']}
        fi
        tar zxf #{node['openmpi']['version']}
        cd #{basename}
        ./configure --prefix=/usr/local #{cuda} #{rdma}
        make all
        mkdir -p #{node['tensorflow']['dir']}/#{basename}
        make install
        #chown -R #{node['tensorflow']['user']} /usr/local/lib/openmpi
        #chown -R #{node['tensorflow']['user']} /usr/local/include/openmpi
      EOF
    not_if { ::File.directory?("/usr/local/include/openmpi") }
  end
end


action :kernel_initramfs do

  case node['platform_family']
  when "debian"
    bash "kernel_initramfs" do
      user "root"
      code <<-EOF
      set -e
      update-initramfs -u
      EOF
    end
  when "rhel"
    bash "kernel_initramfs" do
      user "root"
      code <<-EOF
        set -e
        sudo dracut --force
        EOF
    end
  end

end

action :tf do

  # https://github.com/lakshayg/tensorflow-build

  tf_version = node['tensorflow']['version']
  base_version = ::File.basename("#{tf_version}", ::File.extname(tf_version))

  # Try and download+install a custom python wheel first. If that fails, build from source
  begin
    wheel = File.basename("#{node['tensorflow']['custom_url']}")
    remote_file "#{Chef::Config['file_cache_path']}/#{wheel}" do
      source node['tensorflow']['custom_url']
      owner node['tensorflow']['user']
      group node['tensorflow']['group']
      mode "0755"
      action :create_if_missing
    end

    bash "pip_install_custom_tensorflow" do
      user "root"
      code <<-EOF
      set -e
      export LC_CTYPE=en_US.UTF-8
      export LC_ALL=en_US.UTF-8
      pip install --ignore-installed --upgrade #{Chef::Config['file_cache_path']}/#{wheel}
     EOF
    end

  rescue


    bash "git_clone_tensorflow_server" do
      user node['tensorflow']['user']
      code <<-EOF
    set -e
    cd /home/#{node['tensorflow']['user']}
    if [ -d /home/#{node['tensorflow']['user']}/tensorflow ] ; then
      cd tensorflow
      git pull
    else
      git clone --recurse-submodules --branch r#{base_version} #{node['tensorflow']['git_url']}
      cd tensorflow
    fi
EOF
      #  not_if { ::File.exists?( "/home/#{node['tensorflow']['user']}/tensorflow/configure" ) }
    end

    clang_path=""
    if node['cuda']['accept_nvidia_download_terms'] == "true"
      config="configure-no-expect-with-gpu.sh"
      case node['platform_family']
      when "debian"
        clang_path="/usr/bin/clang"
      when "rhel"
        clang_path="/bin/clang"
      end
    else
      config="configure-no-expect.sh"
    end



    template "/home/#{node['tensorflow']['user']}/tensorflow/#{config}" do
      source "#{config}.erb"
      owner node['tensorflow']['user']
      mode 0770
      variables({ :clang_path => clang_path })
    end


    #
    # http://www.admin-magazine.com/Articles/Automating-with-Expect-Scripts
    #
    bash "configure_tensorflow_server" do
      user "root"
      code <<-EOF
    set -e
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    cd /home/#{node['tensorflow']['user']}/tensorflow
    ./#{config}

    # Check if configure completed successfully
    #if [ ! -f tools/bazel.rc ] ; then
    #  exit 1
    #fi
EOF
    end


    if node['cuda']['accept_nvidia_download_terms'] == "true"


      # https://github.com/bazelbuild/bazel/issues/739
      bash "workaround_bazel_build" do
        user "root"
        code <<-EOF
    set -e
     chown -R #{node['tensorflow']['user']} /home/#{node['tensorflow']['user']}/tensorflow
#     rm -rf /home/#{node['tensorflow']['user']}/.cache/bazel
      find /usr/local/cuda/lib64/stubs/ -printf "%f\n" > /etc/ld.so.conf.d/cuda-stubs.conf
      ldconfig
     EOF
      end


      case node['platform_family']
      when "debian"
        # tensorflow tools say to install this - not default package in ubuntu
        #package 'cuda-command-line-tools'

        bash "build_install_tensorflow_server_debian" do
          #    user node['tensorflow']['user']
          user "root"
          timeout 30800
          code <<-EOF
    set -e
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export PATH=/usr/local/cuda/bin:/usr/local/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

    cd /home/#{node['tensorflow']['user']}/tensorflow
    ./#{config}
# Compile instructions - https://stackoverflow.com/questions/41293077/how-to-compile-tensorflow-with-sse4-2-and-avx-instructions


    if [ ! -d nccl ] ; then
      git clone https://github.com/NVIDIA/nccl.git
    fi
    cd nccl/
    make CUDA_HOME=/usr/local/cuda
    sudo make install
    sudo mkdir -p /usr/local/include/external/nccl_archive/src
    if [ ! -f /usr/local/include/external/nccl_archive/src/nccl.h ] ; then
      sudo ln -s /usr/local/include/nccl.h /usr/local/include/external/nccl_archive/src/nccl.h
    fi
    cd ..

# This works for ubuntu but not for centos
# Build fails for centos: https://github.com/tensorflow/tensorflow/issues/10665
#    bazel build -c opt  --cxxopt="-D_GLIBCXX_USE_CXX11_ABI=0" --config=cuda --copt=-mavx --copt=-mavx2 --copt=-mfma --copt=-mfpmath=both --copt=-msse4.1 --copt=-msse4.2 //tensorflow/tools/pip_package:build_pip_package

    bazel build -c opt --action_env=LD_LIBRARY_PATH=/usr/local/cuda/lib64::/usr/local/cuda/extras/CUPTI/lib64 --config=cuda //tensorflow/tools/pip_package:build_pip_package
    touch .installed
EOF
          not_if { ::File.exists?( "/home/#{node['tensorflow']['user']}/tensorflow/.installed" ) }
        end


      when "rhel"

        bash "build_install_tensorflow_server_rhel" do
          user "root"
          timeout 30800
          code <<-EOF
    set -e
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export PATH=/usr/local/cuda/bin:/usr/local/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

    cd /home/#{node['tensorflow']['user']}/tensorflow
    ./#{config}

    if [ ! -d nccl ] ; then
      git clone https://github.com/NVIDIA/nccl.git
    fi
    cd nccl/
    make CUDA_HOME=/usr/local/cuda
    sudo make install
    sudo mkdir -p /usr/local/include/external/nccl_archive/src
    if [ ! -f /usr/local/include/external/nccl_archive/src/nccl.h ] ; then
      sudo ln -s /usr/local/include/nccl.h /usr/local/include/external/nccl_archive/src/nccl.h
    fi
    cd ..

#  https://github.com/tensorflow/serving/issues/327
# removing prefix /external/nccl_archive in files nccl_ops.cc and
# nccl_manager.h which in folder tensorflow/tensorflow/contrib/nccl/kernels, fix the issue
   # vi tensorflow/workspace.bzl :s/6d43b9d223ce09e5d4ce8b0060cb8a7513577a35a64c7e3dad10f0703bf3ad93/e5fdeee6b28cf6c38d61243adff06628baa434a22b5ebb7432d2a7fbabbdb13d/g

# Compile instructions - https://stackoverflow.com/questions/41293077/how-to-compile-tensorflow-with-sse4-2-and-avx-instructions
#    bazel build -c opt --config=cuda //tensorflow/core/distributed_runtime/rpc:grpc_tensorflow_server

# This works for ubuntu but not for centos
# Build fails for centos: https://github.com/tensorflow/tensorflow/issues/10665
#    bazel build -c opt  --cxxopt="-D_GLIBCXX_USE_CXX11_ABI=0" --config=cuda --copt=-mavx --copt=-mavx2 --copt=-mfma --copt=-mfpmath=both --copt=-msse4.1 --copt=-msse4.2 //tensorflow/tools/pip_package:build_pip_package

#    bazel build -c opt --cxxopt="-D_GLIBCXX_USE_CXX11_ABI=0 -I/usr/lib/gcc/x86_64-redhat-linux/4.8.5/include/*.h" --config=cuda //tensorflow/tools/pip_package:build_pip_package

    bazel build -c opt  --action_env=LD_LIBRARY_PATH=/usr/local/cuda/lib64::/usr/local/cuda/extras/CUPTI/lib64 --cxxopt="-I/usr/lib/gcc/x86_64-redhat-linux/4.8.5/include/*.h" --config=cuda //tensorflow/tools/pip_package:build_pip_package
    touch .installed
EOF
          not_if { ::File.exists?( "/home/#{node['tensorflow']['user']}/tensorflow/.installed" ) }
        end

      end


      bash "pip_install_tensorflow" do
        user "root"
        timeout 30800
        code <<-EOF
    set -e
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export PATH=$PATH:/usr/local/bin
    cd /home/#{node['tensorflow']['user']}/tensorflow

    #install -Dm755 bazel-bin/tensorflow/libtensorflow.so /usr/lib/
    #install -Dm644 tensorflow/c/c_api.h /usr/include/tensorflow-cuda/c_api.h

    #bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
    export PATH=$PATH:/usr/local/bin:/usr/local/cuda/bin
     bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
    # tensorflow-1.7.0-cp27-cp27mu-linux_x86_64.whl
    pip install --ignore-installed --upgrade /tmp/tensorflow_pkg/tensorflow-#{node['tensorflow']['version']}-cp27-cp27mu-linux_x86_64.whl
    # pip install --ignore-installed --upgrade /tmp/tensorflow_pkg/tensorflow-#{base_version}-py2-none-any.whl
    touch .installed_pip
EOF
        not_if { ::File.exists?( "/home/#{node['tensorflow']['user']}/tensorflow/.installed_pip" ) }
      end

      begin
        gzip = File.basename("#{node['tensorflow']['graph_url']}")
        remote_file "#{Chef::Config['file_cache_path']}/#{gzip}" do
          source node['tensorflow']['graph_url']
          owner node['tensorflow']['user']
          group node['tensorflow']['group']
          mode "0755"
          action :create_if_missing
        end

        bash "install_transform_graph_tensorflow" do
          user "root"
          code <<-EOF
      set -e
      export LC_CTYPE=en_US.UTF-8
      export LC_ALL=en_US.UTF-8
        cd #{Chef::Config['file_cache_path']}
        tar zxf #{gzip} -C #{node['tensorflow']['dir']}
     EOF
        end

      rescue


        bash "transform_graph" do
          user "root"
          code <<-EOF
       set -e
        export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
        export PATH=$PATH:/usr/local/bin:/usr/local/cuda/bin
        cd /home/#{node['tensorflow']['user']}/tensorflow
        bazel build tensorflow/tools/graph_transforms:transform_graph
        cp -rf bazel-bin/tensorflow #{node['tensorflow']['dir']}
      EOF
        end



      end   # End rescue

    else

      # https://github.com/bazelbuild/bazel/issues/739
      bash "workaround_bazel_build" do
        user "root"
        code <<-EOF
    set -e
     chown -R #{node['tensorflow']['user']} /home/#{node['tensorflow']['user']}/tensorflow
     rm -rf /home/#{node['tensorflow']['user']}/.cache/bazel
     EOF
      end


      bash "build_install_tensorflow_server_no_cuda" do
        user "root"
        timeout 10800
        code <<-EOF
    set -e

    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    cd /home/#{node['tensorflow']['user']}/tensorflow
    ./#{config}

# Create the pip package and install
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

# Needed for Centos
    export PATH=$PATH:/usr/local/bin
    # http://biophysics.med.jhmi.edu/~yliu120/tensorflow.html
    # bazel build -c opt --copt=-mavx2 --copt=-mfma --copt=-mfpmath=both --copt=-msse4.1 --copt=-msse4.2 //tensorflow/tools/pip_package:build_pip_package
    bazel build -c opt --copt=-mavx2 --ignore_unsupported_sandboxing --genrule_strategy=standalone --spawn_strategy=standalone --linkopt '-lrt -lm' //tensorflow/tools/pip_package:build_pip_package
    bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
    pip install /tmp/tensorflow_pkg/tensorflow-#{base_version}-cp27-cp27mu-linux_x86_64.whl
    #--user
    touch .installed
EOF
        not_if { ::File.exists?( "/home/#{node['tensorflow']['user']}/tensorflow/.installed" ) }
      end
    end


  end # End rescue

  bash "upgrade_protobufs" do
    user "root"
    code <<-EOF
       set -e
       pip install --upgrade https://storage.googleapis.com/tensorflow/linux/cpu/protobuf-3.0.0b2.post2-cp27-none-linux_x86_64.whl
       #--user
      EOF
  end

end
