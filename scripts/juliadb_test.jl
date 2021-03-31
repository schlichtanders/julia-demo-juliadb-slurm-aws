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