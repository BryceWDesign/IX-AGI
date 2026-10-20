module Worlds
import ..IXAGI
const BF=IXAGI.BF
import ..IXAGI.IXBlackFoxAGI: perceive,commands,transition!

# Host-only task mechanics: NEVER passed to either learner.
mutable struct Relay <: BF.Environment
    state::BF.Situation
    panel::String
    signal_source::String
    verb::String
    inverted::Bool
    dispatches::Int
end
function Relay(panel::String;inverted::Bool=false,verb::String="flip",signal_source::String="hub")
    Relay(BF.Situation([BF.Fact("ready",panel), BF.Fact("station",signal_source)]),
          panel,signal_source,verb,inverted,0)
end
perceive(e::Relay)=copy(e.state)
commands(e::Relay)=[BF.Command(e.verb,e.panel)]
function transition!(e::Relay,a::BF.Command)
    a in commands(e) || throw(ArgumentError("not an allowed action"))
    e.dispatches+=1
    if !e.inverted
        push!(e.state,BF.Fact("beacon",e.signal_source))
    else
        push!(e.state,BF.Fact("jammed",e.signal_source))
    end
    nothing
end
relay_goal(e::Relay)=BF.Goal(BF.Situation([BF.Fact("beacon",e.signal_source)]))

mutable struct LocalSwitch <: BF.Environment
    state::BF.Situation
    object::String
    dispatches::Int
end
LocalSwitch(obj::String)=LocalSwitch(BF.Situation([BF.Fact("ready",obj)]),obj,0)
perceive(e::LocalSwitch)=copy(e.state)
commands(e::LocalSwitch)=[BF.Command("activate",e.object)]
function transition!(e::LocalSwitch,a::BF.Command)
    a in commands(e) || throw(ArgumentError("invalid command"))
    e.dispatches+=1
    push!(e.state,BF.Fact("active",e.object))
    nothing
end
local_goal(e::LocalSwitch)=BF.Goal(BF.Situation([BF.Fact("active",e.object)]))
end
