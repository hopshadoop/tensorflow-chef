# coding: utf-8
action :kernel_initramfs do

  case node.platform_family
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

action :cuda do

bash "validate_cuda" do
    user "root"
    code <<-EOF
    set -e
# test the cuda nvidia compiler
    su #{node.tensorflow.user} -l -c "nvcc -V"
EOF
end


end

action :cudnn do

bash "validate_cudnn" do
    user "root"
    code <<-EOF
    set -e
    su #{node.tensorflow.user} -l -c "nvidia-smi | grep NVID"
EOF
  not_if { node["cuda"]["skip_test"] == "true" }
end

end

action :tf do

# bash "install_bazel_again" do
#     user "root"
#     code <<-EOF
#     set -e
#     /var/chef/cache/bazel-0.3.1-installer-linux-x86_64.sh
# EOF
# end


bash "git_clone_tensorflow_server" do
    user node.tensorflow.user
    code <<-EOF
    set -e
    cd /home/#{node.tensorflow.user}

    git clone --recurse-submodules #{node.tensorflow.git_url}
EOF
  not_if { ::File.exists?( "/home/#{node.tensorflow.user}/tensorflow/configure" ) }
end

if node.cuda.enabled == "true" 
  config="configure-no-expect-with-gpu.sh"
else
  config="configure-no-expect.sh"
end

template "/home/#{node.tensorflow.user}/tensorflow/#{config}" do
  source "#{config}.erb"
  owner node.tensorflow.user
  mode 0770
end


#
# http://www.admin-magazine.com/Articles/Automating-with-Expect-Scripts
#
bash "configure_tensorflow_server" do
    user node.tensorflow.user
    code <<-EOF
    set -e
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    cd /home/#{node.tensorflow.user}/tensorflow
    ./#{config}
    
    # Check if configure completed successfully
    if [ ! -f tools/bazel.rc ] ; then
      exit 1
    fi
EOF
  not_if { ::File.exists?( "/home/#{node.tensorflow.user}/tensorflow/tools/bazel.rc" ) }
end


if node.cuda.enabled == "true" 

  # https://github.com/bazelbuild/bazel/issues/739
    bash "workaround_bazel_build" do
     user "root"
      code <<-EOF
    set -e
     chown -R #{node.tensorflow.user} /home/#{node.tensorflow.user}/tensorflow
     rm -rf /home/#{node.tensorflow.user}/.cache/bazel
     EOF
    end


  bash "build_install_tensorflow_server" do
     user node.tensorflow.user
      timeout 10800
      code <<-EOF
    set -e
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    cd /home/#{node.tensorflow.user}/tensorflow
    ./#{config}

    bazel build -c opt --config=cuda //tensorflow/core/distributed_runtime/rpc:grpc_tensorflow_server
# Create the pip package and install
    bazel build -c opt --config=cuda //tensorflow/tools/pip_package:build_pip_package
    bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg

# tensorflow-0.10.0-py2-none-any.whl
    pip install /tmp/tensorflow_pkg/tensorflow-#{node.tensorflow.base_version}-py2-none-any.whl
    touch .installed
EOF
      not_if { ::File.exists?( "/home/#{node.tensorflow.user}/tensorflow/.installed" ) }
    end


else

  # https://github.com/bazelbuild/bazel/issues/739
    bash "workaround_bazel_build" do
     user "root"
      code <<-EOF
    set -e
     chown -R #{node.tensorflow.user} /home/#{node.tensorflow.user}/tensorflow
     rm -rf /home/#{node.tensorflow.user}/.cache/bazel
     EOF
    end


  bash "build_install_tensorflow_server_no_cuda" do
     user node.tensorflow.user    
      timeout 10800
      code <<-EOF
    set -e

    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    cd /home/#{node.tensorflow.user}/tensorflow
    ./#{config}

# Create the pip package and install
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

#    bazel build -c opt //tensorflow/tools/pip_package:build_pip_package
    bazel build --config=mkl --copt="-DEIGEN_USE_VML" -c opt //tensorflow/tools/pip_package:build_pip_package
    bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
    pip install /tmp/tensorflow_pkg/tensorflow-#{node.tensorflow.base_version}-cp27-cp27mu-linux_x86_64.whl
    touch .installed
EOF
      not_if { ::File.exists?( "/home/#{node.tensorflow.user}/tensorflow/.installed" ) }
    end
  end


    bash "upgrade_protobufs" do
      user "root"
      code <<-EOF
       set -e
       pip install --upgrade https://storage.googleapis.com/tensorflow/linux/cpu/protobuf-3.0.0b2.post2-cp27-none-linux_x86_64.whl
      EOF
    end


    bash "validate_tensorflow" do
      user node.tensorflow.user
      code <<-EOF
       set -e
#       cd /home/#{node.tensorflow.user}/tensorflow
#       cd models/image/mnist
#       python convolutional.py
      EOF
    end

end
