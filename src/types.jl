# The Move struct stores information in bits as follows...
# FLAG | mov to | m from
# 0000 | 000000 | 000000
"""
    Move

`DataType` used to store the information encoding a move.
"""
struct Move
    val::UInt16
end


"""
    MoveStack

`DataType` for storing lists of moves.
"""
mutable struct MoveStack <: AbstractArray{Move, 1}
    list::Vector{Move}
    idx::Int
end


"""
    Undo

`DataType` for storing the minimal amount of information to restore a `Board` object to its previous position.
"""
struct Undo
    checkers::Bitboard
    pinned::Bitboard
    castling::UInt8
    enpass::UInt8
    captured::Piece
    halfmovecount::UInt16
    hash::ZobristHash
    psqteval::Int32
    pkhash::ZobristHash
end


"""
    UndoStack

`DataType` for storing lists of `Undos`.
"""
mutable struct UndoStack <: AbstractArray{Undo, 1}
    list::Vector{Undo}
    idx::Int
end


"""
    ThreadStats

`DataType` for storing the stats of the thread during a search.
"""
mutable struct ThreadStats
    depth::Int
    seldepth::Int
    nodes::Int
    tbhits::Int
end


# ButterflyTable for storing move histories.
# The datatype is ugly, so this alias makes it more tidy.
# BTABLE[i][j][k]
# [i] => colour
# [j] => from
# [k] => to
# https://www.chessprogramming.org/index.php?title=Butterfly_Boards
const CounterTable = MArray{Tuple{2},MArray{Tuple{6},MArray{Tuple{64},Move,1,64},1,6},1,2}
const ButterflyHistTable =  Vector{Vector{Vector{Int}}}
const CounterHistTable = Vector{Vector{Vector{Vector{Int}}}}
CounterTable() = CounterTable([[repeat([MOVE_NONE], 64) for j in 1:6] for k in 1:2])
ButterflyHistTable() = ButterflyHistTable([[zeros(Int, 64) for i in 1:64] for j in 1:2])
CounterHistTable() = CounterHistTable([[[zeros(Int, 64) for j in 1:6] for k in 1:64] for l in 1:6])

"""
    MoveOrder

`DataType` for storing information used in ordering moves.
"""
mutable struct MoveOrder
    type::UInt8
    stage::UInt8
    movestack::MoveStack
    values::Vector{Int32}
    margin::Int
    noisy_size::Int
    quiet_size::Int
    tt_move::Move
    killer1::Move
    killer2::Move
    counter::Move
end


mutable struct PKT_Entry
    pkhash::ZobristHash
    passed::Bitboard
    score::Int
end


const PawnKingTable = Dict{UInt16, PKT_Entry}


"""
    Thread

`DataType` used to store information used by the thread during its search.
"""
mutable struct Thread
    timeman::TimeManagement
    board::Board
    pv::Vector{MoveStack} # 1st element is the PV, rest are preallocated tmp PVs
    ss::ThreadStats
    moveorders::Vector{MoveOrder}
    movestack::MoveStack
    piecestack::PieceStack
    evalstack::Vector{Int}
    quietstack::Vector{MoveStack}
    history::ButterflyHistTable
    counterhistory::CounterHistTable
    followhistory::CounterHistTable
    killer1s::MoveStack
    killer2s::MoveStack
    cmtable::CounterTable
    pktable::PawnKingTable
    stop::Bool
end
