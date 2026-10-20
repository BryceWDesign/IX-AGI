"""An observed symbolic relation. The learner assigns no meaning to its name."""
struct Fact
    predicate::String
    terms::Tuple{Vararg{String}}
end
Fact(p::AbstractString, xs::AbstractString...) = Fact(String(p), Tuple(String.(xs)))
Base.:(==)(a::Fact,b::Fact) = a.predicate==b.predicate && a.terms==b.terms
Base.isequal(a::Fact,b::Fact) = a==b
Base.hash(f::Fact,h::UInt) = hash(f.terms,hash(f.predicate,h))
factkey(f::Fact) = (f.predicate, f.terms)

struct Command
    name::String
    args::Tuple{Vararg{String}}
    function Command(name::String,args::Tuple{Vararg{String}})
        isempty(name) && throw(ArgumentError("empty command name"))
        length(args)<=32 || throw(ArgumentError("command arity exceeds checkpoint format limit"))
        length(unique(args))==length(args) || throw(ArgumentError("aliased command arguments unsupported"))
        any(x->startswith(x,"?"),args) && throw(ArgumentError("? prefix reserved for learned variables"))
        new(name,args)
    end
end
Command(n::AbstractString,xs::AbstractString...) = Command(String(n),Tuple(String.(xs)))
Base.:(==)(a::Command,b::Command) = a.name==b.name && a.args==b.args
Base.isequal(a::Command,b::Command) = a==b
Base.hash(a::Command,h::UInt) = hash(a.args,hash(a.name,h))
commandkey(a::Command) = (a.name,a.args)
schema(a::Command) = (a.name,length(a.args))
const Situation = Set{Fact}

struct Goal
    present::Situation
    absent::Situation
    function Goal(p::Situation,a::Situation=Situation())
        isempty(intersect(p,a)) || throw(ArgumentError("contradictory goal"))
        new(copy(p),copy(a))
    end
end
Goal(fs::Fact...) = Goal(Situation(fs))
reached(g::Goal,s::Situation) = issubset(g.present,s) && isdisjoint(g.absent,s)
distance(g::Goal,s::Situation) = length(setdiff(g.present,s))+length(intersect(g.absent,s))
statekey(s::Situation) = Tuple(sort!(collect(s),by=factkey))

function lift(f::Fact,a::Command)
    terms=String[]
    for t in f.terms
        i=findfirst(==(t),a.args)
        i===nothing && return nothing
        push!(terms,"?"*string(i))
    end
    return Fact(f.predicate,Tuple(terms))
end
function ground(f::Fact,a::Command)
    Fact(f.predicate,Tuple(a.args[parse(Int,t[2:end])] for t in f.terms))
end
function localize(s::Situation,a::Command)
    out=Situation()
    for f in s
        t=lift(f,a)
        t===nothing || push!(out,t)
    end
    out
end

"""Transition evidence lifted by command arguments, without host success labels."""
struct Experience
    before::Situation
    added::Situation
    removed::Situation
end
effectkey(e::Experience) = (statekey(e.added),statekey(e.removed))
changed(e::Experience) = !isempty(e.added) || !isempty(e.removed)

struct Literal
    fact::Fact
    positive::Bool
end
holds(l::Literal,s::Situation) = (l.fact in s)==l.positive
literalkey(l::Literal) = (factkey(l.fact),l.positive)

"""A learned conditional transition, induced from positive AND no-effect evidence."""
struct Operator
    conditions::Vector{Literal}
    added::Situation
    removed::Situation
    support::Int
    separated::Bool
end

mutable struct ActionMemory
    evidence::Vector{Experience}
    operators::Vector{Operator}
    revision::Int
    regime::Int
    conflicts::Int
    contradictory_contexts::Set{Any}
    prediction_cache::Dict{Any,Union{Nothing,Operator}}
end
ActionMemory() = ActionMemory(Experience[],Operator[],0,0,0,Set{Any}(),Dict{Any,Union{Nothing,Operator}}())

"""Infer conjunctive preconditions by greedy minimum-description discrimination.
Effects are exact lifted differences, not supplied transition rules. If identical
local observations have incompatible outcomes, prediction abstains in that context.
"""
function induce!(m::ActionMemory)
    empty!(m.prediction_cache)
    empty!(m.contradictory_contexts)
    context_outcomes=Dict{Any,Any}()
    universe=Situation()
    for e in m.evidence
        union!(universe,e.before,e.added,e.removed)
        context=statekey(e.before)
        outcome=effectkey(e)
        if haskey(context_outcomes,context) && context_outcomes[context]!=outcome
            push!(m.contradictory_contexts,context)
        end
        context_outcomes[context]=outcome
    end
    groups=Dict{Any,Vector{Experience}}()
    for e in m.evidence
        changed(e) && push!(get!(groups,effectkey(e),Experience[]),e)
    end
    empty!(m.operators)
    m.conflicts=0
    for key in sort!(collect(keys(groups)),by=string)
        positives=groups[key]
        negatives=[e for e in m.evidence if effectkey(e)!=key]
        candidates=Literal[]
        for f in sort!(collect(universe),by=factkey), polarity in (true,false)
            l=Literal(f,polarity)
            all(e->holds(l,e.before),positives) && push!(candidates,l)
        end
        remaining=copy(negatives)
        selected=Literal[]
        while !isempty(remaining)
            scores=[count(e->!holds(l,e.before),remaining) for l in candidates]
            (isempty(scores) || maximum(scores)==0) && break
            i=argmax(scores)
            l=popat!(candidates,i)
            push!(selected,l)
            filter!(e->holds(l,e.before),remaining)
        end
        separated=isempty(remaining)
        m.conflicts+=length(remaining)
        exemplar=first(positives)
        push!(m.operators,Operator(selected,copy(exemplar.added),copy(exemplar.removed),
                                  length(positives),separated))
    end
    m.revision+=1
    m
