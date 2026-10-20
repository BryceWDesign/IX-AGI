using IXBlackFoxAGI
using Random
using TOML
using Statistics
using SHA
include("Worlds.jl")
using .Worlds

function makecase(kind::String,seed::Int)
    if kind=="courier"
        e=Worlds.Courier(seed;nlocations=5,prefix="test"*string(seed))
        return e,Worlds.courier_goal(e)
    elseif kind=="switchboard"
        e=Worlds.Switchboard(seed;n=7,prefix="test"*string(seed))
        return e,Worlds.switch_goal(e)
    elseif kind=="workshop"
        e=Worlds.Workshop(seed;n=4,prefix="test"*string(seed))
        return e,Worlds.workshop_goal(e)
    elseif kind=="combined"
        e=Worlds.Combined(Worlds.Courier(seed;nlocations=4,prefix="test"*string(seed)),
                          Worlds.Workshop(seed+1;n=2,prefix="testjob"*string(seed)))
        return e,Worlds.combined_goal(e)
    end
    error("unknown host evaluation adapter")
end

function frozenmind(trained::Mind,seed::Int;procedures::Bool=false)
    m=Mind(seed=seed)
    m.world=trained.world
    procedures && (m.procedures=trained.procedures)
    m
end

function baseline!(m::Mind,env::Environment,g::Goal,mode::String;max_steps::Int=40)
    for i in 0:max_steps
        reached(g,perceive(env)) && return i,true
        i==max_steps && break
        a=mode=="random" ? rand(m.rng,commands(env)) :
                           investigate(m,perceive(env),commands(env);goal=g)
        a===nothing && return i,false
        act!(m,env,a;learning=false)
    end
    max_steps,false
end

function run_suite()
    nseeds=parse(Int,get(ENV,"IXBF_LIFETIME_SEEDS","5"))
    ncases=parse(Int,get(ENV,"IXBF_LIFETIME_CASES","8"))
    1<=nseeds<=30 && 1<=ncases<=100 || error("evaluation sizes out of bounds")
    outdir=get(ENV,"IXBF_RESULTS",joinpath(@__DIR__,"..","results","lifetime"))
    mkpath(outdir)
    rows=Dict{String,Any}[]
    training=Dict{String,Any}[]
    start=time()
    for seed in 101:(100+nseeds)
        trained=Mind(seed=seed)
        t=time()
        Worlds.train!(trained;seed)
        # Procedure discovery uses separate practice worlds, never held-out cases.
        for i in 1:6
            e=Worlds.Workshop(seed*4000+i;n=2,prefix="practice"*string(i))
            pursue!(trained,e,Worlds.workshop_goal(e);explore=false)
        end
        push!(training,Dict("seed"=>seed,"transitions"=>trained.world.observations,
            "seconds"=>time()-t,"schemas"=>length(trained.world.actions),
            "procedures"=>count(IXBlackFoxAGI.usable,values(trained.procedures)),
            "unsupported_effects"=>trained.world.unsupported_effects))
        fixed_observations=trained.world.observations
        for (k,kind) in enumerate(("courier","switchboard","workshop","combined")), i in 1:ncases
            case_seed=900_000+seed*1000+k*100+i
            env,g=makecase(kind,case_seed)
            # Do not inflate success with goals already satisfied before acting.
            while reached(g,perceive(env))
                case_seed+=100_000
                env,g=makecase(kind,case_seed)
            end
            initial_distance=IXBlackFoxAGI.distance(g,perceive(env))
            for mode in ("planner","reactive","random")
                env,g=makecase(kind,case_seed)
                m=frozenmind(trained,case_seed)
                tcase=time()
                if mode=="planner"
                    r=pursue!(m,env,g;max_steps=40,explore=false,learning=false,use_procedures=false)
                    steps=r.steps; success=reached(g,perceive(env))
                    expansions=r.expansions;status=string(r.status)
                else
                    steps,success=baseline!(m,env,g,mode)
                    expansions=0;status=success ? "achieved" : "step_limit"
                end
                push!(rows,Dict("training_seed"=>seed,"case_seed"=>case_seed,
                    "domain"=>kind,"mode"=>mode,"success"=>success,"steps"=>steps,
                    "status"=>status,"expansions"=>expansions,"surprises"=>m.surprises,
                    "predictions_made"=>count(e->e["kind"]=="transition" && e["predicted"]!==false,m.trace),
                    "initial_distance"=>initial_distance,"seconds"=>time()-tcase,
                    "learning_during_evaluation"=>false))
            end
            @assert trained.world.observations==fixed_observations
        end
        # A never-trained environment provides a cold-model negative control.
        cold_env,cold_goal=makecase("combined",seed+600_000)
        cold=Mind(seed=seed)
        cold_result=pursue!(cold,cold_env,cold_goal;explore=false,learning=false)
        @assert cold_result.status!=:achieved
        save_mind(trained,joinpath(outdir,"trained-seed-"*string(seed)*".toml"))
        println("Training seed ",seed," complete, held-out cases ",4*ncases)
        flush(stdout)
    end
    summary=Dict{String,Any}[]
    for kind in ("courier","switchboard","workshop","combined"), mode in ("planner","reactive","random")
        subset=[r for r in rows if r["domain"]==kind && r["mode"]==mode]
        push!(summary,Dict("domain"=>kind,"mode"=>mode,"solved"=>count(r->r["success"],subset),
            "total"=>length(subset),"mean_steps"=>mean(r["steps"] for r in subset),
            "prediction_errors"=>sum(r["surprises"] for r in subset),
            "predictions_made"=>sum(r["predictions_made"] for r in subset)))
    end
    report=Dict("julia_version"=>string(VERSION),"platform"=>string(Sys.KERNEL),
        "implementation_sha256"=>IXBlackFoxAGI.implementation_digest(),
        "evaluation_source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "training_seed_count"=>nseeds,"cases_per_domain_per_seed"=>ncases,
        "max_actions_per_case"=>40,"elapsed_seconds"=>time()-start,
        "training"=>training,"summary"=>summary,"cases"=>rows)
    open(joinpath(outdir,"report.toml"),"w") do io;TOML.print(io,report;sorted=true);end
    open(joinpath(outdir,"cases.csv"),"w") do io
        columns=["training_seed","case_seed","domain","mode","success","steps","status",
                 "expansions","surprises","predictions_made","initial_distance","seconds","learning_during_evaluation"]
        println(io,join(columns,","))
        for row in rows; println(io,join([string(row[c]) for c in columns],","));end
    end
    for s in summary;println(s);end
    all(s->s["solved"]==s["total"],[s for s in summary if s["mode"]=="planner"]) ||
        error("held-out planning failures recorded; inspect report.toml")
    report
end

run_suite()
