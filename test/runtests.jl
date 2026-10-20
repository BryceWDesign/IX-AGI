using Test
using IXAGI
include(joinpath(@__DIR__,"..","experiments","Worlds.jl"))
using .Worlds
const B=IXAGI.BF

@testset "Actual BlackFox core and native Ada gate required" begin
    @test isfile(B.guard_library())
    @test B.authorize(1;permission=0,risk=0,cost=1,budget=3)==0
    @test B.authorize(1;permission=1,risk=0,cost=1,budget=3)==1
    @test B.authorize(1;permission=1,risk=2,cost=1,budget=3)==0
    @test B.authorize(2;permission=1,risk=0,cost=1,budget=3,
                      samples=16,correct=16,cross_check=8)==2
end

@testset "Machine signal, one-tick delay, lesions and finite-state rejection" begin
    c=NeuralCallosum(width=8,seed=2)
    left=ones(8);right=fill(0.5,8)
    l,r=signal!(c,left,right)
    @test all(iszero,l.activity)
    @test all(iszero,r.activity)
    l,r=signal!(c,left,right)
    @test any(x->!iszero(x),l.activity)
    @test any(x->!iszero(x),r.activity)
    old=copy(c.left_to_right)
    adjust!(c;left_error=0.,right_error=1.)
    @test c.updates==1
    @test c.left_to_right!=old
    @test all(isfinite,c.left_to_right)
    @test_throws ArgumentError signal!(c,fill(NaN,8),right)
    @test_throws ArgumentError signal!(c,left,right;uncertainty_l=2.0)
    lesion=NeuralCallosum(width=8,lesions=true)
    signal!(lesion,left,right)
    l,r=signal!(lesion,left,right)
    @test all(iszero,l.activity)
    @test all(iszero,r.activity)
    adjust!(lesion;left_error=0.,right_error=1.)
    @test lesion.updates==0
end

@testset "Complementary representation learns effects BlackFox cannot" begin
    h=DualOrganism(seed=20)
    for i in 1:5
        e=Worlds.Relay("training_"*string(i))
        a=only(B.commands(e))
        inspect!(h,B.perceive(e),a)
        d=Decision(:investigate,a,:training,nothing,0.)
        @test step!(h,e,d)==:unrepresentable
        @test e.dispatches==1
        @test h.left.world.unsupported_effects==i
    end
    unseen=Worlds.Relay("unseen_panel")
    s=B.perceive(unseen);a=only(B.commands(unseen))
    @test B.imagine(h.left.world,s,a)===nothing
    p=predict_counter(h.right,s,a)
    @test p!==nothing
    @test B.Fact("beacon","hub") in p.state
    @test p.confidence>=0.7
    @test B.reached(Worlds.relay_goal(unseen),p.state)
    d=choose!(h,unseen,Worlds.relay_goal(unseen))
    @test d.mode==:act
    @test d.reason==:callosal_delta_alignment
    # Different goal should not be satisfied simply because an unrelated
    # prediction emitted a nonzero vector.
    unrelated=B.Goal(B.Situation([B.Fact("unrelated","hub")]))
    @test choose!(h,Worlds.Relay("another_panel"),unrelated).mode==:hold
    @test h.channel.tick>=2
    @test self_check(h)
end

@testset "Denial changes no world state; permission required for same action" begin
    h=DualOrganism(seed=31)
    for i in 1:5
        e=Worlds.Relay("t_"*string(i));a=only(B.commands(e))
        inspect!(h,B.perceive(e),a)
        @test step!(h,e,Decision(:investigate,a,:training,nothing,0.))==:unrepresentable
    end
    e=Worlds.Relay("new")
    d=choose!(h,e,Worlds.relay_goal(e))
    @test d.action!==nothing
    before=B.perceive(e); budget=h.left.budget
    @test step!(h,e,d;permission=0)==:denied
    @test e.dispatches==0
    @test B.perceive(e)==before
    @test h.left.budget==budget
    @test step!(h,e,d)==:unrepresentable
    @test e.dispatches==1
    @test B.reached(Worlds.relay_goal(e),B.perceive(e))
    @test self_check(h)
end

