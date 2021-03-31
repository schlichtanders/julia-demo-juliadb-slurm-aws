# BigData with JuliaDB.jl

Welcome to this little demo about how to use Julia to do bigdata ETL tasks on AWS. We setup a high-performance-cluster (HPC) on AWS, and run a distributed JuliaDB.jl job.

# Prerequisites

1. [install aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) and add a profile for your reply account, we call it`"reply"` here
2. choose a region where you can spawn a new VPC (there is a default threshold of max 5 VPC per region), e.g.`us-east-2`
3. create a keypair in that region for you, download your key to let's say`~/credentials/mykey.cer`
4. run`chmod 400 ~/credentials/mykey.cer`
5. S3 bucket with example data, e.g.`s3://ssahm-ohio-hpc-test`

# Slurm Cluster

We use [slurm](https://slurm.schedmd.com/documentation.html) as our cluster manager. It is the most wide-spread open source cluster manager with support through [aws parallelcluster](https://docs.aws.amazon.com/parallelcluster/index.html). There are also a couple of julia tutorials about how to use slurm for distributed computation.

In addition to a standard HPC, we add FSx Lustre as our Filesystem in order to get super fast and convenient access to resources on S3. It is a POSIX compliant distributed filesystem and as such brings optimal compatibility with file-based routines, even when going distributed.

The main references for this section are [quick-start tutorial from aws-parallelcluster](https://github.com/aws/aws-parallelcluster#quick-start) and [aws tutorial for FSx Lustre on aws-parallelcluster](https://aws.amazon.com/blogs/storage/building-an-hpc-cluster-with-aws-parallelcluster-and-amazon-fsx-for-lustre/).

## Configure Cluster

Let's create cluster configuration

First we need to upload our custom bootstrap script to S3. This will contain the instructions to initialize every machine the same way. Open your terminal in this repository and then run

````bash
export AWS_PROFILE="reply" AWS_DEFAULT_REGION=us-east-2
aws s3 sync scripts/ s3://ssahm-ohio-hpc-test/scripts/
````

Output should look something like

```bash
upload: scripts/single_machine_bootstrap.sh to s3://ssahm-ohio-hpc-test/scripts/single_machine_bootstrap.sh
```

Now we can start configuration of our cluster by running

```bash
export AWS_PROFILE="reply" AWS_DEFAULT_REGION=us-east-2
pcluster configure
```

Use the following parameters

| parameter | value |
| - | - |
| Region | us-east-2 |
| Scheduler | slurm (needed for FSx Lustre support) |
| Operating System | centos7 (needed for FSx Lustre support) |
| Minimum cluster size | 3 |
| Maximum cluster size | 5 |
| master instance type | t3.medium |
| compute instance type | t3.medium |
| Automate VPC creation | y |
| Network Configuration | "Head node and compute fleet in the same public subnet" |

Note that we cannot use t3.micro, as we run into memory problems. The same has already been reported on [discourse.julialang.org](https://discourse.julialang.org/t/some-added-modules-fail-on-not-loading-lib-julia-sys-so/37772/9) where a minimum of 2 GB RAM was necessary.

Add the following extra config to your cluster configuration: (adapted from documentation about [fluster integration](https://aws-parallelcluster.readthedocs.io/en/latest/configuration.html#fsx-section) and [initial installations](https://docs.aws.amazon.com/parallelcluster/latest/ug/pre_post_install.html))

```toml
[cluster default]
...
s3_read_write_resource = arn:aws:s3:::ssahm-ohio-hpc-test/*
post_install = s3://ssahm-ohio-hpc-test/scripts/single_machine_bootstrap.sh
post_install_args = ''
fsx_settings = myfsx

[fsx myfsx]
shared_dir = /fsx
import_path = s3://ssahm-ohio-hpc-test
imported_file_chunk_size = 1024
export_path = s3://ssahm-ohio-hpc-test/fsx_output
storage_capacity = 1200 # GiB, minimum
```

## Starting Cluster

In order to spawn a cluster run the following

```bash
export AWS_PROFILE="reply" AWS_DEFAULT_REGION=us-east-2
pcluster create myfirstcluster
```

Creating the cluster may take about 20-30 minutes.

The final output looks something like

```bash
Beginning cluster creation for cluster: myfirstcluster
Creating stack named: parallelcluster-myfirstcluster
Status: parallelcluster-myfirstcluster - CREATE_COMPLETE
MasterPublicIP: 3.143.107.239
ClusterUser: centos
MasterPrivateIP: 10.0.11.218
```

## Connecting to the Cluster

For connecting we use `pcluster ssh`, however this time we need to point the command to our custom key file by providing the standard ssh argument `-i`.

```bash
export AWS_PROFILE="reply" AWS_DEFAULT_REGION=us-east-2
pcluster ssh myfirstcluster -i ~/reply-credentials/mlreply_ohio_ssahm.cer
```

## Delete Cluster

In order to delete your cluster again you first need to log-out of the cluster in case your are still logged in. Then simply run

```bash
pcluster delete myfirstcluster
```

Deletion may take about 20-30 minutes.

# Slurm Job

For an introduction into slurm, I can recommend slurm's [quickstart tutorial](https://slurm.schedmd.com/quickstart.html). 

Slurm jobs are usually started using the [sbatch](https://slurm.schedmd.com/sbatch.html) command-line utility. However, in order to use it, we need some preparations.

## Configure Julia Script

The instructions are adapted from an old but well-automatized example [from Christopher Rackauckas&#39;s blog](http://www.stochasticlifestyle.com/multi-node-parallelism-in-julia-on-an-hpc/).

We created both a julia test script `scripts/juliadb_test.jl` as well as a sbatch job script `scripts/juliadb_test.jl.sbatch.sh`. They look like this

`juliadb_test.jl`

```julia
using Distributed
hosts = []
pids = []
for i in workers()
        host, pid = fetch(@spawnat i (gethostname(), getpid()))
        @show host
        push!(hosts, host)
        push!(pids, pid)
end
@show hosts
@show pids
```

`juliadb_test.jl.sbatch.sh`

```bash
#!/bin/bash
#SBATCH -A <account>
#SBATCH --job-name="juliaTest"
#SBATCH --output="juliaTest.%j.%N.out"
#SBATCH --partition=compute
#SBATCH --nodes=4
#SBATCH --export=ALL
#SBATCH --ntasks-per-node=2
#SBATCH -t 01:00:00
julia --machine-file $(generate_pbs_nodefile) /fsx/scripts/juliadb_test.jl
```

## Run julia script

After connecting to the cluster with `pcluster ssh` we can run our job using

```bash
sbatch -N2 -o ./output.txt ./juliadb_test.jl.sbatch.sh
```

* `-N2` says that we should only use 2 Nodes, overwriting the 4 nodes mentioned in the sbatch comments in the file. That is needed because our cluster has only 2 nodes for now.
* `-o ./output.txt` specifies the output file where stdout is written to, i.e. where you can see the output from your script

For more details on sbatch, consult [the slurm documentation](https://slurm.schedmd.com/sbatch.html).

In order to monitor the output you can run

```bash
watch cat ./output.txt
```

After a second or so, you should see an output similar to

```
Warning: Permanently added 'compute-st-t2medium-1,10.0.10.92' (ECDSA) to the list of known hosts.
Warning: Permanently added 'compute-st-t2medium-2,10.0.2.135' (ECDSA) to the list of known hosts.
host = "compute-st-t2medium-1"
host = "compute-st-t2medium-2"
host = "compute-st-t2medium-2"
host = "compute-st-t2medium-1"
hosts = Any["compute-st-t2medium-1", "compute-st-t2medium-2", "compute-st-t2medium-2", "compute-st-t2medium-1"]
pids = Any[7082, 7244, 7287, 7126]
```

# Slurm Interactive Console

When working with an interactive language like julia it can be super handy to also work interactively on a the cluster. Slurm actually supports this nicely, you just need to run

```bash
salloc -N2 --ntasks-per-node=2 bash
```

To start a new bash shell with a cluster in the background. Connecting julia to the cluster is exactly the same like when using sbatch:

```bash
julia --machine-file $(generate_pbs_nodefile)
```

Running `using Distributed; nworkers()` in the julia shell should output `4`.

# JuliaDB.jl

Having a high performance cluster, we want to do some Big Data task on it. Traditionally you would use Hadoop MapReduce or Apache Spark for it, however, that can be quite clumsy.

Using Julia we can reduce start-up time and overall complexity of the setup. The [JuliaDB.jl](https://juliadb.org/) package already comes with multi-core and multi-machine processing capabilities, building upon Julia's builtin parallelization support. In the little example above when testing the slurm cluster, you've already seen how easy it is to start Julia on a full cluster.
