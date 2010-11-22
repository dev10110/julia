## 1-dimensional ranges ##

struct Range{T<:Real} <: Tensor{T,1}
    start::T
    step::T
    stop::T

    Range{T}(start::T, step::T, stop::T) = new(start, step, stop)
    Range(start, step, stop) = new(promote(start, step, stop)...)
end

struct Range1{T<:Real} <: Tensor{T,1}
    start::T
    stop::T

    Range1{T}(start::T, stop::T) = new(start, stop)
    Range1(start, stop) = new(promote(start, stop)...)
end

typealias Ranges Union(Range,Range1)

step(r::Range)  = r.step
step(r::Range1) = one(r.start)

show(r::Range)  = print(r.start,':',r.step,':',r.stop)
show(r::Range1) = print(r.start,':',r.stop)

numel(r::Ranges) = length(r)
size(r::Ranges) = tuple(length(r))
length{T<:Int}(r::Range{T}) = max(0, div((r.stop-r.start+r.step), r.step))
length{T<:Int}(r::Range1{T}) = max(0, (r.stop-r.start + 1))
length(r::Range) = max(0, int32((r.stop-r.start) / r.step + 1))
length(r::Range1) = max(0, int32(r.stop-r.start + 1))

isempty(r::Range) = (r.step > 0 ? r.stop < r.start : r.stop > r.start)
isempty(r::Range1) = (r.stop < r.start)

start{T<:Int}(r::Range{T}) = r.start
done{T<:Int}(r::Range{T}, i) = (r.step < 0 ? (i < r.stop) : (i > r.stop))
next{T<:Int}(r::Range{T}, i) = (i, i+r.step)

start(r::Range1) = r.start
done(r::Range1, i) = (i > r.stop)
next(r::Range1, i) = (i, i+1)

# floating point ranges need to keep an integer counter
start(r::Range) = (1, r.start)
done{T}(r::Range{T}, st) =
    (r.step < 0 ? (st[2]::T < r.stop) : (st[2]::T > r.stop))
next{T}(r::Range{T}, st) =
    (st[2]::T, (st[1]::Int+1, r.start + st[1]::Int*r.step))

colon(start::Real, stop::Real, step::Real) = Range(start, step, stop)
colon(start::Real, stop::Real) = Range1(start, stop)

ref(r::Range, i::Index) =
    (x = r.start + (i-1)*r.step;
     (r.step < 0 ? (x < r.stop) : (x > r.stop)) ? throw(BoundsError()) : x)
ref(r::Range1, i::Index) = (x = r.start + (i-1);
                            i < 1 || done(r,x) ? throw(BoundsError()) : x)

## linear operations on 1-d ranges ##

(-)(r::Ranges) = Range(-r.start, -step(r), -r.stop)

(+)(x::Real, r::Range ) = Range(x+r.start, r.step, x+r.stop)
(+)(x::Real, r::Range1) = Range1(x+r.start, x+r.stop)
(+)(r::Ranges, x::Real) = x+r

(-)(x::Real, r::Ranges) = Range(x-r.start, -step(r), x-r.stop)
(-)(r::Range , x::Real) = Range(r.start-x, r.step, r.stop-x)
(-)(r::Range1, x::Real) = Range1(r.start-x, r.stop-x)

(*)(x::Real, r::Ranges) = Range(x*r.start, x*step(r), x*r.stop)
(*)(r::Ranges, x::Real) = x*r

(/)(r::Ranges, x::Real) = Range(r.start/x, step(r)/x, r.stop/x)

## adding and subtracting ranges ##

# TODO: if steps combine to zero, create sparse zero vector

function (+)(r1::Ranges, r2::Ranges)
    if length(r1) != length(r2); error("shape mismatch"); end
    Range(r1.start+r2.start, step(r1)+step(r2), r1.stop+r2.stop)
end

function (-)(r1::Ranges, r2::Ranges)
    if length(r1) != length(r2); error("shape mismatch"); end
    Range(r1.start-r2.start, step(r1)-step(r2), r1.stop-r2.stop)
end

## N-dimensional ranges ##

struct NDRange{N}
    ranges::NTuple{N,Any}
    empty::Bool
    NDRange(r::())           =new(r,false)
    NDRange(r::(Any,))       =new(r,isempty(r[1]))
    NDRange(r::(Any,Any))    =new(r,isempty(r[1])||isempty(r[2]))
    NDRange(r::(Any,Any,Any))=new(r,isempty(r[1])||isempty(r[2])||isempty(r[3]))
    NDRange(r::Tuple)        =new(r,any(map(isempty,r)))
    NDRange(rs...) = NDRange(rs)
end

start(r::NDRange{0}) = false
done(r::NDRange{0}, st) = st
next(r::NDRange{0}, st) = ((), true)

start(r::NDRange) = { start(r.ranges[i]) | i=1:length(r.ranges) }
done(r::NDRange, st) = r.empty || !bool(st)

function next{N}(r::NDRange{N}, st)
    nxt = ntuple(N, i->next(r.ranges[i], st[i]))
    vals = map(n->n[1], nxt)
    
    for itr=1:N
        ri = r.ranges[itr]
        ni = nxt[itr][2]
        if !done(ri, ni)
            st[itr] = ni
            return (vals, st)
        else
            st[itr] = start(ri)
        end
    end
    (vals, false)
end

function next(r::NDRange{2}, st)
    (r1, r2) = r.ranges
    (v1, n1) = next(r1, st[1])
    (v2, n2) = next(r2, st[2])
    vals = (v1, v2)
    
    if !done(r1, n1)
        st[1] = n1
        return (vals, st)
    else
        st[1] = start(r1)
    end
    if !done(r2, n2)
        st[2] = n2
        return (vals, st)
    end
    (vals, false)
end
