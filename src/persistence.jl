"""Checkpoint is persisted alongside BlackFox's independently verified Mind snapshot."""
function factdict(f::BF.Fact)
    Dict("predicate"=>f.predicate,"terms"=>collect(f.terms))
end
function dictfact(x)
    BF.Fact(String(x["predicate"]),Tuple(String.(x["terms"])))
end
function matrixrows(m::Matrix{Float64})
    [collect(m[i,:]) for i in axes(m,1)]
end
function rowsmatrix(rows,width)
    length(rows)==width || throw(ArgumentError("invalid channel matrix rows"))
    all(x->length(x)==width,rows) || throw(ArgumentError("invalid channel columns"))
    vals=Matrix{Float64}(undef,width,width)
    for i in 1:width,j in 1:width
        vals[i,j]=Float64(rows[i][j])
    end
    all(isfinite,vals) || throw(ArgumentError("nonfinite channel matrix"))
    vals
end
function save_organism(h::DualOrganism,prefix::AbstractString)
    mkpath(dirname(abspath(prefix)))
    BF.save_mind(h.left,prefix*".blackfox.toml")
    memories=Dict{String,Any}[]
    for ((name,arity),evidence) in sort!(collect(h.right.memory),by=first)
        push!(memories,Dict{String,Any}("name"=>name,"arity"=>arity,
            "evidence"=>[Dict{String,Any}("context"=>collect(x.context),
                "added"=>[factdict(f) for f in x.added],
                "removed"=>[factdict(f) for f in x.removed],
                "episode"=>x.episode) for x in evidence]))
    end
    c=h.channel
    data=Dict{String,Any}(
        "format"=>1,"evidence"=>memories,"max_per_schema"=>h.right.max_per_schema,
        "right_observations"=>h.right.observations,
        "right_surprises"=>h.right.surprises,"right_episodes"=>h.right.episodes,
        "left_count"=>h.left_count,"right_count"=>h.right_count,
        "left_correct"=>h.left_correct,"right_correct"=>h.right_correct,
        "step_count"=>h.step_count,"modes"=>h.modes,
        "late_fusion"=>h.late_fusion,
        "channel"=>Dict{String,Any}(
            "width"=>c.width,"tick"=>c.tick,"gain_lr"=>c.gain_lr,
            "gain_rl"=>c.gain_rl,"lesions"=>c.lesions,"plasticity"=>c.plasticity,
            "updates"=>c.updates,"phase_period"=>c.phase_period,
            "left_to_right"=>matrixrows(c.left_to_right),
            "right_to_left"=>matrixrows(c.right_to_left),
            "previous_left"=>c.previous_left,"previous_right"=>c.previous_right,
            "received_left"=>c.last_received_left,
            "received_right"=>c.last_received_right))
    txt=sprint(io->TOML.print(io,data;sorted=true))
    path=prefix*".callosum.toml"
    write(path*".tmp",txt)
    mv(path*".tmp",path;force=true)
    write(path*".sha256",bytes2hex(sha256(codeunits(txt)))*"\n")
    prefix
end
function load_organism(prefix::AbstractString)
    path=prefix*".callosum.toml"
    filesize(path)<=32*1024*1024 || throw(ArgumentError("oversize checkpoint"))
    text=read(path,String)
    bytes2hex(sha256(codeunits(text)))==strip(read(path*".sha256",String)) ||
        throw(ArgumentError("callosal checkpoint digest mismatch"))
    payload=TOML.parse(text)
    payload["format"]==1 || throw(ArgumentError("unsupported checkpoint"))
    cdata=payload["channel"]
    width=Int(cdata["width"])
    4<=width<=512 || throw(ArgumentError("invalid channel width"))
    mode=Bool(payload["late_fusion"]) ? :late_fusion : (Bool(cdata["lesions"]) ? :lesioned : :coupled)
    h=DualOrganism(;width,mode)
    h.left=BF.load_mind(prefix*".blackfox.toml")
    h.channel.left_to_right=rowsmatrix(cdata["left_to_right"],width)
    h.channel.right_to_left=rowsmatrix(cdata["right_to_left"],width)
    h.channel.gain_lr=Float64(cdata["gain_lr"])
    h.channel.gain_rl=Float64(cdata["gain_rl"])
    h.channel.tick=Int(cdata["tick"])
    h.channel.updates=Int(cdata["updates"])
    h.channel.phase_period=Int(cdata["phase_period"])
    0<=h.channel.phase_period<=128 || throw(ArgumentError("invalid phase in checkpoint"))
    h.channel.plasticity=Bool(cdata["plasticity"])
    for (field,key) in ((:previous_left,"previous_left"),(:previous_right,"previous_right"),
                        (:last_received_left,"received_left"),(:last_received_right,"received_right"))
        v=Float64.(cdata[key])
        valid_activity(v,width) || throw(ArgumentError("invalid activity in checkpoint"))
        setfield!(h.channel,field,v)
    end
    (isfinite(h.channel.gain_lr) && isfinite(h.channel.gain_rl) &&
        0.05<=h.channel.gain_lr<=1.5 && 0.05<=h.channel.gain_rl<=1.5) ||
        throw(ArgumentError("invalid channel gains"))
    h.right=CounterHemisphere(;max_per_schema=Int(payload["max_per_schema"]))
    for m in payload["evidence"]
        key=(String(m["name"]),Int(m["arity"]))
        h.right.memory[key]=[BoundedEvidence(Tuple(String.(e["context"])),
            [dictfact(f) for f in e["added"]],
            [dictfact(f) for f in e["removed"]],Int(e["episode"])) for e in m["evidence"]]
        length(h.right.memory[key])<=h.right.max_per_schema ||
            throw(ArgumentError("oversized evidence buffer"))
    end
    h.right.observations=Int(payload["right_observations"])
    h.right.surprises=Int(payload["right_surprises"])
    h.right.episodes=Int(payload["right_episodes"])
    h.left_count=Int(payload["left_count"]);h.right_count=Int(payload["right_count"])
    h.left_correct=Int(payload["left_correct"]);h.right_correct=Int(payload["right_correct"])
    h.step_count=Int(payload["step_count"])
    h.modes=[Dict{String,Any}(x) for x in payload["modes"]]
    self_check(h) || throw(ArgumentError("inconsistent restored organism"))
    h
end
