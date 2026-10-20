module IXAGI
using Random
using Statistics
using LinearAlgebra
using SHA
using TOML

# Run the actual, unmodified BlackFox Julia cognitive engine and its native Ada ABI.
# This vendor is licensed separately under vendor/IXBlackFoxAGI/LICENSE.
include(joinpath(@__DIR__, "..", "vendor", "IXBlackFoxAGI", "src", "IXBlackFoxAGI.jl"))
const BF = IXBlackFoxAGI

include("hemisphere.jl")
include("callosum.jl")
include("organism.jl")
include("persistence.jl")

export BF, DualOrganism, CounterHemisphere, NeuralCallosum, NeuralPacket,
       BoundedEvidence, predict_counter, counter_learn!, signal!, adjust!,
       inspect!, choose!, step!, live!, decision_log, save_organism,
       load_organism, Prediction, Decision, self_check
end
