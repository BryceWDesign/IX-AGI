"""Adapters expose observations and syntactic commands, never their hidden dynamics."""
abstract type Environment end
perceive(::Environment) = error("adapter must implement perceive")
commands(::Environment) = error("adapter must implement commands")
transition!(::Environment,::Command) = error("adapter must implement transition!")

mutable struct Mind
    world::WorldMemory
    procedures::Dict{String,Procedure}
    budget::Int
    visits::Dict{String,Int}
    trace::Vector{Dict{String,Any}}
    surprises::Int
    denied::Int
    rng::MersenneTwister
end
function Mind(;budget::Int=100_000,seed::Int=1,max_evidence::Int=512)
    0<=budget<=1_000_000 || throw(ArgumentError("invalid native authority budget"))
    Mind(WorldMemory(;max_evidence),Dict{String,Procedure}(),budget,Dict{String,Int}(),Dict{String,Any}[],
         0,0,MersenneTwister(seed))
end

factdata(f::Fact) = Dict("predicate"=>f.predicate,"terms"=>collect(f.terms))
factsdata(s::Situation) = [factdata(f) for f in sort!(collect(s),by=factkey)]
function stabletext(value)
    if value isa AbstractDict
        return "{"*join([repr(string(k))*":"*stabletext(value[k]) for k in sort!(collect(keys(value)))],",")*"}"
    elseif value isa AbstractVector || value isa Tuple
        return "["*join(stabletext.(value),",")*"]"
    else
        return repr(value)
    end
end
digest(value) = bytes2hex(sha256(stabletext(value)))
function visitkey(s::Situation,a::Command)
    digest((factsdata(localize(s,a)),a.name,length(a.args)))
end
function record!(m::Mind,event::Dict{String,Any})
    event["sequence"]=length(m.trace)+1
    event["previous"]=isempty(m.trace) ? repeat("0",64) : last(m.trace)["hash"]
    event["hash"]=digest(event)
    push!(m.trace,event)
end
function verify_trace(trace::Vector)
    previous=repeat("0",64)
    for (i,e) in enumerate(trace)
        get(e,"sequence",0)==i || return false
        get(e,"previous","")==previous || return false
        payload=Dict(k=>v for (k,v) in e if k!="hash")
        get(e,"hash","")==digest(payload) || return false
        previous=e["hash"]
    end
    true
end

"""The only runtime command dispatch path; the Ada decision precedes the adapter."""
function act!(m::Mind,env::Environment,a::Command;permission::Int=1,risk::Int=0,
              learning::Bool=true,cognitive_mode::String="unreported",
              cognitive_reason::String="")
    before=perceive(env)
    if !(a in commands(env))
        m.denied+=1
        return :invalid_command
    end
    decision=authorize(1;permission,risk,cost=1,budget=m.budget)
    if decision!=1
        m.denied+=1
        record!(m,Dict{String,Any}("kind"=>"denied","command"=>a.name,
                "args"=>collect(a.args),"decision"=>decision,"permission"=>permission,
                "risk"=>risk,"budget"=>m.budget))
        return :denied
    end
    predicted=imagine(m.world,before,a)
    m.budget-=1 # includes a failed adapter attempt
    transition!(env,a)
    after=perceive(env)
    surprise=predicted!==nothing && predicted!=after
    m.surprises+=Int(surprise)
    key=visitkey(before,a)
    m.visits[key]=get(m.visits,key,0)+1
    status=learning ? learn!(m.world,before,a,after) : :frozen
    record!(m,Dict{String,Any}("kind"=>"transition","command"=>a.name,
        "args"=>collect(a.args),"before"=>factsdata(before),"after"=>factsdata(after),
        "predicted"=>predicted===nothing ? false : factsdata(predicted),
        "surprise"=>surprise,"learned"=>string(status),"budget"=>m.budget,
        "permission"=>permission,"risk"=>risk,"decision"=>decision,
        "cognitive_mode"=>cognitive_mode,"cognitive_reason"=>cognitive_reason))
    status
end

