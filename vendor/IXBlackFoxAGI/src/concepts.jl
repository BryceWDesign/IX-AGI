"""Evidence-derived, object-invariant predictive concepts.

Concepts are new *bounded conjunctions of existing observed relations*, not
arbitrary invented sensory primitives or a claim of general abstraction.
The creator sees only stored, command-local before/after experiences.
Separate selection and untouched final test partitions limit model-selection leakage.
"""
struct LearnedConcept
    name::String
    action::Tuple{String,Int}
    conditions::Vector{Literal}
    fit_support::Int
    fit_precision::Float64
    holdout_support::Int
    holdout_precision::Float64
    holdout_recall::Float64
end

function concept_holds(c::LearnedConcept, s::Situation, a::Command)
    schema(a)==c.action || return false
    localstate=localize(s,a)
    all(l->holds(l,localstate),c.conditions)
end

function concept_candidates(examples::Vector{Tuple{Situation,Bool}};max_literals::Int=32)
    counts=Dict{Fact,Int}()
    for (s,_) in examples, f in s
        counts[f]=get(counts,f,0)+1
    end
    n=length(examples)
    eligible=sort!([f for (f,k) in counts if 2<=k<=n-2],by=factkey)
    # Deterministic bounded vocabulary; limit pair search complexity.
    eligible=first(eligible,min(max_literals,length(eligible)))
    literals=Literal[]
    for f in eligible
        push!(literals,Literal(f,true))
        push!(literals,Literal(f,false))
    end
    result=Vector{Vector{Literal}}()
    for i in eachindex(literals)
        push!(result,[literals[i]])
        for j in (i+1):length(literals)
            # A tautology or contradiction about the same relation is useless.
            literals[i].fact==literals[j].fact && continue
            push!(result,[literals[i],literals[j]])
        end
    end
    result
end

"""Induce validated new Boolean features for predicting whether an action changes state.
Conflicting outcomes for an identical observed context are omitted, rather
than labelled as certain. Both changed and unchanged cases are necessary.
"""
function synthesize_concepts(w::WorldMemory; min_contexts::Int=18,
                             min_fit_support::Int=4,min_holdout_support::Int=3,
                             min_precision::Float64=0.80,min_gain::Float64=0.15,
                             max_concepts::Int=3,max_literals::Int=24)
    0.0 < min_precision <= 1.0 || throw(ArgumentError("invalid precision"))
    min_contexts>=12 && min_fit_support>=1 && min_holdout_support>=1 &&
    max_concepts>=1 && 1<=max_literals<=128 || throw(ArgumentError("invalid synthesis limits"))
    library=LearnedConcept[]
    for (action,memory) in sort!(collect(w.actions),by=first)
        # Collapse repeated encounters, retaining only contexts with a stable
        # observed changed/unchanged outcome. Exact contexts are never split
        # between fitting, selection or final audit.
        grouped=Dict{Any,Vector{Experience}}()
        for e in memory.evidence
            push!(get!(grouped,statekey(e.before),Experience[]),e)
        end
        examples=Tuple{Situation,Bool}[]
        for k in sort!(collect(keys(grouped)),by=stabletext)
            observations=grouped[k]
            labels=unique(changed.(observations))
            length(labels)==1 || continue
            push!(examples,(copy(first(observations).before),only(labels)))
        end
        length(examples)>=min_contexts || continue
        positive=[e for e in examples if e[2]]
        negative=[e for e in examples if !e[2]]
        length(positive)>=6 && length(negative)>=6 || continue
        # Three *context-disjoint* sets: fitting, model selection and a final
        # untouched audit partition. No final-audit score is used to rank or
        # tune a candidate, reducing optimistic selection bias.
        fit=Tuple{Situation,Bool}[]
        selection=Tuple{Situation,Bool}[]
        audit=Tuple{Situation,Bool}[]
        for group in (positive,negative)
            for (i,e) in enumerate(group)
                bucket=i%5
                push!(bucket==0 ? audit : bucket==1 ? selection : fit,e)
            end
        end
        length(selection)>=4 && length(audit)>=6 || continue
        selection_base=count(e->e[2],selection)/length(selection)
        audit_base=count(e->e[2],audit)/length(audit)
        candidates=concept_candidates(fit;max_literals)
        selected=Tuple{Float64,Vector{Literal},Int,Float64}[]
        for condition in candidates
            fits=[e for e in fit if all(l->holds(l,e[1]),condition)]
            length(fits)>=min_fit_support || continue
            fitprecision=count(e->e[2],fits)/length(fits)
            fitprecision>=min_precision || continue
            passes=[e for e in selection if all(l->holds(l,e[1]),condition)]
            length(passes)>=2 || continue
            precision=count(e->e[2],passes)/length(passes)
            precision>=min_precision && precision>=selection_base+min_gain || continue
            recall=count(e->e[2],passes)/count(e->e[2],selection)
            score=precision+0.4*recall-0.02*length(condition)
            push!(selected,(score,condition,length(fits),fitprecision))
        end
        sort!(selected,by=x->(-x[1],length(x[2]),stabletext([
            (l.fact.predicate,collect(l.fact.terms),l.positive) for l in x[2]])))
        # Only the preselected candidates are assessed on the untouched audit
        # partition. Rejected candidates are *not* replaced using audit data.
        for (_,condition,fit_support,fitprecision) in first(selected,min(max_concepts,length(selected)))
            heldout=[e for e in audit if all(l->holds(l,e[1]),condition)]
            length(heldout)>=min_holdout_support || continue
            precision=count(e->e[2],heldout)/length(heldout)
            precision>=min_precision && precision>=audit_base+min_gain || continue
            recall=count(e->e[2],heldout)/count(e->e[2],audit)
            signature=[(l.fact.predicate,collect(l.fact.terms),l.positive) for l in condition]
            name="concept_"*digest((action,signature))[1:16]
            push!(library,LearnedConcept(name,action,copy(condition),fit_support,
                fitprecision,length(heldout),precision,recall))
        end
    end
    library
end
