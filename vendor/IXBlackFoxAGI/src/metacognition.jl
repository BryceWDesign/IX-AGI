"""Empirical confidence and runtime choice of planning versus diagnosis.

The statistics are calculated from the append-only executed action trace.
Coverage explicitly excludes abstentions and is not a population accuracy claim.
"""
struct PredictionProfile
    action::Tuple{String,Int}
    observations::Int
    predicted::Int
    correct::Int
    surprises::Int
    coverage::Float64
    accuracy::Union{Nothing,Float64}
    wilson_lower::Float64
end

function prediction_profile(m::Mind,a::Command;window::Int=64)
    window>=1 || throw(ArgumentError("window must be positive"))
    history=Dict{String,Any}[]
    for event in Iterators.reverse(m.trace)
        get(event,"kind","")=="transition" || continue
        get(event,"command","")==a.name && length(get(event,"args",[]))==length(a.args) || continue
        push!(history,event)
        length(history)>=window && break
    end
    n=length(history)
    predicted=[e for e in history if get(e,"predicted",false)!==false]
    k=length(predicted)
    correct=count(e->!Bool(e["surprise"]),predicted)
    # Lower edge of a two-sided 95% Wilson interval;
    # n=0 returns zero instead of spuriously high certainty.
    lower=0.0
    if k>0
        p=correct/k
        z=1.96
        lower=max(0.0,(p+z*z/(2*k)-z*sqrt(p*(1-p)/k+z*z/(4*k*k)))/(1+z*z/k))
    end
    PredictionProfile(schema(a),n,k,correct,k-correct,n==0 ? 0.0 : k/n,
                      k==0 ? nothing : correct/k,lower)
end

"""Select a cognitive operation, returning a reason that is inspectable.
The planner's result is never overwritten. When prediction failures persist,
the runtime can elect a new diagnostic action instead of trusting a plan.
"""
function cognitive_choice(m::Mind,s::Situation,actions::Vector{Command},g::Goal,
                          proposed::PlanResult;min_predictions::Int=8,
                          min_wilson::Float64=0.50,window::Int=64)
    min_predictions>=1 && 0<=min_wilson<=1 || throw(ArgumentError("invalid metacognitive policy"))
    if proposed.status==:solved && !isempty(proposed.commands)
        candidate=first(proposed.commands)
        profile=prediction_profile(m,candidate;window)
        if profile.predicted>=min_predictions && profile.wilson_lower<min_wilson
            diagnostic=investigate(m,s,actions;goal=g,
                                   concept_library=synthesize_concepts(m.world))
            return (mode=:diagnose,command=diagnostic,
                    reason=:measured_prediction_unreliability,profile=profile)
        end
        return (mode=:plan,command=candidate,reason=:supported_or_insufficient_data,
                profile=profile)
    end
    candidate=investigate(m,s,actions;goal=g,
                          concept_library=synthesize_concepts(m.world))
    (mode=:explore,command=candidate,reason=:no_supported_plan,profile=nothing)
end

"""Summary of grounded cognitive coverage, not an intelligence score."""
function cognitive_report(m::Mind)
    schema_actions=sort!(collect(keys(m.world.actions)))
    profiles=Dict{String,Any}[]
    for (name,arity) in schema_actions
        a=Command(name,Tuple("sample_"*string(i) for i in 1:arity))
        p=prediction_profile(m,a)
        push!(profiles,Dict("action"=>name,"arity"=>arity,
            "observations"=>p.observations,"predicted"=>p.predicted,
            "correct"=>p.correct,"coverage"=>p.coverage,
            "accuracy"=>p.accuracy===nothing ? "unmeasured" : p.accuracy,
            "wilson_lower"=>p.wilson_lower))
    end
    Dict("observations"=>m.world.observations,
         "unsupported_effects"=>m.world.unsupported_effects,
         "regime_resets"=>m.world.regime_resets,
         "procedures"=>length(m.procedures),
         "derived_concepts"=>length(synthesize_concepts(m.world)),
         "schema_profiles"=>profiles)
end