"""Optimistic information-seeking, with empirical local-context visit penalties.
The score is a heuristic, NOT a Bayesian information-gain calculation.
"""
function investigate(m::Mind,s::Situation,actions::Vector{Command};
                     goal::Union{Nothing,Goal}=nothing,concept_library=nothing)
    isempty(actions) && return nothing
    ordered=sort!(unique(actions),by=commandkey)
    scores=Float64[]
    for a in ordered
        memory=get(m.world.actions,schema(a),nothing)
        n=memory===nothing ? 0 : length(memory.evidence)
        visits=get(m.visits,visitkey(s,a),0)
        predicted=imagine(m.world,s,a)
        novelty=4/sqrt(1+visits)+2/sqrt(1+n)
        progress=predicted===nothing || goal===nothing ? 0. :
                 1.5*(distance(goal,s)-distance(goal,predicted))
        mobility=predicted!==nothing && predicted!=s ? 0.15 : 0.
        # Evidence-validated derived features can prioritize promising unknown
        # changes. This is a heuristic exploration bonus, not an effect oracle.
        concept_bonus=concept_library===nothing ? 0.0 :
            (any(c->concept_holds(c,s,a),concept_library) ? 0.40 : 0.0)
        push!(scores,novelty+progress+mobility+concept_bonus)
    end
    best=maximum(scores)
    candidates=findall(x->abs(x-best)<1e-10,scores)
    ordered[rand(m.rng,candidates)]
end

struct EpisodeResult
    status::Symbol
    steps::Int
    planned_steps::Int
    exploratory_steps::Int
    surprises::Int
    expansions::Int
end

"""Observe, plan, act, compare consequences, learn, and replan after every action."""
function pursue!(m::Mind,env::Environment,g::Goal;max_steps::Int=100,
                 max_expansions::Int=5000,explore::Bool=true,learning::Bool=true,
                 use_procedures::Bool=true,cognitive_control::Bool=false,
                 min_prediction_evidence::Int=8,min_prediction_wilson::Float64=0.50)
    max_steps>=0 || throw(ArgumentError("negative episode length"))
    planned=0; exploratory=0; expanded=0; initial_surprises=m.surprises
    successful_commands=Command[]
    trace_start=length(m.trace)+1
    for step in 0:max_steps
        s=perceive(env)
        if reached(g,s)
            if learning
                remember_procedures!(m.procedures,successful_commands)
                record!(m,Dict{String,Any}("kind"=>"episode_achieved","trace_start"=>trace_start,
                    "present"=>factsdata(g.present),"absent"=>factsdata(g.absent),
                    "final"=>factsdata(s)))
            end
            return EpisodeResult(:achieved,step,planned,exploratory,
                                 m.surprises-initial_surprises,expanded)
        end
        step==max_steps && break
        m.budget<=0 && return EpisodeResult(:budget_exhausted,step,planned,exploratory,
                                           m.surprises-initial_surprises,expanded)
        actions=commands(env)
        p=plan(m.world,s,actions,g;max_expansions,
               procedures=use_procedures ? m.procedures : nothing)
        expanded+=p.expansions
        cognitive_mode="unreported"
        cognitive_reason=""
        if cognitive_control && explore
            # The strategy selector consumes *past executed evidence*, never
            # simulator lookahead. Unsupported or unreliable predictions prompt
            # bounded new observations, not unauthorized action.
            choice=cognitive_choice(m,s,actions,g,p;
                min_predictions=min_prediction_evidence,
                min_wilson=min_prediction_wilson)
            a=choice.command
            cognitive_mode=string(choice.mode)
            cognitive_reason=string(choice.reason)
            if choice.mode==:plan
                planned+=1
            else
                exploratory+=1
            end
        elseif p.status==:solved
            a=first(p.commands); planned+=1
        elseif explore
            # When planning is unavailable, acquire dynamics without penalizing
            # temporary goal regression (e.g. picking up before stacking).
            a=investigate(m,s,actions); exploratory+=1
        else
            return EpisodeResult(p.status,step,planned,exploratory,
                                 m.surprises-initial_surprises,expanded)
        end
        a===nothing && return EpisodeResult(:no_commands,step,planned,exploratory,
                                            m.surprises-initial_surprises,expanded)
        result=act!(m,env,a;learning,cognitive_mode,cognitive_reason)
        result in (:denied,:invalid_command) && return EpisodeResult(result,step,planned,
                                   exploratory,m.surprises-initial_surprises,expanded)
        push!(successful_commands,a)
    end
    EpisodeResult(:step_limit,max_steps,planned,exploratory,
                  m.surprises-initial_surprises,expanded)
end

