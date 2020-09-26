#
# Name
# 2017-08-01
#
# Important Build-Time Environment Variables (see name-defines.inc)
# NO_PACKAGE=1    -> Do Not Build/Rebuild Package RPM
# NO_MODULEFILE=1 -> Do Not Build/Rebuild Modulefile RPM
#
# Important Install-Time Environment Variables (see post-defines.inc)
# RPM_DBPATH      -> Path To Non-Standard RPM Database Location
#
# Typical Command-Line Example:
# ./build_rpm.sh Bar.spec
# cd ../RPMS/x86_64
# rpm -i --relocate /tmprpm=/opt/apps Bar-package-1.1-1.x86_64.rpm
# rpm -i --relocate /tmpmod=/opt/apps Bar-modulefile-1.1-1.x86_64.rpm
# rpm -e Bar-package-1.1-1.x86_64 Bar-modulefile-1.1-1.x86_64

%global __os_install_post %{nil}

%define shortsummary Apache Spark is an open-source distributed general-purpose cluster-computing framework
Summary: %{shortsummary}

# Give the package a base name
%define pkg_base_name spark

# Create some macros (spec file variables)
%define major_version 3
%define minor_version 0
%define patch_version 1

%define pkg_version %{major_version}.%{minor_version}.%{patch_version}

### Toggle On/Off ###
%include ./include/system-defines.inc
%include ./include/%{PLATFORM}/rpm-dir.inc                  
%include ./include/%{PLATFORM}/compiler-defines.inc
#%include ./include/%{PLATFORM}/mpi-defines.inc
%include ./include/%{PLATFORM}/name-defines.inc
########################################
############ Do Not Remove #############
########################################

############ Do Not Change #############
Name:      %{pkg_name}
Version:   %{pkg_version}
########################################

Release:   1
License:   BSD
Group:     Applications/Life Sciences
URL:       https://spark.apache.org/
Packager:  TACC - gzynda@tacc.utexas.edu
Source:    %{pkg_base_name}-%{pkg_version}-bin-hadoop3.2.tgz

%package %{PACKAGE}
Summary: %{shortsummary}
Group:   Applications/Life Sciences
%description package
%{pkg_base_name}: %{shortsummary}

%package %{MODULEFILE}
Summary: The modulefile RPM
Group:   Lmod/Modulefiles
%description modulefile
Module file for %{pkg_base_name}

%description
%{pkg_base_name}: %{shortsummary}

#---------------------------------------
%prep
#---------------------------------------

#------------------------
%if %{?BUILD_PACKAGE}
#------------------------
  # Delete the package installation directory.
  rm -rf $RPM_BUILD_ROOT/%{INSTALL_DIR}

# Comment this out if pulling from git
%setup -qn %{pkg_base_name}-%{pkg_version}-bin-hadoop3.2
# If using multiple sources. Make sure that the "-n" names match.
#%setup -T -D -a 1 -n %{pkg_base_name}-%{pkg_version}

#-----------------------
%endif # BUILD_PACKAGE |
#-----------------------

#---------------------------
%if %{?BUILD_MODULEFILE}
#---------------------------
  #Delete the module installation directory.
  rm -rf $RPM_BUILD_ROOT/%{MODULE_DIR}
#--------------------------
%endif # BUILD_MODULEFILE |
#--------------------------

#---------------------------------------
%build
#---------------------------------------


#---------------------------------------
%install
#---------------------------------------

# Setup modules
%include ./include/%{PLATFORM}/system-load.inc
##################################
# If using build_rpm
##################################
%include ./include/%{PLATFORM}/compiler-load.inc
#%include ./include/%{PLATFORM}/mpi-load.inc
#%include ./include/%{PLATFORM}/mpi-env-vars.inc
##################################
# Manually load modules
##################################
# module load
##################################

echo "Building the package?:    %{BUILD_PACKAGE}"
echo "Building the modulefile?: %{BUILD_MODULEFILE}"

