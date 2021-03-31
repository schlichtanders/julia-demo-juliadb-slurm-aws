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