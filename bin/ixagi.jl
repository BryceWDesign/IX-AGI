#!/usr/bin/env julia
using IXAGI
include(joinpath(@__DIR__, "..", "experiments", "Worlds.jl"))
using .Worlds

function main()
    h=DualOrganism(seed=12)
    println("IX-AGI / REAL NATIVE JULIA + ADA EXECUTION")
    println("Training via observed action consequences. No world rules delivered to either model.")
    for i in 1:6
        w=Worlds.Relay("train_panel_"*string(i))
        a=first(IXAGI.BF.commands(w))
        IXAGI.inspect!(h,IXAGI.BF.perceive(w),a)
        d=Decision(:investigate,a,:gather_evidence,nothing,0.0)
        status=step!(h,w,d)
        println("train=",i,"  learning_status=",status," native_dispatches=",w.dispatches)
    end
    e=Worlds.Relay("unseen_panel")
    g=Worlds.relay_goal(e)
    println("BlackFox predicted: ",IXAGI.BF.imagine(h.left.world,IXAGI.BF.perceive(e),first(IXAGI.BF.commands(e)))!==nothing)
    pred=predict_counter(h.right,IXAGI.BF.perceive(e),first(IXAGI.BF.commands(e)))
    println("Independent hemisphere predicted: ",pred!==nothing)
    decision=choose!(h,e,g)
    println("decision=",decision.mode," reason=",decision.reason)
    before=IXAGI.BF.perceive(e)
    refused=step!(h,e,decision;permission=0)
    println("ADA DENIAL: ",refused,"  state_unchanged=",IXAGI.BF.perceive(e)==before,"  dispatches=",e.dispatches)
    allowed=step!(h,e,decision;permission=1)
    println("ADA ACCEPT: ",allowed,"  dispatches=",e.dispatches,"  goal=",IXAGI.BF.reached(g,IXAGI.BF.perceive(e)))
    println("BlackFox audit valid: ",IXAGI.BF.verify_trace(h.left.trace))
    println("Dual cognition audit valid: ",self_check(h))
    out=joinpath(@__DIR__, "..", "results", "demo_check")
    save_organism(h,out)
    println("Checkpoint saved: ",out)
end
main()
