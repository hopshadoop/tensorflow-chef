name             "tensorflow"
maintainer       "Jim Dowling"
maintainer_email "jdowling@kth.se"
license          "Apache v2.0"
description      'Installs/Configures/Runs tensorflow'
version          "0.6.0"

recipe            "tensorflow::install", "Download and compile and install tensorflow"
recipe            "tensorflow::default",  "Setup tensorflow"
recipe            "tensorflow::serving",  "Install tensorflow serving"
recipe            "tensorflow::purge",  "Uninstall tensorflow and cuda"


depends "kagent"
depends "java"
depends "magic_shell"
depends "ndb"
depends "hops"

%w{ ubuntu debian rhel centos }.each do |os|
  supports os
end


attribute "tensorflow/user",
          :description => "user parameter value",
          :type => "string"

attribute "tensorflow/group",
          :description => "group parameter value",
          :type => "string"

attribute "tensorflow/dir",
          :description => "Base installation directory",
          :type => "string"

attribute "download_url",
          :description => "url for binaries",
          :type => "string"

attribute "tensorflow/git_url",
          :description => "url for git sourcecode for tensorflow",
          :type => "string"

attribute "tensorflow/install",
          :description => "'src' to compile/install from source code. 'dist' to install from binaries. ",
          :type => "string"

attribute "tensorflow/mpi",
          :description => "'true' to install openmpi support, 'false' (default) for no MPI support. ",
          :type => "string"

attribute "tensorflow/mkl",
          :description => "'true' to install Intel MKL support, 'false' (default) for no support. ",
          :type => "string"

attribute "tensorflow/rdma",
          :description => "Used by TensorflowOnSpark. 'true' to install rdma (infiniband) support, 'false' (default) for no rdma support. ",
          :type => "string"

attribute "install/dir",
          :description => "Set to a base directory under which we will install.",
          :type => "string"

attribute "install/user",
          :description => "User to install the services as",
          :type => "string"

attribute "cuda/accept_nvidia_download_terms",
          :description => "Accept cuda licensing terms and conditions. Default: 'false'. Change to 'true' to enable cuda.",
          :type => "string"

attribute "cuda/skip_test",
          :description => "Dont check if there is a local nvidia card on this machine",
          :type => "string"

attribute "cuda/skip_stop_xserver",
          :description => "Dont restart the xserver (probably a localhost installation)",
          :type => "string"

