#-----------------------------------------------------------------------------# StatLearn
abstract type Updater end
Base.show(io::IO, u::Updater) = print(io, name(u))
init(u::Updater, p) = u

struct StatLearn{U <: Updater, L <: Loss, P <: Penalty} <: StochasticStat{(1, 0), 1}
    β::VecF
    gx::VecF
    λfactor::VecF
    loss::L
    penalty::P
    updater::U
end
function StatLearn(p::Integer, l::Loss, pen::Penalty, λ::Float64, u::Updater = SPGD())
    StatLearn(zeros(p), zeros(p), ones(p) * λ, l, pen, init(u, p))
end
function Base.show(io::IO, o::StatLearn)
    header(io, name(o))
    println(io)
    print_item(io, "β", o.β')
    print_item(io, "λ factor", o.λfactor')
    print_item(io, "Loss", o.loss)
    print_item(io, "Penalty", o.penalty)
    print_item(io, "Updater", o.updater, false)
end
coef(o::StatLearn) = o.β
predict(o::StatLearn, x::AVec) = dot(x, o.β)
predict(o::StatLearn, x::AMat) = x * o.β




function fit!(o::StatLearn, x::AVec, y::Real, γ::Float64)
    xβ = dot(x, o.β)
    g = deriv(o.loss, y, xβ)
    o.gx .= g .* x
    update!(o, γ)
end

function fitbatch!(o::StatLearn, x::AMat, y::AVec, γ::Float64)
    xβ = x * o.β
    g = deriv(o.loss, y, xβ)
    @inbounds for j in eachindex(o.gx)
        o.gx[j] = 0.0
        for i in eachindex(y)
            o.gx[j] += g[i] * x[i, j]
        end
    end
    scale!(o.gx, 1 / length(y))
    update!(o, γ)
end




#-----------------------------------------------------------------------# SPGD
"Stochastic Proximal Gradient Descent"
struct SPGD <: Updater
    η::Float64
    SPGD(η::Float64 = 1.0) = new(η)
end
function update!(o::StatLearn{SPGD}, γ)
    γη = γ * o.updater.η
    for j in eachindex(o.β)
        @inbounds o.β[j] = prox(o.penalty, o.β[j] - γη * o.gx[j], γη * o.λfactor[j])
    end
end
#-----------------------------------------------------------------------# MSPGD
"Max SPGD.  Only Update βⱼ with the largest xⱼ"
struct MSPGD <: Updater
    η::Float64
    MSPGD(η::Float64 = 1.0) = new(η)
end
function update!(o::StatLearn{MSPGD}, γ)
    γη = γ * o.updater.η
    j = indmax(x)
    @inbounds o.β[j] = prox(o.penalty, o.β[j] - γη * o.gx[j], γη * o.λfactor[j])
end

#-----------------------------------------------------------------------# ADAGRAD
"Adaptive Gradient. Elementwise learning rate version of SPGD"
struct ADAGRAD <: Updater
    η::Float64
    H::VecF
    ADAGRAD(η::Float64 = 1.0, p::Integer = 0) = new(η, zeros(p))
end
init(u::ADAGRAD, p::Integer) = ADAGRAD(u.η, p)
function update!(o::StatLearn{ADAGRAD}, γ)
    U = o.updater
    @inbounds for j in eachindex(o.β)
        U.H[j] = smooth(U.H[j], o.gx[j] ^ 2, γ)
        s = U.η * γ * inv(sqrt(U.H[j]) + ϵ)
        o.β[j] = prox(o.penalty, o.β[j] - s * o.gx[j], s * o.λfactor[j])
    end
end
