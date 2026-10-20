struct Observation
    x::Int
    y::Int
    domain::Int
end

"""Hidden rule is accessible to the TEST HOST, not to program synthesis."""
struct Task
    id::Symbol
    rule::Symbol
    shift::Int
end

"""Four disjoint partitions: candidate fit, selection, veto, untouched report."""
struct Dataset
    fit::Vector{Tuple{Observation,Bool}}
    select::Vector{Tuple{Observation,Bool}}
    veto::Vector{Tuple{Observation,Bool}}
    blind::Vector{Tuple{Observation,Bool}}
end

function truth(t::Task, o::Observation)::Bool
    if t.rule == :greater
        return o.x > o.y + t.shift
    elseif t.rule == :parity
        return isodd(o.x + o.y)
    elseif t.rule == :composed
        return xor(o.x > o.y, isodd(o.x))
    elseif t.rule == :constant
        return true
    elseif t.rule == :unstructured
        return mod(o.x * o.x + 3 * o.x * o.y + 7 * o.y * o.y + t.shift, 17) < 8
    else
        throw(ArgumentError("unknown evaluation world"))
    end
end

function make_dataset(t::Task, seed::Integer; nfit=160, nselect=100, nveto=100, nblind=100)
    all(n -> n > 0, (nfit, nselect, nveto, nblind)) || throw(ArgumentError("empty partition"))
    total = nfit+nselect+nveto+nblind
    total <= 1681 || throw(ArgumentError("sensor space exhausted; cannot guarantee disjoint observations"))
    rng = MersenneTwister(seed)
    pairs = [(x,y) for x in -20:20 for y in -20:20]
    shuffle!(rng, pairs)
    make_group(start, n, domain) = [(Observation(pairs[i][1], pairs[i][2], domain),
                                       truth(t, Observation(pairs[i][1], pairs[i][2], domain)))
                                      for i in start:(start+n-1)]
    a=make_group(1,nfit,1)
    b=make_group(nfit+1,nselect,2)
    c=make_group(nfit+nselect+1,nveto,3)
    d=make_group(nfit+nselect+nveto+1,nblind,4)
    return Dataset(a,b,c,d)
end
