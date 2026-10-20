using Test
using IXBlackFoxAGI
using IXBlackFoxAGI: Task

@testset "Ada/SPARK mandatory authority" begin
    @test isfile(guard_library())
    @test authorize(2;permission=1,risk=0,cost=1,budget=5,
                    samples=30,correct=29,cross_check=12)==2
    @test authorize(2;permission=0,risk=0,cost=1,budget=5,
                    samples=30,correct=30,cross_check=12)==0
    @test authorize(2;permission=1,risk=2,cost=1,budget=5,
                    samples=30,correct=30,cross_check=12)==0
    @test authorize(2;permission=1,risk=0,cost=1,budget=5,
                    samples=30,correct=15,cross_check=12)==0
    @test authorize(1;permission=1,risk=0,cost=1,budget=5)==1
    @test authorize(1;permission=1,risk=1,cost=1,budget=5)==0
    @test authorize(0;permission=0)==3
    @test authorize(2;permission=1,risk=0,cost=1,budget=5,
                    samples=1_000_001,correct=1_000_001,cross_check=20)==0
end

@testset "Dataset independence" begin
    d=make_dataset(Task(:a,:composed,0),11)
    @test length(d.fit)==160
    @test length(d.select)==100
    @test length(d.veto)==100
    @test length(d.blind)==100
    allobs=[(o.x,o.y) for part in (d.fit,d.select,d.veto,d.blind) for (o,_) in part]
    @test length(unique(allobs))==length(allobs)
    @test d.fit==make_dataset(Task(:a,:composed,0),11).fit
    @test_throws ArgumentError make_dataset(Task(:a,:composed,0),11,nfit=1681)
end

@testset "Composed program acquisition and ablation" begin
    for seed in 1:5
        t=Task(:novel,:composed,0); d=make_dataset(t,seed)
        a=Agent(beam=30)
        r=evolve!(a,t,d)
        @test r.status==:promoted
        @test r.strategy==:composed
        score,n=blind_score(a,t.id,d)
        @test score==n
        b=Agent(allow_composition=false)
        off=evolve!(b,t,d)
        @test off.status==:unsupported
    end
end

@testset "Independent held-out and negative controls" begin
    for (i,rule) in enumerate((:greater,:parity,:unstructured,:constant))
        t=Task(Symbol("world",i),rule,0);d=make_dataset(t,22+i)
        a=Agent(beam=30)
        r=evolve!(a,t,d)
        if rule==:unstructured
            @test r.status==:unsupported
            @test predict(a,t.id,Observation(3,1,9))===nothing
        elseif rule==:constant
            @test r.status==:no_change
        else
            @test r.status==:promoted
            @test first(blind_score(a,t.id,d)) >= 95
        end
    end
end

@testset "Governance, contradiction and rollback" begin
    t=Task(:learn,:greater,0);d=make_dataset(t,33)
    a=Agent(budget=10)
    r=evolve!(a,t,d;permission=0)
    @test r.status==:denied
    @test isempty(a.skills)
    @test a.budget==10
    @test evolve!(a,t,d).status==:promoted
    o=Observation(8,2,99)
    @test predict(a,t.id,o)===true
    @test observe!(a,t.id,o,false)==:contradiction
    @test observe!(a,t.id,o,false)==:quarantined
    @test predict(a,t.id,o)===nothing
    newd=make_dataset(Task(:learn,:greater,2),34)
    # A failed trial cannot replace an installed skill, and quarantine stays.
    old=a.skills[:learn].program
    a.budget=0
    @test evolve!(a,Task(:learn,:greater,2),newd).status==:denied
    @test a.skills[:learn].program===old
    @test :learn in a.quarantined
end

@testset "Checkpoint persistence, invalid settings and tampering" begin
    mktempdir() do dir
        t=Task(:learn,:greater,0);d=make_dataset(t,15)
        a=Agent(budget=20,beam=30)
        @test evolve!(a,t,d).status==:promoted
        file=joinpath(dir,"ck.toml")
        save_checkpoint(a,file)
        b=load_checkpoint(file)
        @test b.beam==30
        @test b.budget==18
        @test predict(b,:learn,Observation(8,3,9))===true
        open(file,"a") do io;write(io,"\n# corruption\n");end
        @test_throws ArgumentError load_checkpoint(file)
    end
end

@testset "Curriculum generates task proposals" begin
    a=Agent(budget=20,beam=30)
    rs=curriculum!(a,Task(:seed,:greater,0),seed=123,rounds=3)
    @test length(rs)==3
    @test :seed in keys(a.skills)
    @test proposed_challenge(Task(:a,:greater,0),1).rule==:composed
end

println("IX-BlackFox-AGI: Julia + mandatory Ada gate tests completed")
include("relational_tests.jl")

include("cognition_tests.jl")