end

mutable struct WorldMemory
    actions::Dict{Tuple{String,Int},ActionMemory}
    observations::Int
    unsupported_effects::Int
    regime_resets::Int
    max_evidence::Int
end
function WorldMemory(;max_evidence::Int=512)
    8<=max_evidence<=100_000 || throw(ArgumentError("invalid evidence capacity"))
    WorldMemory(Dict{Tuple{String,Int},ActionMemory}(),0,0,0,max_evidence)
end

function learn!(w::WorldMemory,before::Situation,a::Command,after::Situation)
    added=setdiff(after,before); removed=setdiff(before,after)
    # Never silently drop effects involving an object outside the command.
    if any(f->lift(f,a)===nothing,union(added,removed))
        w.unsupported_effects+=1
        return :unrepresentable
    end
    e=Experience(localize(before,a),localize(added,a),localize(removed,a))
    m=get!(w.actions,schema(a),ActionMemory())
    push!(m.evidence,e)
    # Three repeated contradictory outcomes trigger a new local dynamics regime.
    # This is an explicit heuristic for nonstationarity, not a proof of a change.
    same_context=[x for x in m.evidence if x.before==e.before]
    if length(same_context)>=4 &&
       any(x->effectkey(x)!=effectkey(e),same_context[1:end-3]) &&
       all(x->effectkey(x)==effectkey(e),same_context[end-2:end])
        # Reset only the contradicted observed context. Other command-local
        # contexts remain valuable knowledge and must not be discarded.
        unaffected=[x for x in m.evidence if x.before!=e.before]
        m.evidence=vcat(unaffected,same_context[end-2:end])
        m.regime+=1
        w.regime_resets+=1
    end
    length(m.evidence)>w.max_evidence && popfirst!(m.evidence)
    w.observations+=1
    induce!(m)
    :learned
end

"""Return a predicted state, or nothing for unknown, ambiguous, or unsupported dynamics."""
function imagine(w::WorldMemory,s::Situation,a::Command;min_support::Int=2)
    m=get(w.actions,schema(a),nothing)
    m===nothing && return nothing
    localstate=localize(s,a)
    # Conflicting outcomes at this exact context cannot be hidden by a rule fit.
    context=statekey(localstate)
    context in m.contradictory_contexts && return nothing
    o=get!(m.prediction_cache,(min_support,context)) do
        options=[o for o in m.operators if o.support>=min_support && o.separated &&
                 all(l->holds(l,localstate),o.conditions)]
        isempty(options) && return nothing
        firstoption=first(options)
        all(o->o.added==firstoption.added && o.removed==firstoption.removed,options) || return nothing
        firstoption
    end
    o===nothing && return nothing
    out=copy(s)
    setdiff!(out,Set(ground(f,a) for f in o.removed))
    union!(out,Set(ground(f,a) for f in o.added))
    out
end

struct PlanResult
    status::Symbol
    commands::Vector{Command}
    expansions::Int
end

"""General forward search over learned operators. No simulator callback is accepted."""
function plan(w::WorldMemory,s::Situation,actions::Vector{Command},g::Goal;
              max_expansions::Int=10_000,max_depth::Int=80,min_support::Int=2,
              procedures=nothing)
    max_expansions>0 && max_depth>0 || throw(ArgumentError("invalid planning budget"))
    reached(g,s) && return PlanResult(:satisfied,Command[],0)
    ordered=sort!(unique(actions),by=commandkey)
    frontier=[(copy(s),Command[],distance(g,s))]
    bestdepth=Dict{Any,Int}(statekey(s)=>0)
    expanded=0
    while !isempty(frontier) && expanded<max_expansions
        i=argmin([(length(x[2])+x[3],x[3],length(x[2])) for x in frontier])
        current,path,_=popat!(frontier,i)
        get(bestdepth,statekey(current),typemax(Int))<length(path) && continue
        expanded+=1
        length(path)>=max_depth && continue
        edges=Tuple{Situation,Vector{Command}}[]
        if procedures!==nothing
            append!(edges,procedure_edges(w,current,ordered,procedures;min_support))
        end
        for a in ordered
            next=imagine(w,current,a;min_support)
            (next===nothing || next==current) || push!(edges,(next,[a]))
        end
        for (next,segment) in edges
            newpath=vcat(path,segment)
            length(newpath)>max_depth && continue
            reached(g,next) && return PlanResult(:solved,newpath,expanded)
            key=statekey(next)
            length(newpath)>=get(bestdepth,key,typemax(Int)) && continue
            bestdepth[key]=length(newpath)
            push!(frontier,(next,newpath,distance(g,next)))
        end
    end
    PlanResult(isempty(frontier) ? :unknown : :budget_exhausted,Command[],expanded)
end
