"""A bounded, evidence-generated cognitive objective (not an autonomous mission)."""
struct Inquiry
    action::Tuple{String,Int}
    reason::Symbol
    priority::Float64
    evidence::Int
    errors::Int
end

"""Derive inquiry priorities from measured prediction failures, coverage and
observed contradictory action contexts; never infer unobserved correctness.
"""
function propose_inquiries(m::Mind;min_observations::Int=1)
    min_observations>=0 || throw(ArgumentError("invalid inquiry threshold"))
    requests=Inquiry[]
    for ((name,arity),memory) in sort!(collect(m.world.actions),by=first)
        a=Command(name,Tuple("inquiry_"*string(i) for i in 1:arity))
        p=prediction_profile(m,a)
        p.observations>=min_observations || continue
        conflicted=length(memory.contradictory_contexts)
        if conflicted>0
            priority=4.0+min(4,conflicted)+p.surprises/max(1,p.predicted)
            reason=:contradictory_context
        elseif p.predicted>=3 && p.wilson_lower<0.5
            priority=2.0+2.0*(1.0-p.wilson_lower)
            reason=:prediction_failure
        elseif p.coverage<0.50
            priority=1.0+(1.0-p.coverage)
            reason=:unmodelled_outcomes
        else
            continue
        end
        push!(requests,Inquiry((name,arity),reason,priority,p.observations,p.surprises))
    end
    sort!(requests,by=i->(-i.priority,i.action))
    requests
end

"""Execute one bounded self-generated knowledge-acquisition session.

The system chooses diagnostic commands using trace-derived inquiries; native
Ada authorization remains mandatory for *every* external adapter dispatch.
Only commands already exposed by the host are possible. The return value
counts attempted permitted transitions, not achievement of general intelligence.
"""
function inquire!(m::Mind,env::Environment;steps::Int=10,
                  permission::Int=1,risk::Int=0)
    steps>=0 || throw(ArgumentError("negative inquiry budget"))
    completed=0
    for _ in 1:steps
        m.budget>0 || break
        s=perceive(env)
        available=commands(env)
        isempty(available) && break
        objectives=propose_inquiries(m)
        weights=Dict(x.action=>(x.priority,x.reason) for x in objectives)
        # The first component comes from real discrepancies; the second
        # prioritizes under-sampled contexts. No simulator lookahead is used.
        ordered=sort!(unique(available),by=commandkey)
        candidates=Tuple{Float64,Command,Symbol}[]
        for a in ordered
            priority,reason=get(weights,schema(a),(0.0,:novel_experiment))
            local_visits=get(m.visits,visitkey(s,a),0)
            value=priority+0.5/sqrt(1+local_visits)
            push!(candidates,(value,a,reason))
        end
        sort!(candidates,by=x->(-x[1],commandkey(x[2])))
        _,a,reason=first(candidates)
        status=act!(m,env,a;permission,risk,cognitive_mode="self_inquiry",
                    cognitive_reason=string(reason))
        status in (:denied,:invalid_command) && break
        completed+=1
    end
    completed
end
