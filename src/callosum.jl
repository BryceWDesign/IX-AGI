"""One-tick-delayed numerical activity, not prose or agent conversation."""
struct NeuralPacket
    tick::Int
    source::Symbol
    activity::Vector{Float64}
    novelty::Float64
    uncertainty::Float64
end
mutable struct NeuralCallosum
    width::Int
    left_to_right::Matrix{Float64}
    right_to_left::Matrix{Float64}
    gain_lr::Float64
    gain_rl::Float64
    tick::Int
    previous_left::Vector{Float64}
    previous_right::Vector{Float64}
    last_received_left::Vector{Float64}
    last_received_right::Vector{Float64}
    lesions::Bool
    plasticity::Bool
    phase_period::Int
    updates::Int
end
function NeuralCallosum(;width::Int=32,seed::Int=13,lesions::Bool=false,plasticity::Bool=true,phase_period::Int=0)
    4<=width<=512 || throw(ArgumentError("invalid callosal width"))
    0<=phase_period<=128 || throw(ArgumentError("invalid phase period"))
    rng=MersenneTwister(seed)
    # Sparse topographic mapping, signed excitatory and inhibitory influences.
    a=zeros(width,width);b=zeros(width,width)
    for i in 1:width
        a[i,i]=0.4;b[i,i]=0.4
        for j in 1:width
            if i!=j && rand(rng)<0.07
                a[i,j]=rand(rng,Bool) ? 0.05 : -0.05
                b[i,j]=rand(rng,Bool) ? 0.05 : -0.05
            end
        end
    end
    NeuralCallosum(width,a,b,1.0,1.0,0,zeros(width),zeros(width),
                   zeros(width),zeros(width),lesions,plasticity,phase_period,0)
end
function valid_activity(v::Vector{Float64},width::Int)
    length(v)==width && all(isfinite,v) && all(abs.(v).<=1e6)
end
function bounded(v::Vector{Float64})
    tanh.(clamp.(v,-20.0,20.0))
end
function signal!(c::NeuralCallosum,left::Vector{Float64},right::Vector{Float64};
                 uncertainty_l::Float64=0.5,uncertainty_r::Float64=0.5)
    valid_activity(left,c.width) && valid_activity(right,c.width) ||
        throw(ArgumentError("malformed internal activity"))
    all(x->0<=x<=1,(uncertainty_l,uncertainty_r)) ||
        throw(ArgumentError("invalid uncertainty"))
    c.tick+=1
    phase_gate=c.phase_period==0 ? 1.0 : (0.10+0.90*(0.5+0.5*cos(2*pi*c.tick/c.phase_period)))
    if c.lesions
        fill!(c.last_received_left,0.0)
        fill!(c.last_received_right,0.0)
    else
        # Previous-tick activity prevents instantaneous answer copying.
        c.last_received_left=bounded((phase_gate*c.gain_rl) .* (c.right_to_left*c.previous_right))
        c.last_received_right=bounded((phase_gate*c.gain_lr) .* (c.left_to_right*c.previous_left))
    end
    c.previous_left=copy(left);c.previous_right=copy(right)
    (NeuralPacket(c.tick,:right,c.last_received_left,0.0,uncertainty_r),
     NeuralPacket(c.tick,:left,c.last_received_right,0.0,uncertainty_l))
end
function adjust!(c::NeuralCallosum;left_error::Float64,right_error::Float64)
    all(x->isfinite(x) && 0<=x<=1,(left_error,right_error)) ||
        throw(ArgumentError("invalid external feedback"))
    (c.lesions || !c.plasticity) && return nothing
    # Outcome-driven, bounded gain plasticity. No peer-agreement reward.
    lr_signal=right_error-left_error
    # When the right model predicts correctly and the left does not,
    # increase right-to-left transmission; reverse this when left is stronger.
    c.gain_rl=clamp(c.gain_rl-0.025*lr_signal,0.05,1.5)
    c.gain_lr=clamp(c.gain_lr+0.025*lr_signal,0.05,1.5)
    # Bounded, outcome-modulated eligibility traces modify *routing weights*,
    # not just scalar gain. Anti-Hebbian changes when peer influence was poor.
    a=c.previous_left
    b=c.previous_right
    scale=0.006 / max(1.0, norm2(a)*norm2(b))
    c.left_to_right .+= (scale*lr_signal).*(b*transpose(a))
    c.right_to_left .-= (scale*lr_signal).*(a*transpose(b))
    c.left_to_right .= clamp.(c.left_to_right,-1.0,1.0)
    c.right_to_left .= clamp.(c.right_to_left,-1.0,1.0)
    c.updates+=1
    nothing
end
