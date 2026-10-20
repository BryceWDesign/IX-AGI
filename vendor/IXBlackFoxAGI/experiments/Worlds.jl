module Worlds
using Random
using IXBlackFoxAGI
import IXBlackFoxAGI: perceive, commands, transition!

"""Host-only simulator. Rules are never passed to the learner or planner."""
mutable struct Courier <: Environment
    state::Situation
    locations::Vector{String}
    parcels::Vector{String}
    verbs::NTuple{3,String}
    permitted::Vector{Command}
end
function Courier(seed::Int;nlocations::Int=3,nparcels::Int=1,prefix::String="r",
                 verbs::NTuple{3,String}=("v17","v41","v93"),disconnected::Bool=false)
    rng=MersenneTwister(seed)
    locations=[prefix*"_"*string(x) for x in randperm(rng,1000)[1:nlocations]]
    parcels=[prefix*"_parcel_"*string(x) for x in randperm(rng,1000)[1:nparcels]]
    state=Situation([Fact("at",rand(rng,locations)),Fact("free")])
    for (i,x) in enumerate(locations), (j,y) in enumerate(locations)
        i==j && continue
        # A connected ring, with independently sampled extra directed edges.
        if !disconnected && (j==mod1(i+1,nlocations) || rand(rng)<0.25)
            push!(state,Fact("linked",x,y))
        end
    end
    for parcel in parcels
        push!(state,Fact("parcel_at",parcel,rand(rng,locations)))
    end
    # Distractors change between worlds and do not imply effects.
    for x in locations
        rand(rng,Bool) && push!(state,Fact("marked",x))
    end
    allowed=vcat([Command(verbs[1],x,y) for x in locations for y in locations if x!=y],
                 [Command(v,p,x) for v in verbs[2:3] for p in parcels for x in locations])
    Courier(state,locations,parcels,verbs,allowed)
end
perceive(e::Courier)=copy(e.state)
commands(e::Courier)=copy(e.permitted)
function transition!(e::Courier,a::Command)
    a in e.permitted || throw(ArgumentError("unknown syntactic command"))
    if a.name==e.verbs[1]
        x,y=a.args
        if Fact("at",x) in e.state && Fact("linked",x,y) in e.state
            delete!(e.state,Fact("at",x));push!(e.state,Fact("at",y))
        end
    elseif a.name==e.verbs[2]
        p,x=a.args
        if Fact("at",x) in e.state && Fact("parcel_at",p,x) in e.state && Fact("free") in e.state
            delete!(e.state,Fact("parcel_at",p,x));delete!(e.state,Fact("free"))
            push!(e.state,Fact("carrying",p))
        end
    elseif a.name==e.verbs[3]
        p,x=a.args
        if Fact("at",x) in e.state && Fact("carrying",p) in e.state
            delete!(e.state,Fact("carrying",p));push!(e.state,Fact("free"))
            push!(e.state,Fact("parcel_at",p,x))
        end
    end
    nothing
end
function courier_goal(e::Courier)
    Goal(Situation(Fact("parcel_at",p,last(e.locations)) for p in e.parcels))
end

mutable struct Switchboard <: Environment
    state::Situation
    switches::Vector{String}
    verb::String
end
function Switchboard(seed::Int;n::Int=3,prefix::String="s",verb::String="q72")
    rng=MersenneTwister(seed)
    switches=[prefix*string(x) for x in randperm(rng,1000)[1:n]]
    state=Situation(Fact("active",x) for x in switches if rand(rng,Bool))
    union!(state,Situation(Fact("tagged",x) for x in switches if rand(rng,Bool)))
    Switchboard(state,switches,verb)
end
perceive(e::Switchboard)=copy(e.state)
commands(e::Switchboard)=[Command(e.verb,x) for x in e.switches]
function transition!(e::Switchboard,a::Command)
    a in commands(e) || throw(ArgumentError("unknown syntactic command"))
    f=Fact("active",only(a.args))
    f in e.state ? delete!(e.state,f) : push!(e.state,f)
    nothing
end
function switch_goal(e::Switchboard)
    Goal(Situation(Fact("active",x) for (i,x) in enumerate(e.switches) if isodd(i)),
         Situation(Fact("active",x) for (i,x) in enumerate(e.switches) if iseven(i)))
end

mutable struct Workshop <: Environment
    state::Situation
    objects::Vector{String}
    verbs::NTuple{3,String}
end
function Workshop(seed::Int;n::Int=2,prefix::String="j",verbs::NTuple{3,String}=("a31","a58","a89"))
    rng=MersenneTwister(seed)
    objects=[prefix*string(x) for x in randperm(rng,1000)[1:n]]
    stages=("raw","shaped","joined","finished")
    state=Situation(Fact(rand(rng,stages),x) for x in objects)
    for x in objects
        rand(rng,Bool) && push!(state,Fact("colored",x))
    end
    Workshop(state,objects,verbs)
end
perceive(e::Workshop)=copy(e.state)
commands(e::Workshop)=[Command(v,x) for v in e.verbs for x in e.objects]
function transition!(e::Workshop,a::Command)
    a in commands(e) || throw(ArgumentError("unknown syntactic command"))
    i=findfirst(==(a.name),e.verbs)
    stages=("raw","shaped","joined","finished")
    f=Fact(stages[i],only(a.args))
    if f in e.state
        delete!(e.state,f);push!(e.state,Fact(stages[i+1],only(a.args)))
    end
    nothing
