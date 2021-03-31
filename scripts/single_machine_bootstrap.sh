#!/bin/bash

echo whoami $(whoami)

# install as root on both master and compute nodes
# ------------------------------------------------
yum clean all
yum-config-manager -y --add-repo https://copr.fedorainfracloud.org/coprs/nalimilan/julia/repo/epel-7/nalimilan-julia-epel-7.repo
yum -y install tmux zsh git julia

# install as root differently on master or compute node
# -----------------------------------------------------
. "/etc/parallelcluster/cfnconfig"
case "${cfn_node_type}" in
    MasterServer)
        echo "I am the head node" >> /tmp/head.txt
    ;;
    ComputeFleet)
        echo "I am a compute node" >> /tmp/compute.txt
    ;;
    *)
    ;;
esac

# install as centos user on both master and compute nodes
# -------------------------------------------------------

# julia packages are not found when installed as root
su - centos
echo whoami $(whoami)
julia -e 'using Pkg; Pkg.add("JuliaDB")'
julia -e 'using JuliaDB'
exit
echo "everything setup"