@testset "Ablation: severed signal prevents cross-hemisphere effect" begin
    h=DualOrganism(seed=31,mode=:lesioned)
    for i in 1:5
        e=Worlds.Relay("t_"*string(i));a=only(B.commands(e))
        inspect!(h,B.perceive(e),a)
        step!(h,e,Decision(:investigate,a,:training,nothing,0.))
    end
    e=Worlds.Relay("new")
    @test predict_counter(h.right,B.perceive(e),only(B.commands(e)))!==nothing
    @test choose!(h,e,Worlds.relay_goal(e)).mode==:hold
    @test e.dispatches==0
end

@testset "Negative controls: no memorized world rule, no unseen action oracle" begin
    h=DualOrganism()
    e=Worlds.Relay("not_seen")
    @test choose!(h,e,Worlds.relay_goal(e)).mode==:hold
    @test predict_counter(h.right,B.perceive(e),only(B.commands(e)))===nothing
    @test live!(h,e,Worlds.relay_goal(e);allow_explore=false)==:held
    @test e.dispatches==0
    # Distinct action vocabulary cannot borrow evidence from flip.
    for i in 1:4
        w=Worlds.Relay("a"*string(i));a=only(B.commands(w))
        inspect!(h,B.perceive(w),a)
        step!(h,w,Decision(:investigate,a,:train,nothing,0.))
    end
    different=Worlds.Relay("never",verb="opaque_action")
    @test predict_counter(h.right,B.perceive(different),only(B.commands(different)))===nothing
    @test choose!(h,different,Worlds.relay_goal(different)).mode==:hold
end

@testset "Checkpoint round trip and tamper rejection" begin
    h=DualOrganism(seed=41)
    for i in 1:5
        e=Worlds.Relay("t"*string(i));a=only(B.commands(e))
        inspect!(h,B.perceive(e),a)
        step!(h,e,Decision(:investigate,a,:train,nothing,0.))
    end
    mktempdir() do tmp
        prefix=joinpath(tmp,"brain")
        save_organism(h,prefix)
        recovered=load_organism(prefix)
        @test recovered.right.observations==h.right.observations
        @test recovered.channel.tick==h.channel.tick
        @test recovered.channel.left_to_right==h.channel.left_to_right
        @test self_check(recovered)
        probe=Worlds.Relay("unseen")
        @test choose!(recovered,probe,Worlds.relay_goal(probe)).mode==:act
        open(prefix*".callosum.toml","a") do io
            write(io,"\n# changed without hash update\n")
        end
        @test_throws ArgumentError load_organism(prefix)
    end
end

@testset "Important control: late fusion can match coupled decision outcome" begin
    h=DualOrganism(seed=12,mode=:late_fusion)
    for i in 1:5
        e=Worlds.Relay("train_late_"*string(i));a=only(B.commands(e))
        inspect!(h,B.perceive(e),a)
        step!(h,e,Decision(:investigate,a,:training,nothing,0.))
    end
    e=Worlds.Relay("new_late")
    d=choose!(h,e,Worlds.relay_goal(e))
    @test d.mode==:act
    @test d.reason==:late_fusion_prediction
    @test step!(h,e,d)==:unrepresentable
    @test B.reached(Worlds.relay_goal(e),B.perceive(e))
end

@testset "Contradictory dynamics evidence eventually revises independent hypothesis" begin
    h=DualOrganism(seed=61)
    for i in 1:6
        e=Worlds.Relay("old_"*string(i));a=only(B.commands(e))
        inspect!(h,B.perceive(e),a)
        step!(h,e,Decision(:investigate,a,:train,nothing,0.))
    end
    before=Worlds.Relay("candidate")
    p=predict_counter(h.right,B.perceive(before),only(B.commands(before)))
    @test B.Fact("beacon","hub") in p.state
    for i in 1:12
        e=Worlds.Relay("changed_"*string(i);inverted=true)
        a=only(B.commands(e))
        inspect!(h,B.perceive(e),a)
        step!(h,e,Decision(:investigate,a,:diagnose,nothing,0.))
    end
    candidate=Worlds.Relay("candidate2")
    p=predict_counter(h.right,B.perceive(candidate),only(B.commands(candidate)))
    @test p!==nothing
    @test B.Fact("jammed","hub") in p.state
    @test B.Fact("beacon","hub") ∉ p.state
    @test h.right.surprises>0
    @test h.right.observations==18
end
