function pack_node(n::Atom)
    n.name in (:x,:y,:zero,:one) || throw(ArgumentError("unknown atom in checkpoint"))
    return Dict{String,Any}("kind"=>"atom","op"=>String(n.name))
end
function pack_node(n::Unary)
    n.op in (:odd,:not) || throw(ArgumentError("unknown unary op"))
    return Dict{String,Any}("kind"=>"unary","op"=>String(n.op),"child"=>pack_node(n.child))
end
function pack_node(n::Binary)
    n.op in (:add,:sub,:gt,:eq,:xor,:and,:or) || throw(ArgumentError("unknown binary op"))
    return Dict{String,Any}("kind"=>"binary","op"=>String(n.op),
                            "left"=>pack_node(n.left),"right"=>pack_node(n.right))
end
function unpack_node(d::AbstractDict,depth::Int=0)::Node
    depth<=10 || throw(ArgumentError("expression nesting too deep"))
    kind=get(d,"kind",nothing)
    op=Symbol(get(d,"op","invalid"))
    if kind=="atom"
        op in (:x,:y,:zero,:one) || throw(ArgumentError("unknown atom"))
        return Atom(op)
    elseif kind=="unary"
        op in (:odd,:not) || throw(ArgumentError("unknown unary"))
        haskey(d,"child") || throw(ArgumentError("missing child"))
        return Unary(op,unpack_node(d["child"],depth+1))
    elseif kind=="binary"
        op in (:add,:sub,:gt,:eq,:xor,:and,:or) || throw(ArgumentError("unknown binary"))
        haskey(d,"left") && haskey(d,"right") || throw(ArgumentError("missing operands"))
        return Binary(op,unpack_node(d["left"],depth+1),unpack_node(d["right"],depth+1))
    end
    throw(ArgumentError("unknown AST node"))
end

"""Checksum detects accidental tampering, NOT a signed or attacker-resistant attestation."""
function save_checkpoint(a::Agent,path::AbstractString)
    skills = [Dict{String,Any}(
        "id"=>String(id),"program"=>pack_node(s.program),
        "fit_correct"=>s.fit_correct,"fit_total"=>s.fit_total,
        "select_correct"=>s.select_correct,"select_total"=>s.select_total,
        "veto_correct"=>s.veto_correct,"veto_total"=>s.veto_total)
        for (id,s) in sort!(collect(a.skills),by=p->String(p.first))]
    state=Dict{String,Any}(
        "format"=>"ixbf-cognitive-checkpoint-1", "budget"=>a.budget,
        "allow_composition"=>a.allow_composition, "beam"=>a.beam,
        "quarantined"=>sort!(String.(collect(a.quarantined))),
        "disagreement"=>Dict(String(k)=>v for (k,v) in a.disagreement),
        "skills"=>skills)
    io=IOBuffer();TOML.print(io,state;sorted=true)
    bytes=take!(io)
    write(path,bytes)
    write(path*".sha256",bytes2hex(SHA.sha256(bytes))*"\n")
    return path
end

function checked_int(v,low,high)
    v isa Integer && low<=v<=high || throw(ArgumentError("invalid checkpoint integer"))
    return Int(v)
end
function load_checkpoint(path::AbstractString)
    bytes=read(path)
    expected=strip(read(path*".sha256",String))
    bytes2hex(SHA.sha256(bytes))==expected || throw(ArgumentError("checkpoint digest mismatch"))
    d=TOML.parse(String(bytes))
    get(d,"format",nothing)=="ixbf-cognitive-checkpoint-1" || throw(ArgumentError("checkpoint version mismatch"))
    config=get(d,"allow_composition",nothing)
    config isa Bool || throw(ArgumentError("invalid composition flag"))
    a=Agent(budget=checked_int(get(d,"budget",nothing),0,1_000_000),
            beam=checked_int(get(d,"beam",nothing),4,64),allow_composition=config)
    for row in get(d,"skills",[])
        id=Symbol(row["id"])
        haskey(a.skills,id) && throw(ArgumentError("duplicate checkpoint skill"))
        p=unpack_node(row["program"])
        program_size(p)<=127 || throw(ArgumentError("oversized cognitive program"))
        values=map(k->checked_int(row[k],0,1_000_000),
                  ("fit_correct","fit_total","select_correct","select_total","veto_correct","veto_total"))
        values[1]<=values[2] && values[3]<=values[4] && values[5]<=values[6] ||
            throw(ArgumentError("incoherent evidence in checkpoint"))
        a.skills[id]=Skill(p,values...)
    end
    for v in get(d,"quarantined",[])
        id=Symbol(v)
        haskey(a.skills,id) || throw(ArgumentError("quarantined id without skill"))
        push!(a.quarantined,id)
    end
    for (id,v) in get(d,"disagreement",Dict())
        a.disagreement[Symbol(id)]=checked_int(v,0,1_000_000)
    end
    return a
end
