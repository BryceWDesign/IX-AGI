#!/usr/bin/env julia
# Matched-evidence comparisons: left-alone, connected, disconnected and unseen rule reversal.
# This is a narrow capability test, not an AGI certification.
using IXAGI
using TOML
include(joinpath(@__DIR__,"Worlds.jl"))
using .Worlds
const B=IXAGI.BF
function train(seed::Int,mode::Symbol)
    h=DualOrganism(;seed,mode)
    for i in 1:6
        e=Worlds.Relay("train_"*string(seed)*"_"*string(i))
        a=only(B.commands(e))
        inspect!(h,B.perceive(e),a)
        step!(h,e,Decision(:investigate,a,:matched_training,nothing,0.))
    end
    h
end
function evaluate(seed::Int,mode::Symbol;inverted::Bool=false)
    h=train(seed,mode)
    e=Worlds.Relay("heldout_"*string(seed);inverted)
    g=Worlds.relay_goal(e)
    d=choose!(h,e,g)
    if d.action!==nothing
        step!(h,e,d;permission=1)
    end
    Dict{String,Any}("seed"=>seed,"mode"=>string(mode),"inverted"=>inverted,
        "success"=>B.reached(g,B.perceive(e)),"dispatches"=>e.dispatches,
        "selection"=>string(d.mode),"reason"=>string(d.reason),
        "right_evidence"=>h.right.observations,"native_trace_verified"=>B.verify_trace(h.left.trace),
        "native_bound"=>isfile(B.guard_library()))
end
function main()
    rows=Dict{String,Any}[]
    for seed in 1:20, inverted in (false,true)
        for mode in (:coupled,:lesioned,:late_fusion)
            push!(rows,evaluate(seed,mode;inverted))
        end
    end
    success(name,inv)=count(x->x["mode"]==name && x["inverted"]==inv && x["success"],rows)
    summary=Dict{String,Any}(
        "conditions"=>"matched training, held-out panels, blinded reversal",
        "seed_count"=>20,"cases"=>length(rows),
        "connected_nominal_success"=>success("coupled",false),
        "lesioned_nominal_success"=>success("lesioned",false),
        "late_fusion_nominal_success"=>success("late_fusion",false),
        "connected_reversal_success"=>success("coupled",true),
        "lesioned_reversal_success"=>success("lesioned",true),
        "late_fusion_reversal_success"=>success("late_fusion",true),
        "completed"=>true,"scope"=>"specific relational side-effect family, NOT general intelligence")
    out=joinpath(@__DIR__,"..","results","native_comparison.toml")
    mkpath(dirname(out))
    open(out,"w") do io
        TOML.print(io,Dict("summary"=>summary,"cases"=>rows))
    end
    println("Native matched-evidence comparison:")
    for (k,v) in sort(collect(summary),by=first);println(k,"=",v);end
    @assert all(x->x["native_trace_verified"] && x["native_bound"],rows)
end
main()