#------------------------
%if %{?BUILD_PACKAGE}
#------------------------

  mkdir -p $RPM_BUILD_ROOT/%{INSTALL_DIR}
  
  #######################################
  ##### Create TACC Canary Files ########
  #######################################
  touch $RPM_BUILD_ROOT/%{INSTALL_DIR}/.tacc_install_canary
  #######################################
  ########### Do Not Remove #############
  #######################################

  #========================================
  # Insert Build/Install Instructions Here
  #========================================

mv conf/spark-defaults.conf.template conf/spark-defaults.conf
echo "spark.io.compression.codec         org.apache.spark.io.LZ4CompressionCodec" >> conf/spark-defaults.conf
mv conf/spark-env.sh.template conf/spark-env.sh
rm -rf examples
cp -r * $RPM_BUILD_ROOT/%{INSTALL_DIR}

# Install spark-slurm
branch=jupyter
curl -L https://github.com/TACC/spark-slurm/archive/${branch}.tar.gz | tar -xzf -
cp spark-slurm-${branch}/scripts/* $RPM_BUILD_ROOT/%{INSTALL_DIR}/bin/

# Install Jupyter scripts and config
mkdir -p $RPM_BUILD_ROOT/%{INSTALL_DIR}/jupyter/{lib,config,data}
cp spark-slurm-${branch}/jupyter/{jupyter.spark.config.py,sbatch.template} $RPM_BUILD_ROOT/%{INSTALL_DIR}/jupyter/
cp spark-slurm-${branch}/jupyter/{tacc-jupyter.sh,sbatch-jupyter.sh} $RPM_BUILD_ROOT/%{INSTALL_DIR}/bin/

# Install python2 packages
export PYTHONUSERBASE=$RPM_BUILD_ROOT/%{INSTALL_DIR}/jupyter/

module load python2
pip install --user jupyter-spark
module load python3
pip3 install --user jupyter-spark

PYTHONPATH=${PYTHONPATH}:$(ls -d $PYTHONUSERBASE/lib/python3*/site-packages)

# Configure Jupyter
export JUPYTER_CONFIG_DIR=$RPM_BUILD_ROOT/%{INSTALL_DIR}/jupyter/config
#export JUPYTER_PATH=$RPM_BUILD_ROOT/%{INSTALL_DIR}/jupyter/base
export JUPYTER_DATA_DIR=$RPM_BUILD_ROOT/%{INSTALL_DIR}/jupyter/data

jupyter serverextension enable --py jupyter_spark
jupyter nbextension install --py --user jupyter_spark
jupyter nbextension enable --py jupyter_spark
jupyter nbextension enable --py widgetsnbextension

#-----------------------  
%endif # BUILD_PACKAGE |
#-----------------------


#---------------------------
%if %{?BUILD_MODULEFILE}
#---------------------------

  mkdir -p $RPM_BUILD_ROOT/%{MODULE_DIR}
  
  #######################################
  ##### Create TACC Canary Files ########
  #######################################
  touch $RPM_BUILD_ROOT/%{MODULE_DIR}/.tacc_module_canary
  #######################################
  ########### Do Not Remove #############
  #######################################
  
# Write out the modulefile associated with the application
cat > $RPM_BUILD_ROOT/%{MODULE_DIR}/%{MODULE_FILENAME} << 'EOF'
local help_message = [[
Please review the detailed usage available at

   https://github.com/TACC/spark-slurm

for optimal usage on TACC systems.

=====================================================

Otherwise, please interact with spark as follows:

1. Start spark

  $ tacc-start.sh

2. Do work:

   a. Submit tasks:

      $ tacc-submit.sh --master spark://$HOSTNAME:7077 
           --name "job name" program.py arg1 arg2

   b. Run jupyter:

      $ tacc-jupyter.sh

3. Shut the cluster down

  $ tacc-stop.sh

%{pkg_base_name} documentation: %{url}

Version %{version}
]]

help(help_message,"\n")

