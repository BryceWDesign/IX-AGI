using Random
using TOML
include(joinpath(@__DIR__,"..","experiments","Worlds.jl"))
using .Worlds

@testset "Relational induction, prerequisites and object transfer" begin
    w=WorldMemory()
    for (x,y) in (("a","b"),("c","d"),("f","g"))
        a=Command("opaque",x,y)
        before=Situation([Fact("p",x),Fact("edge",x,y)])
        after=Situation([Fact("p",y),Fact("edge",x,y)])
        @test learn!(w,before,a,after)==:learned
        blocked=Situation([Fact("p",x)])
        learn!(w,blocked,a,blocked)
        wrongplace=Situation([Fact("p",y),Fact("edge",x,y)])
        learn!(w,wrongplace,a,wrongplace)
    end
    s=Situation([Fact("p","never_seen"),Fact("edge","never_seen","also_new"),Fact("distractor","x")])
    a=Command("opaque","never_seen","also_new")
    predicted=imagine(w,s,a)
    @test predicted!==nothing
    @test Fact("p","also_new") in predicted
    @test Fact("p","never_seen") ∉ predicted
    @test Fact("distractor","x") in predicted
    @test imagine(w,Situation([Fact("p","never_seen")]),a)===nothing
    @test imagine(WorldMemory(),s,a)===nothing
    bad=union(s,Situation([Fact("changed","unbound_object")]))
    @test learn!(w,s,a,bad)==:unrepresentable
    @test w.unsupported_effects==1
    @test_throws ArgumentError Command("alias","a","a")
    @test_throws ArgumentError Goal(Situation([Fact("p")]),Situation([Fact("p")]))
    @test_throws ArgumentError WorldMemory(max_evidence=2)
end

@testset "Conditional outcome induction and conflicts" begin
    w=WorldMemory()
    for x in ("a","b","c")
        a=Command("flip",x)
        off=Situation([Fact("tag",x)])
        on=union(off,Situation([Fact("lit",x)]))
        learn!(w,off,a,on); learn!(w,on,a,off)
    end
    @test length(w.actions[("flip",1)].operators)==2
    a=Command("flip","new")
    off=Situation([Fact("tag","new")])
    on=union(off,Situation([Fact("lit","new")]))
    @test imagine(w,off,a)==on
    @test imagine(w,on,a)==off
    learn!(w,off,a,off)
    @test imagine(w,off,a)===nothing
end

@testset "Confirmed dynamics shift changes subsequent predictions" begin
    w=WorldMemory()
    s=Situation([Fact("tag","a")]);a=Command("unknownverb","a")
    original=union(s,Situation([Fact("lit","a")]))
    revised=union(s,Situation([Fact("warm","a")]))
    learn!(w,s,a,original);learn!(w,s,a,original)
    @test imagine(w,s,a)==original
    learn!(w,s,a,revised)
    @test imagine(w,s,a)===nothing
    learn!(w,s,a,revised)
    @test imagine(w,s,a)===nothing
    learn!(w,s,a,revised)
    @test w.regime_resets==1
    @test imagine(w,s,a)==revised
end

@testset "Independent randomized predicate and command semantics" begin
    for seed in 1:20
        rng=MersenneTwister(seed)
        predicates=["predicate_"*string(x) for x in randperm(rng,1000)[1:5]]
        indices=randperm(rng,4)[1:2]
        signs=rand(rng,Bool,2)
        verb="operator_"*string(rand(rng,1000:9999))
        w=WorldMemory()
        for object in ("training_a","training_b"), bits in 0:15
            values=[!iszero(bits & (1<<(i-1))) for i in 1:4]
            s=Situation(Fact(predicates[i],object) for i in 1:4 if values[i])
            after=copy(s)
            if all(values[i]==b for (i,b) in zip(indices,signs))
                push!(after,Fact(predicates[5],object))
            end
            learn!(w,s,Command(verb,object),after)
        end
        for bits in 0:15
            values=[!iszero(bits & (1<<(i-1))) for i in 1:4]
            s=Situation(Fact(predicates[i],"unseen") for i in 1:4 if values[i])
            actual=all(values[i]==b for (i,b) in zip(indices,signs))
            p=imagine(w,s,Command(verb,"unseen"))
            @test (p!==nothing)==actual
            if actual
                @test p==union(s,Situation([Fact(predicates[5],"unseen")]))
            end
        end
        @test w.regime_resets==0
    end
end

@testset "Native authority before adapter dispatch" begin
    m=Mind(budget=2)
    env=Worlds.Switchboard(3)
    s=perceive(env);a=first(commands(env))
    @test act!(m,env,a;permission=0)==:denied
    @test perceive(env)==s
    @test m.budget==2
    @test m.world.observations==0
    @test act!(m,env,a;risk=2)==:denied
    @test perceive(env)==s
    @test act!(m,env,Command("unknown","x"))==:invalid_command
    @test act!(m,env,a)==:learned
    @test m.budget==1
    @test perceive(env)!=s
    @test act!(m,env,a)==:learned
    @test act!(m,env,a)==:denied
    @test verify_trace(m.trace)
    @test_throws ArgumentError Mind(budget=-1)
