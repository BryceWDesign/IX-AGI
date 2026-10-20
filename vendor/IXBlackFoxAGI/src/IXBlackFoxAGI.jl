module IXBlackFoxAGI

using Random
using Statistics
using SHA
using TOML
using Libdl

export Observation, Task, Dataset, Node, Atom, Unary, Binary, Skill, Agent,
       authorize, guard_library, evaluate, make_dataset, evolve!, predict,
       proposed_challenge, save_checkpoint, load_checkpoint, program_size,
       blind_score, curriculum!, observe!, DevelopmentReport

include("guard.jl")
include("worlds.jl")
include("programs.jl")
include("development.jl")
include("checkpoint.jl")

include("relational.jl")
include("procedures.jl")
include("mind.jl")
include("audit.jl")
include("concepts.jl")
include("metacognition.jl")
include("inquiry.jl")
export Fact, Situation, Command, Goal, reached, WorldMemory, Mind, PlanResult,
       learn!, imagine, plan, Environment, perceive, commands, transition!,
       act!, explore!, investigate, pursue!, EpisodeResult, save_mind, load_mind,
       verify_trace, audit_mind, LearnedConcept, synthesize_concepts, concept_holds,
       PredictionProfile, prediction_profile, cognitive_choice, cognitive_report,
       Inquiry, propose_inquiries, inquire!
end # module
