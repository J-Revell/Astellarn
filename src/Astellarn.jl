__precompile__()
module Astellarn
    const ASTELLARN_VERSION = "v0.2.9"

    using Crayons
    using StaticArrays
    using Printf
    #using SIMD

    import Base.&, Base.|, Base.~, Base.<<, Base.>>, Base.⊻, Base.!, Base.bswap
    import Base.isempty, Base.isone, Base.isequal
    import Base.getindex, Base.setindex!, Base.push!
    import Base.iterate, Base.length, Base.eltype, Base.size, Base.IndexStyle
    import Base.copy!
    import Base.show

    include("../deps/config.jl")
    include("bitboard.jl")
    include("pieces.jl")
    include("zobrist.jl")
    include("timeman.jl")
    include("utils.jl")
    include("parameters.jl")
    include("board.jl")
    include("types.jl")
    include("fen.jl")
    include("magic.jl")
    include("attacks.jl")
    include("move.jl")
    include("movegen.jl")
    include("movecount.jl")
    include("perft.jl")
    include("masks.jl")
    include("evaluate.jl")
    include("syzygy.jl")
    include("transposition.jl")
    include("thread.jl")
    include("moveorder.jl")
    include("history.jl")
    include("search.jl")
    include("repl.jl")
    include("uci.jl")


    export Bitboard, Board, Piece, PieceType, Color, Magic, Move, Undo, MoveStack, UndoStack
    export @newgame, @move, @random, @engine, @importfen, @perft

    export importfen, exportfen
    export pawns, kings, bishops, knights, rooks, queens, enemy, friendly, occupied, empty, rooklike, bishoplike
    export checkers, pinned, cancastlekingside, cancastlequeenside
    export ischeck, islegal, ischeckmate, isstalemate, isdrawbymaterial
    export monkey!, perft, engine!

    export static_exchange_evaluator

    export WHITE, BLACK
    export PAWN, KNIGHT, BISHOP, ROOK, KING, QUEEN
    export WHITEPAWN, WHITEKNIGHT, WHITEBISHOP, WHITEROOK, WHITEQUEEN, WHITEKING
    export BLACKPAWN, BLACKKNIGHT, BLACKBISHOP, BLACKROOK, BLACKQUEEN, BLACKKING

    export __KNIGHT_PROMO, __BISHOP_PROMO, __ROOK_PROMO, __QUEEN_PROMO, SEE_VALUES, PawnKingTable, evaluate, initEvalInfo

    export evaluate_knights, evaluate_bishops, evaluate_rooks, evaluate_queens, evaluate_kings, evaluate_pins, evaluate_threats, evaluate_initiative, evaluate_space, evaluate_passed

    export uci_main

end
