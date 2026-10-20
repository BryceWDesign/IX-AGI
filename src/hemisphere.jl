"""An independent, environment-feedback-trained model of nonlocal, relational effects.

Unlike the BlackFox model (which deliberately rejects effects outside command args),
this predictor preserves relations involving external persistent objects and allows
command-argument role variables. External object names must remain stable. It learns from before/after observations, never simulator transition
rules, predicted answers, external pretrained weights, or action authorization.
"""
struct BoundedEvidence
    context::Tuple{Vararg{String}}
    added::Vector{BF.Fact}
    removed::Vector{BF.Fact}
    episode::Int
end
mutable struct CounterHemisphere
    memory::Dict{Tuple{String,Int},Vector{BoundedEvidence}}
    max_per_schema::Int
    observations::Int
    surprises::Int
    episodes::Int
end
function CounterHemisphere(;max_per_schema::Int=96)
    8<=max_per_schema<=10_000 || throw(ArgumentError("invalid evidence capacity"))
    CounterHemisphere(Dict{Tuple{String,Int},Vector{BoundedEvidence}}(),max_per_schema,0,0,0)
end

# Encoded internal symbols are not inter-agent messages; terms are argument-role indices.
function rolefact(f::BF.Fact, a::BF.Command)
    terms=String[]
    for t in f.terms
        ix=findfirst(==(t),a.args)
        push!(terms,ix===nothing ? ":"*t : "?"*string(ix))
    end
    BF.Fact(f.predicate,Tuple(terms))
end
function groundfact(f::BF.Fact,a::BF.Command)
    BF.Fact(f.predicate,Tuple(startswith(t,"?") ? a.args[parse(Int,t[2:end])] : t[2:end] for t in f.terms))
end
function scoped(s::BF.Situation,a::BF.Command)
    kept=BF.Fact[]
    for f in s
        mapped=rolefact(f,a)
        mapped===nothing || push!(kept,mapped)
    end
    sort!(kept,by=f->(f.predicate,f.terms))
    kept
end
function contextkey(s::BF.Situation,a::BF.Command)
    Tuple([string(f.predicate,"/",join(f.terms,",")) for f in scoped(s,a)])
end
function actionkey(a::BF.Command)
    (a.name,length(a.args))
end
function counter_learn!(h::CounterHemisphere,before::BF.Situation,a::BF.Command,after::BF.Situation)
    gained=BF.Fact[]; lost=BF.Fact[]
    for f in setdiff(after,before)
        mapped=rolefact(f,a)
        mapped===nothing || push!(gained,mapped)
    end
    for f in setdiff(before,after)
        mapped=rolefact(f,a)
        mapped===nothing || push!(lost,mapped)
    end
    sort!(gained,by=f->(f.predicate,f.terms))
    sort!(lost,by=f->(f.predicate,f.terms))
    h.episodes+=1
    bucket=get!(h.memory,actionkey(a),BoundedEvidence[])
    push!(bucket,BoundedEvidence(contextkey(before,a),gained,lost,h.episodes))
    length(bucket)>h.max_per_schema && popfirst!(bucket)
    h.observations+=1
    return :learned
end
struct Prediction
    state::BF.Situation
    confidence::Float64
    support::Int
    basis::Symbol
end

"""Abstain on sparse or contradictory evidence; prefer recent evidence on regime shift.

Bayesian posterior with 1-count smoothing is deliberately *not* a certainty claim.
No hidden-world lookahead or actions supplied as labels are used.
"""
function predict_counter(h::CounterHemisphere,s::BF.Situation,a::BF.Command;
                         min_support::Int=2,window::Int=12)
    evidence=get(h.memory,actionkey(a),BoundedEvidence[])
    key=contextkey(s,a)
    examples=[e for e in evidence if e.context==key]
    isempty(examples) && return nothing
    examples=last(examples,min(window,length(examples)))
    length(examples)>=min_support || return nothing
    counts=Dict{String,Int}()
    exemplar=Dict{String,BoundedEvidence}()
    for e in examples
        sig=join(vcat(["+"*f.predicate*"("*join(f.terms,",")*")" for f in e.added],
                       ["-"*f.predicate*"("*join(f.terms,",")*")" for f in e.removed]),"|")
        counts[sig]=get(counts,sig,0)+1
        exemplar[sig]=e
    end
    best=sort(collect(keys(counts)),by=x->(-counts[x],x))[1]
    leader=counts[best]
    # Two agreeing observations alone can predict with uncertainty, never certainty.
    confidence=(leader+1)/(length(examples)+2)
    leader >= min_support || return nothing
    e=exemplar[best]
    out=copy(s)
    for f in e.removed; delete!(out,groundfact(f,a)); end
    for f in e.added; push!(out,groundfact(f,a)); end
    Prediction(out,confidence,leader,:independent_counterfactual)
end

# Expose uncertainty as a scalar side-channel; the receiving selector never
# receives the peer's symbolic predicted state in coupled mode.
function confidence_signal(h::CounterHemisphere,s::BF.Situation,a::BF.Command)
    p=predict_counter(h,s,a)
    p===nothing ? 0.0 : p.confidence
end

"""Compact numerical state encoding, not a text-based or conversational channel.

A fixed SHA-256 projection makes feature assignments deterministic across runs and
isolates the learner's representations from environment names used by its peer.
The channel never includes transitions, authorization tokens or held-out targets.
"""
function stablechannel(x::AbstractString,width::Int)
    d=sha256(codeunits(x))
    pos=1 + mod((Int(d[1])<<8)+Int(d[2]),width)
    polarity=isodd(Int(d[3])) ? 1.0 : -1.0
    pos,polarity
end
function encode_state(s::BF.Situation,a::BF.Command,width::Int)
    z=zeros(Float64,width)
    for token in contextkey(s,a)
        pos,polarity=stablechannel(token,width)
        z[pos]+=polarity
    end
    n=norm2(z)
    n>0 && (z ./= n)
    z
end
norm2(x::Vector{Float64})=sqrt(sum(abs2,x))
