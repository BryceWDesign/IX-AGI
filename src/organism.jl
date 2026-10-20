"""A single functioning dual-cognition organism operating on the BlackFox Environment ABI.

The original BlackFox acts through Ada's native guard. Neither hemisphere can call
transition! directly from this runtime; all external effects go through BF.act!.
"""
struct Decision
    mode::Symbol
    action::Union{Nothing,BF.Command}
    reason::Symbol
    predicted::Union{Nothing,BF.Situation}
    confidence::Float64
end
mutable struct DualOrganism
    left::BF.Mind
    right::CounterHemisphere
    channel::NeuralCallosum
    late_fusion::Bool
    modes::Vector{Dict{String,Any}}
    left_correct::Int
    right_correct::Int
    left_count::Int
    right_count::Int
    step_count::Int
end
function DualOrganism(;seed::Int=1,width::Int=32,budget::Int=100_000,
                       mode::Symbol=:coupled)
    mode in (:coupled,:lesioned,:late_fusion) || throw(ArgumentError("invalid dual-mode"))
    DualOrganism(BF.Mind(;seed,budget),CounterHemisphere(),
        NeuralCallosum(;seed,width,lesions=(mode!=:coupled)),mode==:late_fusion,
        Dict{String,Any}[],0,0,0,0,0)
end
function numerical_activity(h::DualOrganism,s::BF.Situation,a::BF.Command)
    # Structural learner: only action-local predicates; counterfactual learner:
    # all perceptible relations, including object-external effects.
    localstate=BF.localize(s,a)
    lv=encode_state(localstate,a,h.channel.width)
    rv=encode_state(s,a,h.channel.width)
    left=BF.imagine(h.left.world,s,a)
    right=predict_counter(h.right,s,a)
    if left!==nothing
        lv .+= 0.20.*encode_state(left,a,h.channel.width)
    end
    # Right emits a signed *change-in-state representation*, not a copy of its
    # predicted future symbolic state or a textual recommendation.
    if right!==nothing
        rv=encode_state(right.state,a,h.channel.width).-encode_state(s,a,h.channel.width)
    else
        rv=zeros(Float64,h.channel.width)
    end
    lv=bounded(lv);rv=bounded(rv)
    ul=left===nothing ? 1.0 : 0.2
    ur=right===nothing ? 1.0 : 1.0-right.confidence
    lv,rv,ul,ur
end
function inspect!(h::DualOrganism,s::BF.Situation,a::BF.Command)
    lv,rv,ul,ur=numerical_activity(h,s,a)
    signal!(h.channel,lv,rv;uncertainty_l=ul,uncertainty_r=ur)
end
function state_distance(g::BF.Goal,s::BF.Situation)
    length(setdiff(g.present,s))+length(intersect(g.absent,s))
end
function choose!(h::DualOrganism,env::BF.Environment,g::BF.Goal;
                 allow_explore::Bool=false)
    s=BF.perceive(env)
    BF.reached(g,s) && return Decision(:hold,nothing,:goal_reached,s,1.0)
    actions=sort!(unique(BF.commands(env)),by=a->(a.name,a.args))
    isempty(actions) && return Decision(:hold,nothing,:no_actions,nothing,0.0)
    p=BF.plan(h.left.world,s,actions,g;max_expansions=2000)
    if p.status==:solved && !isempty(p.commands)
        a=first(p.commands)
        inspect!(h,s,a)
        return Decision(:act,a,:structural_plan,BF.imagine(h.left.world,s,a),1.0)
    end
    # Right-side symbolic predictions stay inside the right subsystem.
    # In the coupled mode the left selector receives *only projected numerical
    # state-change activity*, matched against an independently supplied goal.
    # A late-fusion comparator intentionally bypasses this interface so that
    # its necessity, rather than its presence, can be measured.
    options=Tuple{Float64,BF.Command,Symbol,Float64}[]
    for a in actions
        if h.late_fusion
            pred=predict_counter(h.right,s,a)
            pred===nothing && continue
            score=Float64(state_distance(g,s)-state_distance(g,pred.state))
            score>0 || continue
            pred.confidence>=0.70 || continue
            push!(options,(score,a,:late_fusion_prediction,pred.confidence))
            continue
        end
        # Two clock ticks: local encoding, then delivery through a *delayed*
        # numerical pathway. No direct read of the right prediction's state.
        inspect!(h,s,a)
        inspect!(h,s,a)
        signal_left=h.channel.last_received_left
        !h.channel.lesions || continue
        # Activity from the right subsystem encodes an estimated state delta;
        # the left subsystem projects its goal into the same bounded channel.
        desired=encode_state(g.present,a,h.channel.width)
        avoid=encode_state(g.absent,a,h.channel.width)
        alignment=sum(desired.*signal_left)-sum(avoid.*signal_left)
        # Independent confidence is a bounded modulation signal, not a future
        # state and not an authorization token.
        confidence=confidence_signal(h.right,s,a)
        evidence=alignment*confidence*clamp(h.channel.gain_rl,0.05,1.25)
        if evidence>0.08 && confidence>=0.70 && h.channel.tick>=2
            push!(options,(evidence,a,:callosal_delta_alignment,confidence))
        end
    end
    if !isempty(options)
        sort!(options,by=x->(-x[1],x[2].name,x[2].args))
        quality,a,reason,confidence=first(options)
        # Coupled mode never passes the peer's symbolic predicted next state.
        return Decision(:act,a,reason,nothing,confidence)
    end
    if allow_explore
        a=BF.investigate(h.left,s,actions)
        a===nothing && return Decision(:hold,nothing,:no_experiment,nothing,0.0)
        inspect!(h,s,a)
        return Decision(:investigate,a,:uncertain_effect,nothing,0.0)
    end
    Decision(:hold,nothing,:no_evidence,nothing,0.0)