end

@testset "Active acquisition, held-out planning and persistent memory" begin
    m=Mind(seed=8)
    Worlds.train!(m;seed=8)
    @test length(m.world.actions)==7
    @test m.world.observations==1980
    @test m.world.unsupported_effects==0
    for i in 1:3
        courier=Worlds.Courier(8000+i;nlocations=5,prefix="heldout"*string(i))
        g=Worlds.courier_goal(courier)
        old=m.world.observations
        r=pursue!(m,courier,g;max_steps=40,explore=false,learning=false)
        @test r.status==:achieved
        @test reached(g,perceive(courier))
        @test r.exploratory_steps==0
        @test r.surprises==0
        @test m.world.observations==old
        switches=Worlds.Switchboard(9000+i;n=7,prefix="new_switch"*string(i))
        g=Worlds.switch_goal(switches)
        r=pursue!(m,switches,g;explore=false,learning=false)
        @test r.status==:achieved
        @test r.surprises==0
        workshop=Worlds.Workshop(10000+i;n=4,prefix="new_job"*string(i))
        g=Worlds.workshop_goal(workshop)
        r=pursue!(m,workshop,g;explore=false,learning=false)
        @test r.status==:achieved
        @test r.surprises==0
    end
    composite=Worlds.Combined(Worlds.Courier(11001;nlocations=4,prefix="combined"),
                             Worlds.Workshop(11002;n=2,prefix="combined_job"))
    g=Worlds.combined_goal(composite)
    @test pursue!(m,composite,g;explore=false,learning=false).status==:achieved
    @test reached(g,perceive(composite))
    @test verify_trace(m.trace)
    # Abstractions come from two successful plans with different object bindings.
    for prefix in ("practice_a","practice_b")
        e=Worlds.Workshop(64;n=1,prefix=prefix)
        filter!(f->f.predicate=="colored",e.state)
        push!(e.state,Fact("raw",only(e.objects)))
        @test pursue!(m,e,Worlds.workshop_goal(e);explore=false,use_procedures=false).status==:achieved
    end
    @test count(IXBlackFoxAGI.usable,values(m.procedures))>=1
    e=Worlds.Workshop(88;n=1,prefix="macro_transfer")
    filter!(f->f.predicate=="colored",e.state)
    push!(e.state,Fact("raw",only(e.objects)))
    s=perceive(e);g=Worlds.workshop_goal(e)
    plain=plan(m.world,s,commands(e),g)
    composed=plan(m.world,s,commands(e),g;procedures=m.procedures)
    @test plain.status==composed.status==:solved
    @test composed.expansions<plain.expansions
    @test length(composed.commands)==length(plain.commands)==3
    mktempdir() do dir
        p=joinpath(dir,"mind.toml")
        save_mind(m,p)
        restored=load_mind(p)
        @test restored.world.observations==m.world.observations
        @test restored.budget==m.budget
        @test length(restored.procedures)==length(m.procedures)
        @test verify_trace(restored.trace)
        @test audit_mind(restored)
        mismatched=deepcopy(restored)
        push!(first(values(mismatched.world.actions)).evidence[1].before,Fact("fabricated"))
        @test !audit_mind(mismatched)
        env=Worlds.Courier(12000;nlocations=5,prefix="after_restart")
        @test pursue!(restored,env,Worlds.courier_goal(env);explore=false,learning=false).status==:achieved
        corrupted=deepcopy(restored.trace)
        first(corrupted)["command"]="tampered"
        @test !verify_trace(corrupted)
        open(p,"a") do io; write(io,"\n#corruption\n");end
        @test_throws ArgumentError load_mind(p)
    end
end

@testset "Missing native library has no fallback" begin
    mktempdir() do dir
        src=joinpath(dir,"src")
        mkpath(src)
        cp(joinpath(@__DIR__,"..","src","guard.jl"),joinpath(src,"guard.jl"))
        isolated=Module(:MissingAuthorityTest)
        Core.eval(isolated,:(using Libdl))
        Base.include(isolated,joinpath(src,"guard.jl"))
        @test_throws ErrorException Base.invokelatest(isolated.authorize,1;permission=1,risk=0,cost=1,budget=10)
    end
end

@testset "Planning refuses unknown dynamics and respects finite search" begin
    env=Worlds.Courier(17)
    s=perceive(env)
    g=Goal(Fact("unreachable","no_such_object"))
    @test plan(WorldMemory(),s,commands(env),g).status==:unknown
    @test plan(WorldMemory(),s,commands(env),Goal()).status==:satisfied
    @test_throws ArgumentError plan(WorldMemory(),s,commands(env),g;max_expansions=0)
    @test_throws ArgumentError pursue!(Mind(),env,g;max_steps=-1)
end
