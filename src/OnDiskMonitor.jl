## -------------------------------------------------------------------
const _UPDATE_RECORD = Dict()
const _WATCHING_TASKS = Dict()

## -------------------------------------------------------------------
mutable struct OnDiskMonitor
    last_save_time::Real
    dt::Real
    file::String
    cache::Dict # Only for ram data
    lk::ReentrantLock
    
    function OnDiskMonitor(p, ps...; dt = 10, lock = ReentrantLock())
        file = joinpath(p, ps...)
        # clear && rm(file; force = true)
        last_save_time = -1.0 # ensure to save the first time
        cache = Dict()
        new(last_save_time, dt, file, cache, lock)
    end
end

_worw_lock(f::Function, lk, dolk::Bool) = dolk ? lock(f, lk) : f()

function sync_from_disk!(m::OnDiskMonitor; dolk = true)
    !isfile(m.file) && return m
    _worw_lock(m.lk, dolk) do
        m.cache = deserialize(m.file)
    end
    m
end

"""
`OnDiskMonitor(file::String; dt = 10, lock = ReentrantLock())`

Example
```
n = 100
m = OnDiskMonitor("path/to/file")
# Watch task (It can be in another process)
watch(m) do dat
    xs = dat[:xs]
    ys = dat[:ys]
    p = scatter(xs, yx; 
        xlabel = "x", ylabel = "y", label = "",
        color = rand([:red, :green, :blue])
    )
    figfile = joinpath(dirname(m.file), "fig1.png")
    sfig(p, figfile)
end

# Fake job to monitor (All is tread save by default)
@threads for i in 1:n
    x = 10*pi*i/n
    y = sin(x)^2
    record!(m) do dat
        push!(get!(dat, :xs, []), x)
        push!(get!(dat, :ys, []), y)
    end
    sleep(10.0/n)
end
sync_to_disk(m)
```
"""
OnDiskMonitor

function sync_to_disk(m::OnDiskMonitor; dolk = true)
    _worw_lock(m.lk, dolk) do
        serialize(m.file, m.cache)
    end
    m
end

function clear_file(m::OnDiskMonitor; dolk = true)
    !isfile(m.file) && return m
    _worw_lock(m.lk, dolk) do
        rm(m.file; force = true)
    end
    m
end

"""
`watch(onupdate::Function, m::OnDiskMonitor; dolk = true, wt = m.dt, iters = typemax(Int))`.

Will start a task (using `@async`) that checks every `wt` secunds if the 
monitored file changed.
If so, will load the data and execute `onupdate` passing that data as only argument.
`dolk` controls wheather to use the monitor lock or not.
`iters` controls how many check iters to do (mostly for dev).

Example
```
m = OnDiskMonitor("path/to/file")
watch(m) do dat
    xs = dat[:xs]
    ys = dat[:ys]
    p = plot(xs, yx; 
        xlabel = "x", ylabel = "y", label = "",
        color = rand([:red, :green, :blue])
    )
    figfile = joinpath(dirname(m.file), "fig1.png")
    sfig(p, figfile)
end
```
"""
function watch(onupdate::Function, m::OnDiskMonitor; 
        dolk = true, wt = m.dt, iters = typemax(Int), 
        onerr = (err) -> @warn("Error on loading/update", err)
    )

    # register task 
    funhash = hash(onupdate)
    _worw_lock(m.lk, dolk) do
        _WATCHING_TASKS[m.file] = funhash
    end

    for it in 1:iters
        sleep(wt)
        
        # Register task
        !isfile(m.file) && continue
        _worw_lock(m.lk, dolk) do
            lmtime = get!(_UPDATE_RECORD, m.file, -1.0)
            fmtime = mtime(m.file)
            if lmtime != fmtime
                try
                    dat = deserialize(m.file)
                    onupdate(dat)
                    catch err; onerr(err)
                end
            end
            _UPDATE_RECORD[m.file] = fmtime
        end

        reghash = get(_WATCHING_TASKS, m.file, nothing)
        reghash != funhash && break
    end
    return nothing
end

"""
`record!(add_to_cache!::Function, m::OnDiskMonitor; dolk = true)`

Execute the given function `add_to_cache!` passing the monitor internal 
cache (a `Dict`) as its only argument. 
After that, it uses `m.dt` to check is the data must be saved 
to disk. 
If so, it create/overwrite `m.file`.
`dolk` controls wheather to use the monitor lock or not.

Example
```
n = 100
m = OnDiskMonitor("path/to/file")
for i in 1:n
    x = 10*pi*i/n
    y = sin(x)^2
    record!(m) do dat
        push!(get!(dat, :xs, []), x)
        push!(get!(dat, :ys, []), y)
    end
    sleep(10.0/n)
end
```
"""
function record!(add_to_cache!::Function, m::OnDiskMonitor; dolk = true)
    _worw_lock(m.lk, dolk) do
        add_to_cache!(m.cache)

        curr_time = time()
        dosave = (curr_time - m.last_save_time) > m.dt
        if dosave
            m.last_save_time = curr_time
            sync_to_disk(m; dolk = false)
        end
    end
end


"""
`reset!(m; dolk = true)`

Reset (empty!) the internal monitor cache and also the data at `m.file`.
`dolk` controls wheather to use the monitor lock or not.
"""
function reset!(m::OnDiskMonitor; dolk = true)
    _worw_lock(m.lk, dolk) do
        empty!(m.cache)
        isfile(m.file) && sync_to_disk(m; dolk = false)
        finish_watch_task(m)
    end
    m
end

function finish_watch_task(m::OnDiskMonitor)
    _WATCHING_TASKS[m.file] = nothing
end

get_cache(m::OnDiskMonitor) = m.cache