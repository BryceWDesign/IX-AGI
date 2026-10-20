"""Fingerprint the runtime source and native build configuration, excluding generated files."""
function implementation_digest()
    root=dirname(@__DIR__)
    paths=String["Project.toml","ada/ix_guard.gpr","ada/guard_test.gpr"]
    for directory in ("src","ada/src")
        for (base,_,files) in walkdir(joinpath(root,directory)), name in files
            push!(paths,relpath(joinpath(base,name),root))
        end
    end
    payload=join([replace(p,'\\'=>'/')*":"*bytes2hex(sha256(read(joinpath(root,p))))
                  for p in sort!(paths)],"\n")
    bytes2hex(sha256(payload))
end

"""Reconstruct the learned model and procedure library from the event trace.
This checks internal consistency. A host that fabricates an entire trace remains
outside the trust boundary; this is not an independent environment attestation.
"""
function audit_mind(m::Mind)
    verify_trace(m.trace) || return false
    replay=WorldMemory(max_evidence=m.world.max_evidence)
    library=Dict{String,Procedure}()
    for (i,event) in enumerate(m.trace)
        kind=event["kind"]
        if kind=="transition"
            before=readfacts(event["before"]);after=readfacts(event["after"])
            action=Command(String(event["command"]),Tuple(String.(event["args"])))
            predicted=imagine(replay,before,action)
            recorded=event["predicted"]===false ? nothing : readfacts(event["predicted"])
            predicted==recorded || return false
            (predicted!==nothing && predicted!=after)==event["surprise"] || return false
            if haskey(event,"permission")
                decision=authorize(1;permission=event["permission"],risk=event["risk"],
                                   cost=1,budget=event["budget"]+1)
                decision==event["decision"]==1 || return false
            end
            if event["learned"]!="frozen"
                string(learn!(replay,before,action,after))==event["learned"] || return false
            end
        elseif kind=="denied"
            if haskey(event,"permission")
                authorize(1;permission=event["permission"],risk=event["risk"],cost=1,
                          budget=event["budget"])==event["decision"] || return false
            end
        elseif kind=="episode_achieved"
            goal=Goal(readfacts(event["present"]),readfacts(event["absent"]))
            final=readfacts(event["final"])
            reached(goal,final) || return false
            start=Int(event["trace_start"])
            1<=start<=i || return false
            segment=m.trace[start:i-1]
            all(e->e["kind"]=="transition",segment) || return false
            if !isempty(segment)
                readfacts(last(segment)["after"])==final || return false
            end
            actions=[Command(String(e["command"]),Tuple(String.(e["args"]))) for e in segment]
            remember_procedures!(library,actions)
        else
            return false
        end
    end
    # Verify secondary cognitive accounting independently of saved counters.
    # External invalid-command attempts increment denied but have no trace.
    # Therefore only a lower bound is assertable for denied actions.
    sum(get(e,"surprise",false)==true for e in m.trace if get(e,"kind","")=="transition")==m.surprises || return false
    count(e->get(e,"kind","")=="denied",m.trace)<=m.denied || return false
    visits=Dict{String,Int}()
    for e in m.trace
        get(e,"kind","")=="transition" || continue
        before=readfacts(e["before"])
        action=Command(String(e["command"]),Tuple(String.(e["args"])))
        key=visitkey(before,action)
        visits[key]=get(visits,key,0)+1
    end
    visits==m.visits || return false
    last_transition=findlast(e->get(e,"kind","")=="transition",m.trace)
    if last_transition!==nothing
        m.budget==m.trace[last_transition]["budget"] || return false
    end
    replay.observations==m.world.observations || return false
    replay.unsupported_effects==m.world.unsupported_effects || return false
    replay.regime_resets==m.world.regime_resets || return false
    Set(keys(replay.actions))==Set(keys(m.world.actions)) || return false
    for (key,memory) in replay.actions
        stored=m.world.actions[key]
        memory.regime==stored.regime || return false
        length(memory.evidence)==length(stored.evidence) || return false
        for (a,b) in zip(memory.evidence,stored.evidence)
            a.before==b.before && a.added==b.added && a.removed==b.removed || return false
        end
    end
    Set(keys(library))==Set(keys(m.procedures)) || return false
    all(library[k].bindings==m.procedures[k].bindings for k in keys(library))
end