end
workshop_goal(e::Workshop)=Goal(Situation(Fact("finished",x) for x in e.objects))

"""A fourth adapter composes two mechanisms; no composite training worlds are used."""
struct Combined <: Environment
    courier::Courier
    workshop::Workshop
end
perceive(e::Combined)=union(perceive(e.courier),perceive(e.workshop))
commands(e::Combined)=vcat(commands(e.courier),commands(e.workshop))
function transition!(e::Combined,a::Command)
    if a in commands(e.courier)
        transition!(e.courier,a)
    else
        transition!(e.workshop,a)
    end
    nothing
end
combined_goal(e::Combined)=Goal(union(courier_goal(e.courier).present,workshop_goal(e.workshop).present))

"""Only the host test harness can reset simulations. The learner cannot reset a real adapter."""
function train!(m::Mind;seed::Int=1,courier_episodes::Int=30,steps::Int=50)
    for i in 1:courier_episodes
        explore!(m,Courier(seed*1000+i;prefix="train"*string(i));steps)
    end
    for i in 1:12
        explore!(m,Switchboard(seed*2000+i;prefix="switchtrain"*string(i));steps=20)
        explore!(m,Workshop(seed*3000+i;prefix="jobtrain"*string(i));steps=20)
    end
    m
end

mutable struct Blocks <: Environment
    state::Situation
    objects::Vector{String}
    verbs::NTuple{4,String}
end
function Blocks(seed::Int;n::Int=3,prefix::String="block",
                verbs::NTuple{4,String}=("b12","b34","b56","b78"))
    rng=MersenneTwister(seed)
    objects=[prefix*string(x) for x in randperm(rng,1000)[1:n]]
    state=Situation([Fact("handfree")])
    for x in objects
        push!(state,Fact("ontable",x));push!(state,Fact("clear",x))
    end
    Blocks(state,objects,verbs)
end
perceive(e::Blocks)=copy(e.state)
commands(e::Blocks)=vcat([Command(v,x) for v in e.verbs[1:2] for x in e.objects],
    [Command(v,x,y) for v in e.verbs[3:4] for x in e.objects for y in e.objects if x!=y])
function transition!(e::Blocks,a::Command)
    a in commands(e) || throw(ArgumentError("unknown syntactic command"))
    x=first(a.args)
    if a.name==e.verbs[1]
        if all(f->f in e.state,(Fact("ontable",x),Fact("clear",x),Fact("handfree")))
            setdiff!(e.state,Situation([Fact("ontable",x),Fact("clear",x),Fact("handfree")]))
            push!(e.state,Fact("holding",x))
        end
    elseif a.name==e.verbs[2]
        if Fact("holding",x) in e.state
            delete!(e.state,Fact("holding",x))
            union!(e.state,Situation([Fact("ontable",x),Fact("clear",x),Fact("handfree")]))
        end
    elseif a.name==e.verbs[3]
        y=last(a.args)
        if Fact("holding",x) in e.state && Fact("clear",y) in e.state
            setdiff!(e.state,Situation([Fact("holding",x),Fact("clear",y)]))
            union!(e.state,Situation([Fact("on",x,y),Fact("clear",x),Fact("handfree")]))
        end
    elseif a.name==e.verbs[4]
        y=last(a.args)
        if all(f->f in e.state,(Fact("on",x,y),Fact("clear",x),Fact("handfree")))
            setdiff!(e.state,Situation([Fact("on",x,y),Fact("clear",x),Fact("handfree")]))
            union!(e.state,Situation([Fact("holding",x),Fact("clear",y)]))
        end
    end
    nothing
end
function blocks_goal(e::Blocks)
    Goal(Situation(vcat([Fact("on",e.objects[i],e.objects[i+1]) for i in 1:length(e.objects)-1],
                         [Fact("handfree")])))
end

"""Host-side vocabulary randomization tests whether core algorithms depend on names."""
struct Renamed{T<:Environment} <: Environment
    inner::T
    predicates::Dict{String,String}
    verbs::Dict{String,String}
end
function Renamed(e::T,seed::Int) where T<:Environment
    rng=MersenneTwister(seed)
    names=sort!(unique([f.predicate for f in perceive(e)]))
    # Include currently absent relation names from this host adapter's vocabulary.
    append!(names,["holding","on","ontable","clear","handfree"])
    unique!(names)
    predicates=Dict(x=>"opaque_relation_"*string(v) for (x,v) in zip(names,randperm(rng,10_000)))
    verbs=Dict(x=>"opaque_action_"*string(v) for (x,v) in zip(sort!(unique(a.name for a in commands(e))),randperm(rng,10_000)))
    Renamed{T}(e,predicates,verbs)
end
renamefact(e::Renamed,f::Fact)=Fact(e.predicates[f.predicate],f.terms)
perceive(e::Renamed)=Situation(renamefact(e,f) for f in perceive(e.inner))
commands(e::Renamed)=[Command(e.verbs[a.name],a.args) for a in commands(e.inner)]
function transition!(e::Renamed,a::Command)
    original=only(k for (k,v) in e.verbs if v==a.name)
    transition!(e.inner,Command(original,a.args))
end
renamegoal(e::Renamed,g::Goal)=Goal(Situation(renamefact(e,f) for f in g.present),
                                    Situation(renamefact(e,f) for f in g.absent))

end