whatis("Name: %{pkg_base_name}")
whatis("Version: %{version}")
whatis("Category: data, machine learning, python")
whatis("Keywords: data, distributed, java, scala")
whatis("Description: %{shortsummary}")
whatis("URL: %{url}")

local spark = "%{INSTALL_DIR}"
local jupyter = pathJoin(spark,"jupyter")
local loc_dir = pathJoin(os.getenv("SCRATCH"),"spark/local")
local log_dir = pathJoin(os.getenv("SCRATCH"),"spark/logs")

prereq_any("python2","python3")

setenv("SPARK_HOME",            spark)
setenv("MALLOC_ARENA_MAX",      2)
--setenv("SPARK_LOCAL_DIRS",    "/tmp/spark," .. loc_dir)
setenv("SPARK_LOCAL_DIRS",      "/tmp/spark/local")
setenv("SPARK_WORKER_DIR",      "/tmp/spark/work")
setenv("SPARK_PID_DIR",		"/tmp/spark")
setenv("SPARK_LOG_DIR",         log_dir)
setenv("SPARK_MASTER_PORT",     7077)
setenv("SPARK_MASTER_WEBUI_PORT",8077)

-- Create directories if they dont exist
for i,v in ipairs({"/tmp/spark",loc_dir,log_dir}) do
        if not isDir(v) then
                --LmodMessage("making " .. v)
                execute{cmd="mkdir -p " .. v, modeA={"load"}}
        end
end

prepend_path("R_LIBS",          pathJoin(spark,"R/lib"))
prepend_path("PATH",            pathJoin(spark,"bin"))
--prepend_path("PATH",          pathJoin(spark,"sbin"))
prepend_path("JUPYTER_CONFIG_DIR",	pathJoin(jupyter,"config"))
prepend_path("JUPYTER_PATH",		pathJoin(jupyter,"data"))
--prepend_path("JUPYTER_DATA_DIR",	pathJoin(jupyter,"data"))
prepend_path("PYTHONPATH",      pathJoin(spark,"python/lib/pyspark.zip"))
prepend_path("PYTHONPATH",      pathJoin(spark,"python/lib/py4j-0.10.9-src.zip"))
setenv("PYSPARK_PYTHONPATH_SET","1")
EOF
  
cat > $RPM_BUILD_ROOT/%{MODULE_DIR}/.version.%{version} << 'EOF'
#%Module3.1.1#################################################
##
## version file for %{BASENAME}%{version}
##

set     ModulesVersion      "%{version}"
EOF
  
  # Check the syntax of the generated lua modulefile
  %{SPEC_DIR}/scripts/checkModuleSyntax $RPM_BUILD_ROOT/%{MODULE_DIR}/%{MODULE_FILENAME}

#--------------------------
%endif # BUILD_MODULEFILE |
#--------------------------


#------------------------
%if %{?BUILD_PACKAGE}
%files package
#------------------------

  %defattr(-,root,install,)
  # RPM package contains files within these directories
  %{INSTALL_DIR}

#-----------------------
%endif # BUILD_PACKAGE |
#-----------------------
#---------------------------
%if %{?BUILD_MODULEFILE}
%files modulefile 
#---------------------------

  %defattr(-,root,install,)
  # RPM modulefile contains files within these directories
  %{MODULE_DIR}

#--------------------------
%endif # BUILD_MODULEFILE |
#--------------------------


########################################
## Fix Modulefile During Post Install ##
########################################
%post %{PACKAGE}
export PACKAGE_POST=1
%include ./include/%{PLATFORM}/post-defines.inc
%post %{MODULEFILE}
export MODULEFILE_POST=1
%include ./include/%{PLATFORM}/post-defines.inc
%preun %{PACKAGE}
export PACKAGE_PREUN=1
%include ./include/%{PLATFORM}/post-defines.inc
########################################
############ Do Not Remove #############
########################################

#---------------------------------------
%clean
#---------------------------------------
rm -rf $RPM_BUILD_ROOT