end
function addlog!(h::DualOrganism,event::Dict{String,Any})
    event["sequence"]=length(h.modes)+1
    push!(h.modes,event)
end
function step!(h::DualOrganism,env::BF.Environment,decision::Decision;
               permission::Int=1,risk::Int=0,learning::Bool=true)
    h.step_count+=1
    if decision.action===nothing || decision.mode==:hold
        addlog!(h,Dict{String,Any}("mode"=>"hold","reason"=>string(decision.reason),
                                "result"=>"held","tick"=>h.channel.tick))
        return :held
    end
    a=decision.action::BF.Command
    before=BF.perceive(env)
    lp=BF.imagine(h.left.world,before,a)
    rp=predict_counter(h.right,before,a)
    # Actual environment execution is ONLY possible inside BlackFox's act!,
    # which invokes native Ada before adapter dispatch and fails closed.
    result=BF.act!(h.left,env,a;permission,risk,learning,
                   cognitive_mode="dual_"*string(decision.mode),
                   cognitive_reason=string(decision.reason))
    after=BF.perceive(env)
    if result in (:denied,:invalid_command)
        after==before || error("SECURITY INVARIANT: denied action changed state")
        addlog!(h,Dict{String,Any}("mode"=>string(decision.mode),"reason"=>string(decision.reason),
                      "result"=>string(result),"tick"=>h.channel.tick))
        return result
    end
    if learning
        counter_learn!(h.right,before,a,after)
        le=lp===nothing ? 0.5 : (lp==after ? 0.0 : 1.0)
        re=rp===nothing ? 0.5 : (rp.state==after ? 0.0 : 1.0)
        if lp!==nothing
            h.left_count+=1;h.left_correct+=Int(le==0.0)
        end
        if rp!==nothing
            h.right_count+=1;h.right_correct+=Int(re==0.0)
            h.right.surprises+=Int(re==1.0)
        end
        adjust!(h.channel;left_error=le,right_error=re)
    end
    addlog!(h,Dict{String,Any}("mode"=>string(decision.mode),"reason"=>string(decision.reason),
         "result"=>string(result),"tick"=>h.channel.tick,
         "left_predicted"=>lp!==nothing,"right_predicted"=>rp!==nothing,
         "left_correct"=>(lp!==nothing && lp==after),
         "right_correct"=>(rp!==nothing && rp.state==after)))
    result
end
function live!(h::DualOrganism,env::BF.Environment,g::BF.Goal;
               max_steps::Int=24,allow_explore::Bool=true,permission::Int=1)
    0<=max_steps<=100_000 || throw(ArgumentError("invalid maximum steps"))
    for _ in 1:max_steps
        BF.reached(g,BF.perceive(env)) && return :achieved
        d=choose!(h,env,g;allow_explore)
        d.mode==:hold && return :held
        s=step!(h,env,d;permission)
        s in (:denied,:invalid_command) && return s
    end
    BF.reached(g,BF.perceive(env)) ? :achieved : :step_limit
end
function decision_log(h::DualOrganism)
    copy(h.modes)
end
function self_check(h::DualOrganism)
    BF.verify_trace(h.left.trace) &&
    all(x->isfinite(x) && x>=0,(h.channel.gain_lr,h.channel.gain_rl)) &&
    h.left_correct<=h.left_count && h.right_correct<=h.right_count &&
    all(e->Int(e["sequence"])>=1,h.modes)
end
