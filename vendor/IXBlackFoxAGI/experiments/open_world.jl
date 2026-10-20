using IXBlackFoxAGI
using TOML
using Random
using SHA
include("Worlds.jl")
using .Worlds

function run()
    rows=Dict{String,Any}[]
    firstseed=parse(Int,get(ENV,"IXBF_OPEN_WORLD_START","301"))
    nseeds=parse(Int,get(ENV,"IXBF_OPEN_WORLD_CASES","20"))
    1<=nseeds<=100 || error("invalid cold acquisition case count")
    for seed in firstseed:firstseed+nseeds-1
        for mode in ("learning_planner","random")
            inner=Worlds.Blocks(seed;n=3,prefix="newdomain"*string(seed))
            env=Worlds.Renamed(inner,seed)
            goal=Worlds.renamegoal(env,Worlds.blocks_goal(inner))
            mind=Mind(seed=seed)
            start=time()
            if mode=="learning_planner"
                result=pursue!(mind,env,goal;max_steps=300,max_expansions=2000)
                steps=result.steps;planned=result.planned_steps;exploration=result.exploratory_steps
            else
                steps=0
                while steps<300 && !reached(goal,perceive(env))
                    act!(mind,env,rand(mind.rng,commands(env));learning=false)
                    steps+=1
                end
                planned=0;exploration=steps
            end
            push!(rows,Dict("seed"=>seed,"mode"=>mode,"success"=>reached(goal,perceive(env)),
                "steps"=>steps,"planned_steps"=>planned,"exploratory_steps"=>exploration,
                "surprises"=>mind.surprises,"seconds"=>time()-start,
                "initial_known_schemas"=>0,"final_learned_schemas"=>length(mind.world.actions)))
            println(last(rows));flush(stdout)
        end
    end
    outdir=joinpath(@__DIR__,"..","results","open_world")
    mkpath(outdir)
    open(joinpath(outdir,"report.toml"),"w") do io
        TOML.print(io,Dict("cases"=>rows,"max_steps"=>300,"julia_version"=>string(VERSION),
            "implementation_sha256"=>IXBlackFoxAGI.implementation_digest(),
            "evaluation_source_sha256"=>bytes2hex(sha256(read(@__FILE__)))),sorted=true)
    end
    all(r->r["success"],[r for r in rows if r["mode"]=="learning_planner"]) ||
        error("cold-acquisition failures recorded; inspect report.toml")
end
run()
