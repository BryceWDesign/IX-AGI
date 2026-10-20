struct CommandPattern
    name::String
    args::Tuple{Vararg{String}}
end
mutable struct Procedure
    steps::Vector{CommandPattern}
    bindings::Set{String}
end
procedurekey(p::Procedure)=stabletext([(s.name,s.args) for s in p.steps])
usable(p::Procedure)=length(p.bindings)>=2

"""Discover reusable action-sequence abstractions by object anti-unification.
There is no built-in navigate, deliver, assemble, or other domain macro.
"""
function abstract_procedure(actions::Vector{Command})
    variables=Dict{String,String}()
    steps=CommandPattern[]
    objects=String[]
    for a in actions
        args=String[]
        for x in a.args
            if !haskey(variables,x)
                variables[x]="?"*string(length(variables)+1)
                push!(objects,x)
            end
            push!(args,variables[x])
        end
        push!(steps,CommandPattern(a.name,Tuple(args)))
    end
    Procedure(steps,Set([stabletext(objects)]))
end

function remember_procedures!(library::Dict{String,Procedure},actions::Vector{Command};
                              max_length::Int=4,capacity::Int=128)
    for n in 2:min(max_length,length(actions)), start in 1:(length(actions)-n+1)
        p=abstract_procedure(actions[start:start+n-1])
        key=procedurekey(p)
        if haskey(library,key)
            union!(library[key].bindings,p.bindings)
        elseif length(library)<capacity
            library[key]=p
        end
    end
    library
end

function matchpattern(p::CommandPattern,a::Command,bindings::Dict{String,String})
    p.name==a.name && length(p.args)==length(a.args) || return nothing
    out=copy(bindings)
    for (variable,value) in zip(p.args,a.args)
        if haskey(out,variable)
            out[variable]==value || return nothing
        else
            value in values(out) && return nothing
            out[variable]=value
        end
    end
    out
end

"""Ground discovered procedures using the command catalogue and learned models.
Every primitive prediction is checked; a macro never bypasses authority at execution.
"""
function procedure_edges(w::WorldMemory,s::Situation,actions::Vector{Command},library;
                         min_support::Int=2,max_bindings::Int=128)
    edges=Tuple{Situation,Vector{Command}}[]
    for p in sort!([p for p in values(library) if usable(p)],
                   by=p->(-length(p.bindings),-length(p.steps),procedurekey(p)))
        partial=[(s,Command[],Dict{String,String}())]
        for pattern in p.steps
            next=Tuple{Situation,Vector{Command},Dict{String,String}}[]
            for (state,path,binding) in partial, a in actions
                length(next)>=max_bindings && break
                bound=matchpattern(pattern,a,binding)
                bound===nothing && continue
                future=imagine(w,state,a;min_support)
                (future===nothing || future==state) && continue
                push!(next,(future,vcat(path,[a]),bound))
            end
            partial=next
            isempty(partial) && break
        end
        for (future,path,_) in partial
            future==s || push!(edges,(future,path))
        end
    end
    edges
end
