"""Falsifiable, independently named synthetic feature-transfer campaign.
The hidden rule lives ONLY in this experiment and is not passed to the learner.
This script emits actual outcomes; it does not contain a hand-written pass line.
"""
using IXBlackFoxAGI
using Random
using TOML
using SHA

function campaign_case(seed::Int;nonlinear::Bool=false)
    rng=MersenneTwister(seed)
    predicates=["opaque_"*string(x) for x in randperm(rng,100_000)[1:8]]
    verb="verb_"*string(rand(rng,100_000:999_999))
    action=Command(verb,"training_identity")
    learned=WorldMemory()
    for bits in 0:63
        before=Situation(Fact(predicates[i],"training_identity") for i in 1:6
                         if !iszero(bits&(1<<(i-1))))
        outcome=nonlinear ? isodd(count_ones(bits)) : (bits&3)==3
        after=copy(before)
        outcome && push!(after,Fact("unseen_consequence","training_identity"))
        learn!(learned,before,action,after)
    end
    concepts=synthesize_concepts(learned)
    # Every evaluation example has at least one *new sensor* absent from the
    # training corpus, and a different object identifier.
    correct=0;baseline=0;positive=0;false_positives=0
    for bits in 64:255
        before=Situation(Fact(predicates[i],"heldout_identity") for i in 1:8
                         if !iszero(bits&(1<<(i-1))))
        target=nonlinear ? isodd(count_ones(bits&63)) : (bits&3)==3
        guess=any(c->concept_holds(c,before,Command(verb,"heldout_identity")),concepts)
        correct+=Int(guess==target)
        baseline+=Int(!target)
        positive+=Int(target)
        false_positives+=Int(guess && !target)
    end
    Dict("seed"=>seed,"nonlinear_negative_control"=>nonlinear,
         "train_contexts"=>64,"test_contexts"=>192,"new_sensor_shift"=>true,
         "new_object_identity"=>true,"concepts"=>length(concepts),
         "correct"=>correct,"always_no_change_correct"=>baseline,
         "positive_cases"=>positive,"false_positives"=>false_positives)
end

function run_campaign()
    rows=Dict{String,Any}[]
    for seed in 701:710, nonlinear in (false,true)
        push!(rows,campaign_case(seed;nonlinear))
    end
    outdir=joinpath(@__DIR__,"..","results","cognition")
    mkpath(outdir)
    report=Dict("source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "implementation_sha256"=>IXBlackFoxAGI.implementation_digest(),
        "tested_rule_family"=>"2-way conjunction and 6-way parity negative control",
        "sensors_training"=>6,"sensors_test"=>8,
        "simulated_environment_only"=>true,
        "true_agi_demonstrated"=>false,"results"=>rows)
    open(joinpath(outdir,"campaign.toml"),"w") do io
        TOML.print(io,report;sorted=true)
    end
    for row in rows
        println("seed=",row["seed"]," parity_control=",row["nonlinear_negative_control"],
                " concepts=",row["concepts"]," correct=",row["correct"],"/",row["test_contexts"],
                " baseline=",row["always_no_change_correct"]," false_positive=",row["false_positives"])
    end
    report
end

run_campaign()