function explore!(m::Mind,env::Environment;steps::Int=100)
    steps>=0 || throw(ArgumentError("negative exploration length"))
    completed=0
    for _ in 1:steps
        m.budget<=0 && break
        a=investigate(m,perceive(env),commands(env))
        a===nothing && break
        act!(m,env,a) in (:learned,:unrepresentable) || break
        completed+=1
    end
    completed
end

"""Persist inspectable evidence and verify it on reload. SHA is integrity, not authentication."""
function save_mind(m::Mind,path::AbstractString)
    verify_trace(m.trace) || throw(ArgumentError("invalid in-memory trace"))
    memories=Dict{String,Any}[]
    for ((name,arity),memory) in sort!(collect(m.world.actions),by=first)
        push!(memories,Dict("name"=>name,"arity"=>arity,"regime"=>memory.regime,
            "evidence"=>[Dict("before"=>factsdata(e.before),"added"=>factsdata(e.added),
                              "removed"=>factsdata(e.removed)) for e in memory.evidence]))
    end
    payload=Dict("format"=>1,"budget"=>m.budget,"surprises"=>m.surprises,
        "denied"=>m.denied,"observations"=>m.world.observations,
        "unsupported_effects"=>m.world.unsupported_effects,"max_evidence"=>m.world.max_evidence,
        "regime_resets"=>m.world.regime_resets,
        "memories"=>memories,"visits"=>m.visits,"trace"=>m.trace,
        "procedures"=>[Dict("steps"=>[Dict("name"=>s.name,"args"=>collect(s.args)) for s in p.steps],
                            "bindings"=>sort!(collect(p.bindings)))
                       for (_,p) in sort!(collect(m.procedures),by=first)])
    mkpath(dirname(abspath(path)))
    text=sprint(io->TOML.print(io,payload;sorted=true))
    tmp=String(path)*".tmp"
    write(tmp,text); mv(tmp,path;force=true)
    write(String(path)*".sha256",bytes2hex(sha256(text))*"\n")
    path
end

function readfacts(data)
    Situation(Fact(String(f["predicate"]),Tuple(String.(f["terms"]))) for f in data)
end
function load_mind(path::AbstractString;seed::Int=1)
    filesize(path)<=128*1024*1024 || throw(ArgumentError("checkpoint too large"))
    text=read(path,String)
    bytes2hex(sha256(text))==strip(read(String(path)*".sha256",String)) ||
        throw(ArgumentError("checkpoint digest mismatch"))
    p=TOML.parse(text)
    p["format"]==1 || throw(ArgumentError("unsupported checkpoint format"))
    m=Mind(budget=p["budget"],max_evidence=p["max_evidence"];seed)
    for item in p["memories"]
        memory=ActionMemory()
        memory.regime=Int(get(item,"regime",0))
        for e in item["evidence"]
            push!(memory.evidence,Experience(readfacts(e["before"]),readfacts(e["added"]),readfacts(e["removed"])))
        end
        length(memory.evidence)<=m.world.max_evidence || throw(ArgumentError("evidence capacity exceeded"))
        arity=Int(item["arity"])
        0<=arity<=32 || throw(ArgumentError("invalid command arity"))
        for e in memory.evidence, f in union(e.before,e.added,e.removed), t in f.terms
            startswith(t,"?") && tryparse(Int,t[2:end])!==nothing &&
                1<=parse(Int,t[2:end])<=arity || throw(ArgumentError("invalid learned variable"))
        end
        induce!(memory)
        m.world.actions[(String(item["name"]),arity)]=memory
    end
    m.world.observations=p["observations"]
    m.world.unsupported_effects=p["unsupported_effects"]
    m.world.regime_resets=Int(get(p,"regime_resets",0))
    m.surprises=p["surprises"];m.denied=p["denied"]
    m.visits=Dict{String,Int}(k=>Int(v) for (k,v) in p["visits"])
    m.trace=Dict{String,Any}[Dict{String,Any}(e) for e in p["trace"]]
    verify_trace(m.trace) || throw(ArgumentError("trace chain mismatch"))
    for item in get(p,"procedures",[])
        steps=[CommandPattern(String(s["name"]),Tuple(String.(s["args"]))) for s in item["steps"]]
        2<=length(steps)<=4 || throw(ArgumentError("invalid procedure length"))
        proc=Procedure(steps,Set(String.(item["bindings"])))
        m.procedures[procedurekey(proc)]=proc
    end
    m
end
