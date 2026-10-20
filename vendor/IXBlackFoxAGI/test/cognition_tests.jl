using Test
using IXBlackFoxAGI

# These experiments use a different synthetic rule construction from Worlds.jl.
# The core never receives the target rule, only before/after observations.
function binary_concept_world(;parity::Bool=false)
    w=WorldMemory()
    a=Command("undocumented","source")
    for bits in 0:63
        before=Situation(Fact("signal_"*string(i),"source") for i in 1:6 if !iszero(bits & (1<<(i-1))))
        gate=parity ? isodd(count_ones(bits)) : (bits & 3)==3
        after=copy(before)
        gate && push!(after,Fact("outcome","source"))
        @test learn!(w,before,a,after)==:learned
    end
    w
end

@testset "Invented relational concepts are holdout-validated and object invariant" begin
    world=binary_concept_world()
    derived=synthesize_concepts(world)
    @test !isempty(derived)
    @test all(c->c.fit_support>=4 && c.holdout_support>=3,derived)
    @test all(c->c.holdout_precision>=0.80,derived)
    unseen=Command("undocumented","unseen_entity")
    yes=Situation([Fact("signal_1","unseen_entity"),Fact("signal_2","unseen_entity")])
    no=Situation([Fact("signal_1","unseen_entity")])
    @test any(c->concept_holds(c,yes,unseen) && !concept_holds(c,no,unseen),derived)
    @test [c.name for c in derived]==[c.name for c in synthesize_concepts(world)] # deterministic selection
    @test all(c->!concept_holds(c,yes,Command("different","unseen_entity")),derived)
    @test isempty(synthesize_concepts(binary_concept_world(parity=true)))
    @test_throws ArgumentError synthesize_concepts(world;min_precision=1.1)
end

mutable struct ShiftingHost <: Environment
    state::Situation
    delivers::Bool
end
IXBlackFoxAGI.perceive(h::ShiftingHost) = copy(h.state)
IXBlackFoxAGI.commands(::ShiftingHost) = [Command("unseen_behavior","object")]
function IXBlackFoxAGI.transition!(h::ShiftingHost,::Command)
    if h.delivers
        push!(h.state,Fact("target","object"))
    end
    h.state
end

@testset "Metacognition uses measured errors to change operational strategy" begin
    a=Command("unseen_behavior","object")
    before=Situation([Fact("ready","object")])
    m=Mind(budget=45,seed=7)
    host=ShiftingHost(copy(before),true)
    for _ in 1:5
        host.state=copy(before)
        @test act!(m,host,a)==:learned
    end
    initial=prediction_profile(m,a)
    @test initial.predicted>=2
    @test initial.surprises==0
    @test initial.accuracy==1.0
    g=Goal(Fact("target","object"))
    candidate=PlanResult(:solved,[a],1)
    @test cognitive_choice(m,before,[a],g,candidate;min_predictions=2,
                           min_wilson=0.30).mode==:plan
    # The world changes while the learned model is frozen. It must react to
    # ground-truth failures, not to injected outcome labels or an oracle.
    host.delivers=false
    for _ in 1:18
        host.state=copy(before)
        @test act!(m,host,a;learning=false)==:frozen
    end
    drift=prediction_profile(m,a)
    @test drift.predicted>=18
    @test drift.surprises>=18
    @test drift.wilson_lower<0.50
    diagnosis=cognitive_choice(m,before,[a],g,candidate;
                                min_predictions=8,min_wilson=0.50)
    @test diagnosis.mode==:diagnose
    @test diagnosis.reason==:measured_prediction_unreliability
    @test audit_mind(m)
    @test prediction_profile(m,Command("missing","object")).accuracy===nothing
    @test_throws ArgumentError prediction_profile(m,a;window=0)
    @test_throws ArgumentError cognitive_choice(m,before,[a],g,candidate;min_wilson=2.0)
    mktempdir() do dir
        p=joinpath(dir,"cognitive-memory.toml")
        save_mind(m,p)
        restored=load_mind(p)
        @test audit_mind(restored)
        @test prediction_profile(restored,a).wilson_lower==drift.wilson_lower
        report=cognitive_report(restored)
        @test report["observations"]==5
        altered=deepcopy(restored)
        altered.surprises+=1
        @test !audit_mind(altered)
        altered=deepcopy(restored)
        empty!(altered.visits)
        @test !audit_mind(altered)
        altered=deepcopy(restored)
        altered.budget+=1
        @test !audit_mind(altered)
    end
end

@testset "Adaptive controller executes the diagnostic decision through Ada" begin
    a=Command("unseen_behavior","object")
    before=Situation([Fact("ready","object")])
    m=Mind(budget=25)
    host=ShiftingHost(copy(before),true)
    for _ in 1:5
        host.state=copy(before)
        @test act!(m,host,a)==:learned
    end
    host.delivers=false
    for _ in 1:9
        host.state=copy(before)
        @test act!(m,host,a;learning=false)==:frozen
    end
    host.state=copy(before)
    n=length(m.trace)
    r=pursue!(m,host,Goal(Fact("target","object"));max_steps=1,
              cognitive_control=true,min_prediction_evidence=5,
              min_prediction_wilson=0.6,learning=false)
    @test r.status==:step_limit
    @test r.exploratory_steps==1
    @test r.planned_steps==0
    @test length(m.trace)==n+1
    @test m.trace[end]["cognitive_mode"]=="diagnose"
    @test m.trace[end]["cognitive_reason"]=="measured_prediction_unreliability"
    @test audit_mind(m)
end

@testset "Regime change retains knowledge from unaffected contexts" begin
    w=WorldMemory()
    a=Command("contextual","object")
    s1=Situation([Fact("context_one","object")])
    s2=Situation([Fact("context_two","object")])
    old=union(s1,Situation([Fact("old_effect","object")]))
    fresh=union(s1,Situation([Fact("new_effect","object")]))
    other=union(s2,Situation([Fact("persistent_effect","object")]))
    for _ in 1:3
        @test learn!(w,s1,a,old)==:learned
        @test learn!(w,s2,a,other)==:learned
    end
    @test imagine(w,s1,a)==old
    @test imagine(w,s2,a)==other
    for _ in 1:3
        @test learn!(w,s1,a,fresh)==:learned
    end
    @test w.regime_resets==1
    @test imagine(w,s1,a)==fresh
    @test imagine(w,s2,a)==other
end

@testset "Self-generated inquiries remain native-gated and evidence grounded" begin
    a=Command("unseen_behavior","object")
    before=Situation([Fact("ready","object")])
    m=Mind(budget=30)
    host=ShiftingHost(copy(before),true)
    for _ in 1:5
        host.state=copy(before)
        @test act!(m,host,a)==:learned
    end
    host.delivers=false
    for _ in 1:9
        host.state=copy(before)
        @test act!(m,host,a;learning=false)==:frozen
    end
    inquiries=propose_inquiries(m)
    @test !isempty(inquiries)
    @test first(inquiries).action==("unseen_behavior",1)
    @test first(inquiries).reason==:prediction_failure
    @test_throws ArgumentError propose_inquiries(m;min_observations=-1)
    trace_length=length(m.trace)
    host.state=copy(before)
    @test inquire!(m,host;steps=1,permission=0)==0
    @test length(m.trace)==trace_length+1
    @test m.trace[end]["kind"]=="denied"
    @test inquire!(m,host;steps=2)==2
    @test m.trace[end]["cognitive_mode"]=="self_inquiry"
    @test audit_mind(m)
    @test_throws ArgumentError inquire!(m,host;steps=-1)
end
