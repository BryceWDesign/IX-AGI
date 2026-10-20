struct Skill
    program::Node
    fit_correct::Int
    fit_total::Int
    select_correct::Int
    select_total::Int
    veto_correct::Int
    veto_total::Int
end

struct DevelopmentReport
    task::Symbol
    status::Symbol
    reason::String
    strategy::Symbol
    candidates::Int
    fit_accuracy::Float64
    select_accuracy::Float64
    veto_accuracy::Float64
end

mutable struct Agent
    skills::Dict{Symbol,Skill}
    quarantined::Set{Symbol}
    disagreement::Dict{Symbol,Int}
    reports::Vector{DevelopmentReport}
    budget::Int
    allow_composition::Bool
    beam::Int
end

function Agent(; budget=60, allow_composition=true, beam=20)
    0 <= budget <= 1_000_000 || throw(ArgumentError("invalid budget"))
    4 <= beam <= 64 || throw(ArgumentError("invalid beam"))
    return Agent(Dict{Symbol,Skill}(),Set{Symbol}(),Dict{Symbol,Int}(),
                 DevelopmentReport[],budget,allow_composition,beam)
end

function report!(a::Agent, t::Task, status::Symbol, reason::String,
                 strategy::Symbol, count::Int, fc::Float64=0.,
                 sc::Float64=0., vc::Float64=0.)
    r = DevelopmentReport(t.id,status,reason,strategy,count,fc,sc,vc)
    push!(a.reports,r)
    return r
end

"""Develop a program with independent selection and veto splits.
    Deliberately NEVER reads data.blind, including for tie-breaking.
"""
function evolve!(a::Agent, t::Task, data::Dataset; permission::Integer=1,
                 risk::Integer=0)
    # A caller may request exploration; only the Ada authority may grant it.
    if authorize(1; permission=permission,risk=risk,cost=1,budget=a.budget) != 1
        return report!(a,t,:denied,"Ada authority denied exploration",:none,0)
    end
    a.budget -= 1
    # Constant-one is a declared non-learning baseline, not a new capability.
    if accuracy(Atom(:one),data.fit) == length(data.fit) &&
       accuracy(Atom(:one),data.select) == length(data.select)
        return report!(a,t,:no_change,"constant baseline already solves the task",:baseline,0)
    end
    existing = get(a.skills,t.id,nothing)
    if existing !== nothing && !(t.id in a.quarantined)
        if accuracy(existing.program,data.select)==length(data.select) &&
           accuracy(existing.program,data.veto)==length(data.veto)
            return report!(a,t,:no_change,"retained skill already passes independent evidence",:reuse,0)
        end
    end

    best_program = nothing
    best_scores = (-1,-1,-1)
    candidates_seen=0
    chosen_strategy=:atomic
    # Self-revision is staged: expand the representation search if atomic search fails.
    for strategy in (a.allow_composition ? (:atomic,:composed) : (:atomic,))
        options=synthesize(data.fit;compose=strategy==:composed,beam=a.beam)
        # Reuse previously learned skills as candidate stepping stones.
        append!(options,[s.program for (id,s) in a.skills if !(id in a.quarantined)])
        candidates_seen += length(options)
        for p in options
            f=accuracy(p,data.fit)
            # Strict FIT screen limits selection-set overfitting.
            f * 100 >= 98 * length(data.fit) || continue
            v=accuracy(p,data.select)
            v * 100 >= 98 * length(data.select) || continue
            key=(v,f,-program_size(p))
            if key > best_scores
                best_program=p;best_scores=key;chosen_strategy=strategy
            end
        end
        best_program !== nothing && break
    end
    best_program === nothing && return report!(a,t,:unsupported,
       "no candidate passed disjoint fit and selection thresholds",:none,candidates_seen)

    p=best_program::Node
    fc=accuracy(p,data.fit); sc=accuracy(p,data.select)
    vc=accuracy(p,data.veto)
    fra=fc/length(data.fit); sra=sc/length(data.select); vra=vc/length(data.veto)
    if vc * 100 < 98 * length(data.veto)
        return report!(a,t,:vetoed,"independent veto evidence rejected promotion",
                       chosen_strategy,candidates_seen,fra,sra,vra)
    end
    # The Ada authority receives bounded evidence counts. Not a cryptographic
    # attestation: the host is responsible for evidence provenance.
    total = length(data.select)+length(data.veto)
    correct = sc+vc
    if authorize(2; permission=permission,risk=risk,cost=1,budget=a.budget,
                 samples=total, correct=correct,cross_check=vc) != 2
        return report!(a,t,:denied,"Ada authority denied skill promotion",
                       chosen_strategy,candidates_seen,fra,sra,vra)
    end
    a.budget -= 1
    a.skills[t.id] = Skill(p,fc,length(data.fit),sc,length(data.select),vc,length(data.veto))
    delete!(a.quarantined,t.id)
    delete!(a.disagreement,t.id)
    return report!(a,t,:promoted,"program passed independent veto and authority",
                   chosen_strategy,candidates_seen,fra,sra,vra)
end

"""No action is issued: a prediction is a proposal, not permission to execute."""
function predict(a::Agent,id::Symbol,o::Observation)
    if !haskey(a.skills,id) || id in a.quarantined
        return nothing # HOLD / INVESTIGATE
    end
    return evaluate(a.skills[id].program,o) != 0
end

"""Explicit consequences can quarantine a previously supported structure."""
function observe!(a::Agent,id::Symbol,o::Observation,actual::Bool)
    previous=predict(a,id,o)
    previous === nothing && return :unknown
    if previous != actual
        a.disagreement[id]=get(a.disagreement,id,0)+1
        if a.disagreement[id]>=2
            push!(a.quarantined,id)
            return :quarantined
        end
        return :contradiction
    end
    a.disagreement[id]=0
    return :confirmed
end

"""Test a capability on the fully untouched fourth partition; never invoked in evolve!."""
function blind_score(a::Agent,id::Symbol,d::Dataset)
    return count(item -> predict(a,id,item[1]) === item[2], d.blind),length(d.blind)
end

"""Generate the next task proposal. Bounded known-world families, not open-ended world creation."""
function proposed_challenge(t::Task,iteration::Int)
    iteration>=0 || throw(ArgumentError("negative iteration"))
    if t.rule==:greater
        return Task(Symbol(string(t.id,"_composed_",iteration)),:composed,0)
    elseif t.rule==:composed
        return Task(Symbol(string(t.id,"_shifted_",iteration)),:greater,1+mod(iteration,2))
    elseif t.rule==:parity
        return Task(Symbol(string(t.id,"_unstructured_",iteration)),:unstructured,iteration)
    else
        return Task(Symbol(string(t.id,"_parity_",iteration)),:parity,0)
    end
end

function curriculum!(a::Agent,initial::Task; seed::Integer=11, rounds::Int=3)
    1<=rounds<=12 || throw(ArgumentError("bounded curriculum requires 1..12 rounds"))
    task=initial
    summaries=DevelopmentReport[]
    for i in 1:rounds
        d=make_dataset(task,seed+i)
        push!(summaries,evolve!(a,task,d))
        task=proposed_challenge(task,i)
    end
    return summaries
end
