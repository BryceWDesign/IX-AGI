"""Bounded, typed cognitive expression trees. No eval, shell, files or network effects."""
abstract type Node end
struct Atom <: Node
    name::Symbol
end
struct Unary <: Node
    op::Symbol
    child::Node
end
struct Binary <: Node
    op::Symbol
    left::Node
    right::Node
end

function evaluate(n::Atom, o::Observation)::Int
    n.name == :x && return o.x
    n.name == :y && return o.y
    n.name == :zero && return 0
    n.name == :one && return 1
    throw(ArgumentError("unknown atom"))
end
function evaluate(n::Unary, o::Observation)::Int
    v = evaluate(n.child,o)
    n.op == :odd && return Int(isodd(v))
    n.op == :not && return Int(v == 0)
    throw(ArgumentError("unknown unary operation"))
end
function evaluate(n::Binary, o::Observation)::Int
    a=evaluate(n.left,o); b=evaluate(n.right,o)
    n.op == :add && return a+b
    n.op == :sub && return a-b
    n.op == :gt && return Int(a>b)
    n.op == :eq && return Int(a==b)
    n.op == :xor && return Int(xor(a != 0,b != 0))
    n.op == :and && return Int(a != 0 && b != 0)
    n.op == :or && return Int(a != 0 || b != 0)
    throw(ArgumentError("unknown binary operation"))
end
program_size(::Atom)=1
program_size(n::Unary)=1+program_size(n.child)
program_size(n::Binary)=1+program_size(n.left)+program_size(n.right)

"""Recursive vocabulary generation; complete task rules are not enumerated."""
function atom_programs()
    x=Atom(:x); y=Atom(:y); z=Atom(:zero); one=Atom(:one)
    numeric = Node[x,y,z,one,
        Binary(:add,x,y),Binary(:sub,x,y),Binary(:sub,y,x),
        Binary(:add,y,one),Binary(:add,x,one),
        Binary(:sub,y,one),Binary(:sub,x,one)]
    raw = Node[]
    for a in numeric
        push!(raw,Unary(:odd,a))
    end
    for a in numeric, b in numeric
        push!(raw,Binary(:gt,a,b))
        push!(raw,Binary(:eq,a,b))
    end
    push!(raw,Atom(:one))
    return raw
end

function accuracy(n::Node, data::Vector{Tuple{Observation,Bool}})::Int
    count(item -> (evaluate(n,item[1]) != 0) == item[2], data)
end

"""Select candidates using FIT data only; SELECT data is never used to grow expressions."""
function synthesize(fit::Vector{Tuple{Observation,Bool}}; compose::Bool=true, beam::Int=20)
    4 <= beam <= 64 || throw(ArgumentError("beam must be between 4 and 64"))
    base = atom_programs()
    # The beam contains diverse semantic signatures, not just the top scoring clones.
    ranked = sort(base, by=p -> (-accuracy(p,fit),program_size(p)))
    seen = Set{String}()
    chosen = Node[]
    # Always include these general-purpose concepts; no complete task rule is supplied.
    anchors = Node[Binary(:gt,Atom(:x),Atom(:y)),
                   Unary(:odd,Atom(:x)),Unary(:odd,Atom(:y)),
                   Binary(:eq,Atom(:x),Atom(:y))]
    for p in vcat(anchors, ranked)
        signature = join((evaluate(p,o) != 0 ? "1" : "0" for (o,_) in fit))
        if !(signature in seen)
            push!(chosen,p);push!(seen,signature)
        end
        length(chosen)>=beam && break
    end
    candidates = copy(base)
    if compose
        for i in eachindex(chosen), j in i:length(chosen)
            a=chosen[i]; b=chosen[j]
            for op in (:xor,:and,:or)
                push!(candidates,Binary(op,a,b))
            end
        end
    end
    # Deduplicate on fit signatures and prefer smaller programs.
    best = Dict{String,Node}()
    for p in candidates
        sig=join((evaluate(p,o) != 0 ? "1" : "0" for (o,_) in fit))
        if !haskey(best,sig) || program_size(p)<program_size(best[sig])
            best[sig]=p
        end
    end
    return sort!(collect(values(best)),by=p->(-accuracy(p,fit),program_size(p)))
end
